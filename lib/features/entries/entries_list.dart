import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'entry_tree.dart';
import 'entry_tree_expansion.dart';
import 'manual_entry_dialog.dart';

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
    final tiersAsync = ref.watch(breakRuleTiersProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final countPausedTimeAsBreak = settings?.countPausedTimeAsBreak ?? false;

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return Center(child: Text(l10n.entriesEmpty));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        final jiraWorklogsById =
            jiraWorklogsAsync.value ?? const <String, JiraWorklogRow>{};
        final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
        final years = buildEntryTree(
          finished,
          tiers: tiers,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
        final expanded = ref.watch(entryTreeExpansionProvider);
        final rows = flattenEntryTree(years, expanded);
        final localeName = Localizations.localeOf(context).languageCode;
        void toggle(String key) =>
            ref.read(entryTreeExpansionProvider.notifier).toggle(key);

        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => switch (rows[index]) {
            EntryTreeYearRow(:final year) => _GroupHeader(
              depth: 0,
              label: '${year.year}',
              total: year.totalDuration,
              breakDuration: year.breakDuration,
              warningTooltip: _rolledUpBreakTooltip(
                l10n,
                year.insufficientBreakDays,
              ),
              expanded: expanded.contains(yearTreeKey(year.year)),
              onTap: () => toggle(yearTreeKey(year.year)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeMonthRow(:final month) => _GroupHeader(
              depth: 1,
              label: DateFormat.MMMM(
                localeName,
              ).format(DateTime(month.year, month.month)),
              total: month.totalDuration,
              breakDuration: month.breakDuration,
              warningTooltip: _rolledUpBreakTooltip(
                l10n,
                month.insufficientBreakDays,
              ),
              expanded: expanded.contains(
                monthTreeKey(month.year, month.month),
              ),
              onTap: () => toggle(monthTreeKey(month.year, month.month)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeWeekRow(:final week) => _GroupHeader(
              depth: 2,
              label: l10n.entriesWeekHeader(
                week.isoWeek,
                '${formatDate(week.firstDay, dateStyle, localeName)} – '
                '${formatDate(week.lastDay, dateStyle, localeName)}',
              ),
              total: week.totalDuration,
              breakDuration: week.breakDuration,
              warningTooltip: _rolledUpBreakTooltip(
                l10n,
                week.insufficientBreakDays,
              ),
              expanded: expanded.contains(
                weekTreeKey(week.monday, week.year, week.month),
              ),
              onTap: () =>
                  toggle(weekTreeKey(week.monday, week.year, week.month)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeDayRow(:final day) => _GroupHeader(
              depth: 3,
              label: _dayLabel(day.day, l10n, dateStyle, localeName),
              total: day.totalDuration,
              breakDuration: day.breakDuration,
              warningTooltip: day.isBreakInsufficient
                  ? l10n.entriesBreakInsufficientTooltip
                  : null,
              expanded: expanded.contains(dayTreeKey(day.day)),
              onTap: () => toggle(dayTreeKey(day.day)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeEntriesRow(:final day) => Padding(
              // Line the card up under its own day header, not the week's.
              padding: const EdgeInsets.only(left: _depthInset * 3),
              child: _DayEntriesBlock(
                entries: day.entries,
                projectsById: projectsById,
                jiraWorklogsById: jiraWorklogsById,
                timeStyle: timeStyle,
                l10n: l10n,
              ),
            ),
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text(l10n.entriesError(error.toString()))),
    );
  }
}

Widget? _jiraStatusIcon(
  AppLocalizations l10n,
  String? jiraTicketKey,
  JiraWorklogRow? worklog,
) {
  if (jiraTicketKey == null) return null;
  final status = worklog?.status;
  return switch (status) {
    JiraWorklogStatus.synced => Tooltip(
      message: l10n.entriesJiraStatusSynced,
      child: const Icon(
        Icons.cloud_done_outlined,
        size: 18,
        color: Colors.green,
      ),
    ),
    JiraWorklogStatus.error => Tooltip(
      message: l10n.entriesJiraStatusError,
      child: const Icon(Icons.cloud_off_outlined, size: 18, color: Colors.red),
    ),
    _ => Tooltip(
      message: l10n.entriesJiraStatusPending,
      child: Icon(
        Icons.cloud_upload_outlined,
        size: 18,
        color: Colors.grey.shade600,
      ),
    ),
  };
}

/// One day's entries rendered as a single rounded card: rows separated by
/// 1px dividers (no divider after the last row), with
/// `clipBehavior: Clip.antiAlias` so each row -- including the
/// swipe-to-delete background -- is clipped to the card's rounded corners.
/// See docs/superpowers/specs/2026-08-04-entries-grouped-block-design.md.
class _DayEntriesBlock extends ConsumerWidget {
  const _DayEntriesBlock({
    required this.entries,
    required this.projectsById,
    required this.jiraWorklogsById,
    required this.timeStyle,
    required this.l10n,
  });

  final List<TimeEntry> entries;
  final Map<String, Project> projectsById;
  final Map<String, JiraWorklogRow> jiraWorklogsById;
  final TimeFormatStyle timeStyle;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final (index, entry) in entries.indexed) ...[
            _EntryTile(
              key: ValueKey(entry.id),
              entry: entry,
              project: entry.projectId == null
                  ? null
                  : projectsById[entry.projectId],
              jiraWorklog: jiraWorklogsById[entry.id],
              timeStyle: timeStyle,
              l10n: l10n,
              onTap: () => showManualEntryDialog(context, ref, existing: entry),
              onDismissed: () {
                ref
                    .read(syncedWritesProvider.future)
                    .then((w) => w.deleteEntry(entry.id));
              },
            ),
            if (index != entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

/// A single time entry row inside a [_DayEntriesBlock]. Presentational only
/// -- [onTap] and [onDismissed] carry the Riverpod-dependent behavior so
/// this widget stays a plain [StatelessWidget].
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    super.key,
    required this.entry,
    required this.project,
    required this.jiraWorklog,
    required this.timeStyle,
    required this.l10n,
    required this.onTap,
    required this.onDismissed,
  });

  final TimeEntry entry;
  final Project? project;
  final JiraWorklogRow? jiraWorklog;
  final TimeFormatStyle timeStyle;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final jiraStatusIcon = _jiraStatusIcon(
      l10n,
      entry.jiraTicketKey,
      jiraWorklog,
    );
    final duration = entry.workedDuration;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: project != null
              ? Color(int.parse(project!.colorHex.replaceFirst('#', '0xFF')))
              : Colors.grey,
          radius: 8,
          child: const SizedBox.shrink(),
        ),
        title: Text(
          entry.description?.isNotEmpty == true
              ? entry.description!
              : (project?.name ?? l10n.entriesNoDescription),
        ),
        subtitle: Text(
          '${project?.name ?? l10n.commonNoProject} · '
          '${formatTime(entry.startAt, timeStyle)} – '
          '${formatTime(entry.endAt!, timeStyle)}',
        ),
        trailing: jiraStatusIcon == null
            ? Text(formatDuration(duration, timeStyle))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  jiraStatusIcon,
                  const SizedBox(width: 6),
                  Text(formatDuration(duration, timeStyle)),
                ],
              ),
        onTap: onTap,
      ),
    );
  }
}

const double _depthInset = 12;

/// "Today"/"Yesterday" for the two most recent days, otherwise the formatted
/// date. Unchanged from the day header this replaced.
String _dayLabel(
  DateTime day,
  AppLocalizations l10n,
  DateFormatStyle dateStyle,
  String localeName,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return l10n.entriesToday;
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return l10n.entriesYesterday;
  }
  return formatDate(day, dateStyle, localeName);
}

/// Tooltip for a week/month/year row's warning icon, or null when no day below
/// it falls short of the break rule.
String? _rolledUpBreakTooltip(AppLocalizations l10n, int insufficientBreakDays) =>
    insufficientBreakDays == 0
        ? null
        : l10n.entriesBreakInsufficientDaysTooltip(insufficientBreakDays);

/// One header row of the entries hierarchy -- year, month, week or day. Purely
/// presentational: it neither knows what its level means nor touches Riverpod,
/// it just indents by [depth], puts [label] on the left and the summary on the
/// right, and reports taps through [onTap].
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.depth,
    required this.label,
    required this.total,
    required this.breakDuration,
    required this.warningTooltip,
    required this.expanded,
    required this.onTap,
    required this.l10n,
    required this.timeStyle,
  });

  final int depth;
  final String label;
  final Duration total;
  final Duration breakDuration;

  /// Non-null shows the warning icon carrying this message; the caller picks
  /// the wording that fits its level.
  final String? warningTooltip;
  final bool expanded;
  final VoidCallback onTap;
  final AppLocalizations l10n;
  final TimeFormatStyle timeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltip = warningTooltip;
    final totalText = formatDuration(total, timeStyle);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: depth * _depthInset, top: 12, bottom: 8),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.keyboard_arrow_right, size: 20),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Wrap so a long date range plus both sums drop to a second line
            // instead of overflowing in a narrow window.
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (tooltip != null)
                    Tooltip(
                      message: tooltip,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  Text(
                    l10n.entriesBreakLabel(
                      formatDuration(breakDuration, timeStyle),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tooltip == null ? null : theme.colorScheme.error,
                    ),
                  ),
                  // Visually just a duration; labelled for screen readers so
                  // the bare number still says what it is.
                  Semantics(
                    label: l10n.entriesWorkLabel(totalText),
                    excludeSemantics: true,
                    child: Text(
                      totalText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
