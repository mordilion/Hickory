import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'break_rule_calculations.dart';
import 'day_grouping.dart';
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
        final jiraWorklogsById = jiraWorklogsAsync.value ?? const <String, JiraWorklogRow>{};
        final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
        final groups = groupEntriesByDay(
          finished,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
        final localeName = Localizations.localeOf(context).languageCode;
        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DayHeader(
                  day: group.day,
                  total: group.totalDuration,
                  breakDuration: group.breakDuration,
                  requiredBreak: requiredBreakForWorked(group.totalDuration, tiers),
                  l10n: l10n,
                  dateStyle: dateStyle,
                  timeStyle: timeStyle,
                  localeName: localeName,
                ),
                _DayEntriesBlock(
                  entries: group.entries,
                  projectsById: projectsById,
                  jiraWorklogsById: jiraWorklogsById,
                  timeStyle: timeStyle,
                  l10n: l10n,
                ),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(l10n.entriesError(error.toString()))),
    );
  }
}

Widget? _jiraStatusIcon(AppLocalizations l10n, String? jiraTicketKey, JiraWorklogRow? worklog) {
  if (jiraTicketKey == null) return null;
  final status = worklog?.status;
  return switch (status) {
    JiraWorklogStatus.synced => Tooltip(
        message: l10n.entriesJiraStatusSynced,
        child: const Icon(Icons.cloud_done_outlined, size: 18, color: Colors.green),
      ),
    JiraWorklogStatus.error => Tooltip(
        message: l10n.entriesJiraStatusError,
        child: const Icon(Icons.cloud_off_outlined, size: 18, color: Colors.red),
      ),
    _ => Tooltip(
        message: l10n.entriesJiraStatusPending,
        child: Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.grey.shade600),
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
          for (var index = 0; index < entries.length; index++) ...[
            _EntryTile(
              entry: entries[index],
              project: entries[index].projectId == null
                  ? null
                  : projectsById[entries[index].projectId],
              jiraWorklog: jiraWorklogsById[entries[index].id],
              timeStyle: timeStyle,
              l10n: l10n,
              onTap: () => showManualEntryDialog(context, ref, existing: entries[index]),
              onDismissed: () {
                final entryId = entries[index].id;
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entryId));
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
    final jiraStatusIcon = _jiraStatusIcon(l10n, entry.jiraTicketKey, jiraWorklog);
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

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.total,
    required this.breakDuration,
    required this.requiredBreak,
    required this.l10n,
    required this.dateStyle,
    required this.timeStyle,
    required this.localeName,
  });

  final DateTime day;
  final Duration total;
  final Duration breakDuration;
  final Duration? requiredBreak;
  final AppLocalizations l10n;
  final DateFormatStyle dateStyle;
  final TimeFormatStyle timeStyle;
  final String localeName;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.entriesToday;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return l10n.entriesYesterday;
    return formatDate(day, dateStyle, localeName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiredBreak = this.requiredBreak;
    final isInsufficient = requiredBreak != null && breakDuration < requiredBreak;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            l10n.entriesDayHeader(_label(), formatDuration(total, timeStyle)),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isInsufficient)
            Tooltip(
              message: l10n.entriesBreakInsufficientTooltip,
              child: Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
            ),
          Text(
            l10n.entriesBreakLabel(formatDuration(breakDuration, timeStyle)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: isInsufficient ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
