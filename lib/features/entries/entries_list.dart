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
        final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
        final groups = groupEntriesByDay(
          finished,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
        final rows = <_ListRow>[
          for (final group in groups) ...[
            _HeaderRow(
              day: group.day,
              total: group.totalDuration,
              breakDuration: group.breakDuration,
              requiredBreak: requiredBreakForWorked(group.totalDuration, tiers),
            ),
            for (final entry in group.entries) _EntryRow(entry),
          ],
        ];
        final localeName = Localizations.localeOf(context).languageCode;
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _HeaderRow) {
              return _DayHeader(
                day: row.day,
                total: row.total,
                breakDuration: row.breakDuration,
                requiredBreak: row.requiredBreak,
                l10n: l10n,
                dateStyle: dateStyle,
                timeStyle: timeStyle,
                localeName: localeName,
              );
            }
            final entry = (row as _EntryRow).entry;
            final project = entry.projectId == null ? null : projectsById[entry.projectId];
            final jiraWorklog = jiraWorklogsAsync.value?[entry.id];
            final jiraStatusIcon = _jiraStatusIcon(l10n, entry.jiraTicketKey, jiraWorklog);
            final duration = entry.workedDuration;
            return Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) {
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entry.id));
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: const StadiumBorder(),
                child: ListTile(
                  shape: const StadiumBorder(),
                  leading: CircleAvatar(
                    backgroundColor: project != null
                        ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
                        : Colors.grey,
                    radius: 8,
                    child: const SizedBox.shrink(),
                  ),
                  title: Text(entry.description?.isNotEmpty == true
                      ? entry.description!
                      : (project?.name ?? l10n.entriesNoDescription)),
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
                  onTap: () => showManualEntryDialog(context, ref, existing: entry),
                ),
              ),
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

sealed class _ListRow {}

class _HeaderRow extends _ListRow {
  _HeaderRow({
    required this.day,
    required this.total,
    required this.breakDuration,
    required this.requiredBreak,
  });
  final DateTime day;
  final Duration total;
  final Duration breakDuration;
  final Duration? requiredBreak;
}

class _EntryRow extends _ListRow {
  _EntryRow(this.entry);
  final TimeEntry entry;
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
