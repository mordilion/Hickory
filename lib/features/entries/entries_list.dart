import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/jira_providers.dart';
import '../../core/di/personio_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/format/iso_week.dart';
import '../../core/theme/hickory_colors.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/tables/personio_attendances_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'entries_location.dart';
import 'entry_tree.dart';
import 'manual_entry_dialog.dart';

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
    final personioAttendancesAsync = ref.watch(personioAttendancesByEntryIdProvider);
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
        final personioAttendancesById =
            personioAttendancesAsync.value ?? const <String, PersonioAttendanceRow>{};
        final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
        final years = buildEntryTree(
          finished,
          tiers: tiers,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
        // Null means "not navigated yet": resolve it here, where the data is
        // known, instead of seeding the controller blind.
        final location =
            ref.watch(entriesLocationControllerProvider) ??
            initialLocation(years, DateTime.now());
        final view = viewFor(years, location);
        final localeName = Localizations.localeOf(context).languageCode;
        void goTo(EntriesLocation target) =>
            ref.read(entriesLocationControllerProvider.notifier).goTo(target);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Breadcrumb(
              location: location,
              l10n: l10n,
              localeName: localeName,
              onGoTo: goTo,
            ),
            Expanded(
              child: switch (view) {
                EntriesYearsView(:final years) => ListView.builder(
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    return _DrillRow(
                      label: '${year.year}',
                      total: year.totalDuration,
                      breakDuration: year.breakDuration,
                      warningTooltip: _rolledUpBreakTooltip(
                        l10n,
                        year.insufficientBreakDays,
                      ),
                      onTap: () => goTo(EntriesYearLocation(year.year)),
                      l10n: l10n,
                      timeStyle: timeStyle,
                    );
                  },
                ),
                EntriesMonthsView(year: final yearGroup) => ListView.builder(
                  itemCount: yearGroup.months.length,
                  itemBuilder: (context, index) {
                    final month = yearGroup.months[index];
                    return _DrillRow(
                      label: _monthLabel(month.year, month.month, localeName),
                      total: month.totalDuration,
                      breakDuration: month.breakDuration,
                      warningTooltip: _rolledUpBreakTooltip(
                        l10n,
                        month.insufficientBreakDays,
                      ),
                      onTap: () =>
                          goTo(EntriesMonthLocation(month.year, month.month)),
                      l10n: l10n,
                      timeStyle: timeStyle,
                    );
                  },
                ),
                EntriesWeeksView(month: final monthGroup) => ListView.builder(
                  itemCount: monthGroup.weeks.length,
                  itemBuilder: (context, index) {
                    final week = monthGroup.weeks[index];
                    return _DrillRow(
                      label: l10n.entriesWeekHeader(
                        week.isoWeek,
                        l10n.entriesWeekDayRange(
                          week.firstDay.day,
                          week.lastDay.day,
                        ),
                      ),
                      total: week.totalDuration,
                      breakDuration: week.breakDuration,
                      warningTooltip: _rolledUpBreakTooltip(
                        l10n,
                        week.insufficientBreakDays,
                      ),
                      onTap: () => goTo(
                        EntriesWeekLocation(
                          monday: week.monday,
                          year: week.year,
                          month: week.month,
                        ),
                      ),
                      l10n: l10n,
                      timeStyle: timeStyle,
                    );
                  },
                ),
                // The deepest view: no more drilling, the days show their own
                // entries so a whole week reads in one screen.
                EntriesWeekView(:final week) => ListView.builder(
                  itemCount: week.days.length,
                  itemBuilder: (context, index) {
                    final day = week.days[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DaySubheader(
                          label: _dayLabel(
                            day.day,
                            l10n,
                            dateStyle,
                            localeName,
                          ),
                          total: day.totalDuration,
                          breakDuration: day.breakDuration,
                          warningTooltip: day.isBreakInsufficient
                              ? l10n.entriesBreakInsufficientTooltip
                              : null,
                          l10n: l10n,
                          timeStyle: timeStyle,
                        ),
                        _DayEntriesBlock(
                          entries: day.entries,
                          projectsById: projectsById,
                          jiraWorklogsById: jiraWorklogsById,
                          personioAttendancesById: personioAttendancesById,
                          timeStyle: timeStyle,
                          l10n: l10n,
                        ),
                      ],
                    );
                  },
                ),
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text(l10n.entriesError(error.toString()))),
    );
  }
}

/// The stored sync error, or [fallback] when the row carries none.
String _errorTooltip(String? lastError, String fallback) {
  final message = lastError?.trim();
  if (message == null || message.isEmpty) return fallback;
  return message;
}

Widget _statusIcon(IconData icon, Color color, String tooltip) =>
    Tooltip(message: tooltip, child: Icon(icon, size: 18, color: color));

/// The entry's Jira booking state, or null when it carries no ticket and so
/// was never meant to be booked. Cloud icons; Personio uses the calendar
/// family so the two are told apart at a glance when both are shown.
Widget? _jiraStatusIcon(
  AppLocalizations l10n,
  String? jiraTicketKey,
  JiraWorklogRow? worklog,
) {
  if (jiraTicketKey == null) return null;
  return switch (worklog?.status) {
    JiraWorklogStatus.synced => _statusIcon(
      Icons.cloud_done_outlined,
      Colors.green,
      l10n.entriesJiraStatusSynced,
    ),
    // The reason is already stored -- and sanitised of credentials by
    // JiraSyncService._safeErrorMessage -- so show it instead of the
    // generic string. That stays the fallback for a row without one: an
    // older row, or a device that received the state before the message.
    JiraWorklogStatus.error => _statusIcon(
      Icons.cloud_off_outlined,
      Colors.red,
      _errorTooltip(worklog?.lastError, l10n.entriesJiraStatusError),
    ),
    _ => _statusIcon(
      Icons.cloud_upload_outlined,
      Colors.grey.shade600,
      l10n.entriesJiraStatusPending,
    ),
  };
}

/// The entry's Personio state, or null when it has never been pushed.
/// Personio has no per-entry opt-in like Jira's ticket key, so the absence
/// of an attendance row is the only thing that distinguishes "not pushed"
/// from "pushed" -- and a permanent pending icon on every entry would say
/// nothing.
Widget? _personioStatusIcon(
  AppLocalizations l10n,
  PersonioAttendanceRow? attendance,
) {
  if (attendance == null) return null;
  return switch (attendance.status) {
    PersonioAttendanceStatus.synced => _statusIcon(
      Icons.event_available_outlined,
      Colors.green,
      l10n.entriesPersonioStatusSynced,
    ),
    PersonioAttendanceStatus.error => _statusIcon(
      Icons.event_busy_outlined,
      Colors.red,
      _errorTooltip(attendance.lastError, l10n.entriesPersonioStatusError),
    ),
    _ => _statusIcon(
      Icons.event_note_outlined,
      Colors.grey.shade600,
      l10n.entriesPersonioStatusPending,
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
    required this.personioAttendancesById,
    required this.timeStyle,
    required this.l10n,
  });

  final List<TimeEntry> entries;
  final Map<String, Project> projectsById;
  final Map<String, JiraWorklogRow> jiraWorklogsById;
  final Map<String, PersonioAttendanceRow> personioAttendancesById;
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
              personioAttendance: personioAttendancesById[entry.id],
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
    required this.personioAttendance,
    required this.timeStyle,
    required this.l10n,
    required this.onTap,
    required this.onDismissed,
  });

  final TimeEntry entry;
  final Project? project;
  final JiraWorklogRow? jiraWorklog;
  final PersonioAttendanceRow? personioAttendance;
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
    final personioStatusIcon = _personioStatusIcon(l10n, personioAttendance);
    final statusIcons = [?jiraStatusIcon, ?personioStatusIcon];
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final icon in statusIcons) ...[icon, const SizedBox(width: 6)],
            Text(formatDuration(duration, timeStyle)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// "Today"/"Yesterday" for the two most recent days, otherwise the formatted
/// date.
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

/// The month's own name, without the year -- the breadcrumb above already
/// carries it.
String _monthLabel(int year, int month, String localeName) =>
    DateFormat.MMMM(localeName).format(DateTime(year, month));

/// Tooltip for a rolled-up row's warning marker, or null when no day below it
/// falls short of the break rule.
String? _rolledUpBreakTooltip(
  AppLocalizations l10n,
  int insufficientBreakDays,
) => insufficientBreakDays == 0
    ? null
    : l10n.entriesBreakInsufficientDaysTooltip(insufficientBreakDays);

/// The path to the current level, with every ancestor tappable. Renders nothing
/// at the years list, where there is no path to show and the space is better
/// spent on entries.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.location,
    required this.l10n,
    required this.localeName,
    required this.onGoTo,
  });

  final EntriesLocation location;
  final AppLocalizations l10n;
  final String localeName;
  final void Function(EntriesLocation) onGoTo;

  /// Ancestors first, current level last.
  List<(String, EntriesLocation)> _trail() => switch (location) {
    EntriesYearsLocation() => const [],
    EntriesYearLocation(:final year) => [('$year', EntriesYearLocation(year))],
    EntriesMonthLocation(:final year, :final month) => [
      ('$year', EntriesYearLocation(year)),
      (_monthLabel(year, month, localeName), EntriesMonthLocation(year, month)),
    ],
    EntriesWeekLocation(:final monday, :final year, :final month) => [
      ('$year', EntriesYearLocation(year)),
      (_monthLabel(year, month, localeName), EntriesMonthLocation(year, month)),
      (
        // The plain week label, not entriesWeekHeader: a breadcrumb segment has
        // no room for the date range, and passing an empty one would leave its
        // separator dangling.
        l10n.entriesWeekLabel(isoWeekNumber(monday)),
        EntriesWeekLocation(monday: monday, year: year, month: month),
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final parent = parentOf(location);
    if (parent == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = HickoryColors.of(context);
    final trail = _trail();

    return Row(
      children: [
        IconButton(
          tooltip: l10n.entriesUpOneLevelTooltip,
          onPressed: () => onGoTo(parent),
          icon: const Icon(Icons.arrow_back, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (index, (label, target)) in trail.indexed) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '›',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                if (index == trail.length - 1)
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  InkWell(
                    onTap: () => onGoTo(target),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.timerNumeral,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A year, month or week row: tapping it drills one level deeper. The trailing
/// chevron is the affordance, so the row carries no expand/collapse state.
class _DrillRow extends StatelessWidget {
  const _DrillRow({
    required this.label,
    required this.total,
    required this.breakDuration,
    required this.warningTooltip,
    required this.onTap,
    required this.l10n,
    required this.timeStyle,
  });

  final String label;
  final Duration total;
  final Duration breakDuration;

  /// Non-null shows the warning marker with this message.
  final String? warningTooltip;
  final VoidCallback onTap;
  final AppLocalizations l10n;
  final TimeFormatStyle timeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = HickoryColors.of(context);
    final tooltip = warningTooltip;
    final totalText = formatDuration(total, timeStyle);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.navBorder)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (tooltip != null) ...[
              // A dot, not the day level's triangle: the same offending day
              // would otherwise shout from every level above it.
              Tooltip(
                message: tooltip,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              l10n.entriesBreakLabel(formatDuration(breakDuration, timeStyle)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: l10n.entriesWorkLabel(totalText),
              excludeSemantics: true,
              child: Text(
                totalText,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}

/// One day inside the week view. Not tappable -- the week view is the deepest
/// level, so a day only labels the entries beneath it.
class _DaySubheader extends StatelessWidget {
  const _DaySubheader({
    required this.label,
    required this.total,
    required this.breakDuration,
    required this.warningTooltip,
    required this.l10n,
    required this.timeStyle,
  });

  final String label;
  final Duration total;
  final Duration breakDuration;
  final String? warningTooltip;
  final AppLocalizations l10n;
  final TimeFormatStyle timeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = HickoryColors.of(context);
    final tooltip = warningTooltip;
    final totalText = formatDuration(total, timeStyle);

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (tooltip != null) ...[
            Tooltip(
              message: tooltip,
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            l10n.entriesBreakLabel(formatDuration(breakDuration, timeStyle)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tooltip == null
                  ? tokens.textMuted
                  : theme.colorScheme.error,
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: l10n.entriesWorkLabel(totalText),
            excludeSemantics: true,
            child: Text(
              totalText,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.timerNumeral,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
