import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/absence_providers.dart';
import '../../core/di/app_settings_provider.dart';
import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';
import '../timer/timer_providers.dart' show allEntriesProvider;
import 'balance_calculations.dart';

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

/// The flex-time balance as of today, over the whole history — deliberately
/// not scoped to the report's selected range or its project/billable
/// filters: "overtime, but only for project X" is not a meaningful number.
final workTimeBalanceProvider = Provider<AsyncValue<Duration>>((ref) {
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

  final now = DateTime.now();
  return AsyncValue.data(
    runningBalance(
      dayBalances(
        entryList,
        settingsRow,
        absences: absenceList,
        absenceTypesById: ref.watch(absenceTypesByIdProvider),
        // Enumerate up to today, so a work day that was neither booked
        // nor excused shows up as the deficit it is.
        through: DateTime(now.year, now.month, now.day),
      ),
      settingsRow,
      asOf: now,
    ),
  );
});
