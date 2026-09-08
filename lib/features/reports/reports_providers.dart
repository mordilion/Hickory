import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/absence_providers.dart';
import '../../core/di/balance_adjustment_providers.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/jira_providers.dart';
import '../../core/di/personio_providers.dart';
import '../../core/di/app_settings_provider.dart';
import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';
import '../timer/timer_providers.dart' show allEntriesProvider;
import '../sync/failed_pushes.dart';
import 'balance_calculations.dart';
import 'quality_calculations.dart';
import 'trend_calculations.dart';
import 'report_view_controller.dart';
import 'report_view_state.dart';

enum ReportRangePreset {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  last30Days,
  all,
}

DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

DateTimeRange rangeForPreset(ReportRangePreset preset, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  switch (preset) {
    case ReportRangePreset.today:
      return DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      );
    case ReportRangePreset.yesterday:
      final yesterday = today.subtract(const Duration(days: 1));
      return DateTimeRange(start: yesterday, end: today);
    case ReportRangePreset.thisWeek:
      final start = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(
        start: start,
        end: today.add(const Duration(days: 1)),
      );
    case ReportRangePreset.thisMonth:
      final start = DateTime(today.year, today.month, 1);
      final end = DateTime(today.year, today.month + 1, 1);
      return DateTimeRange(start: start, end: end);
    case ReportRangePreset.last30Days:
      return DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today.add(const Duration(days: 1)),
      );
    case ReportRangePreset.all:
      return DateTimeRange(start: DateTime(2000), end: DateTime(2100));
  }
}

final reportEntriesProvider = StreamProvider.autoDispose
    .family<List<TimeEntry>, DateTimeRange>((ref, range) {
      return ref
          .watch(appDatabaseProvider)
          .timeEntriesDao
          .watchEntriesInRange(range.start.toUtc(), range.end.toUtc());
    });

final reportProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(appDatabaseProvider).projectsDao.watchAllProjects();
});

/// Everything the two balance providers below need, resolved once: the
/// per-day balances, the settings they were computed against, and the
/// manual corrections that still have to be folded in.
///
/// Deliberately not scoped to the report's selected filters: "overtime,
/// but only for project X" is not a meaningful number, so both providers
/// read every entry there is.
AsyncValue<({List<DayBalance> balances, AppSettingsRow settings, List<BalanceAdjustment> adjustments})>
    _balanceInputs(Ref ref) {
  final entries = ref.watch(allEntriesProvider);
  final settings = ref.watch(appSettingsProvider);
  final absences = ref.watch(absencesProvider);
  // Checked before the loading/null checks below: AsyncError's `isLoading`
  // is always false and its `.value` carries forward the previous data (or
  // null) on purpose, so an error here would otherwise either be
  // mistaken for "still loading" (no prior data) or silently masked by a
  // stale balance (prior data present) instead of reaching the UI.
  if (entries is AsyncError<List<TimeEntry>>) {
    return AsyncValue.error(entries.error, entries.stackTrace);
  }
  if (settings is AsyncError<AppSettingsRow>) {
    return AsyncValue.error(settings.error, settings.stackTrace);
  }
  if (entries.isLoading || settings.isLoading) return const AsyncValue.loading();
  final entryList = entries.value;
  final settingsRow = settings.value;
  if (entryList == null || settingsRow == null) return const AsyncValue.loading();

  // Absences only matter, and only have to be waited for, while the
  // feature is on. With it off a failing absence stream must not take
  // down a balance that does not read absences at all.
  var absenceList = const <Absence>[];
  if (settingsRow.absenceTrackingEnabled) {
    if (absences is AsyncError<List<Absence>>) {
      return AsyncValue.error(absences.error, absences.stackTrace);
    }
    final loaded = absences.value;
    if (loaded == null) return const AsyncValue.loading();
    absenceList = loaded;
  }

  // Corrections are cheap and always relevant, so unlike absences they are
  // waited for unconditionally -- there is no switch that turns them off.
  final adjustments = ref.watch(balanceAdjustmentsProvider);
  if (adjustments is AsyncError<List<BalanceAdjustment>>) {
    return AsyncValue.error(adjustments.error, adjustments.stackTrace);
  }
  final adjustmentList = adjustments.value;
  if (adjustmentList == null) return const AsyncValue.loading();

  final now = DateTime.now();
  return AsyncValue.data((
    balances: dayBalances(
      entryList,
      settingsRow,
      absences: absenceList,
      absenceTypesById: ref.watch(absenceTypesByIdProvider),
      // Enumerate up to today, so a work day that was neither booked nor
      // excused shows up as the deficit it is.
      through: DateTime(now.year, now.month, now.day),
    ),
    settings: settingsRow,
    adjustments: adjustmentList,
  ));
}

/// The flex-time balance as of today, over the whole history and since the
/// last cutoff.
final workTimeBalanceProvider = Provider<AsyncValue<Duration>>((ref) {
  return _balanceInputs(ref).whenData(
    (inputs) => runningBalance(
      inputs.balances,
      inputs.settings,
      asOf: DateTime.now(),
      adjustments: inputs.adjustments,
    ),
  );
});

/// The chart's bars for the report's selected range, per day or per week
/// depending on how long the range is.
///
/// Reads every entry, like the balance it charts against: a target line
/// drawn over a filtered subset would compare one project's hours with a
/// whole week's target.
final trendBarsProvider =
    Provider<AsyncValue<({List<TrendBar> bars, TrendGranularity granularity})>>((ref) {
  final range =
      (ref.watch(reportViewControllerProvider).value ?? const ReportViewState()).range;
  final now = DateTime.now();
  final granularity = granularityFor(range);
  return _balanceInputs(ref).whenData(
    (inputs) => (
      bars: trendBars(
        inputs.balances,
        range,
        granularity,
        through: DateTime(now.year, now.month, now.day),
      ),
      granularity: granularity,
    ),
  );
});

/// What the tracking is missing over the report's selected range.
///
/// Reads every entry in the range, not the filtered ones: a forgotten day
/// is forgotten whichever project the filter is set to (spec §6).
final qualityFiguresProvider = Provider<AsyncValue<QualityFigures>>((ref) {
  final range =
      (ref.watch(reportViewControllerProvider).value ?? const ReportViewState()).range;
  final tiers = ref.watch(breakRuleTiersProvider).value ?? const <BreakRuleTier>[];
  final absences = ref.watch(absencesProvider).value ?? const <Absence>[];
  final jira = ref.watch(jiraWorklogsByEntryIdProvider).value ?? const {};
  final personio = ref.watch(personioAttendancesByEntryIdProvider).value ?? const {};

  return _balanceInputs(ref).whenData((inputs) {
    final entriesInRange = [
      for (final entry in ref.watch(allEntriesProvider).value ?? const <TimeEntry>[])
        if (entry.endAt != null &&
            !entry.startAt.toLocal().isBefore(range.start) &&
            entry.startAt.toLocal().isBefore(range.end))
          entry,
    ];
    // One entry can fail on both services; it is one entry either way, so
    // the two failure sets are unioned rather than added.
    final failed = <String>{
      ...jiraFailures(jira).keys,
      ...personioFailures(personio).keys,
    };
    final failedInRange = entriesInRange.where((entry) => failed.contains(entry.id)).length;

    return qualityFigures(
      balances: inputs.balances,
      entries: entriesInRange,
      absences: absences,
      absenceTypesById: ref.watch(absenceTypesByIdProvider),
      tiers: tiers,
      includePausedTimeInBreak: inputs.settings.countPausedTimeAsBreak,
      failedPushCount: failedInRange,
      range: range,
    );
  });
});

/// Worked, target, average and corrections over the report's selected
/// range. The range is the screen's own; its project and billable filters
/// are deliberately ignored (see [_balanceInputs]).
final balanceFiguresProvider = Provider<AsyncValue<RangeFigures>>((ref) {
  // The stored view state arrives asynchronously and can fail to load at
  // all; falling back to the default keeps the tiles showing the range the
  // screen itself defaults to rather than an empty state.
  final range =
      (ref.watch(reportViewControllerProvider).value ?? const ReportViewState()).range;
  return _balanceInputs(ref).whenData(
    (inputs) => figuresForRange(inputs.balances, range, adjustments: inputs.adjustments),
  );
});
