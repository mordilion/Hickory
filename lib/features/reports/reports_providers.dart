import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to this entry point in Riverpod 3.x; still the right
// tool for a single piece of simple, directly-settable UI state like the
// selected report date range.
import 'package:flutter_riverpod/legacy.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';

enum ReportRangePreset { thisWeek, thisMonth, last30Days, all }

DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

DateTimeRange rangeForPreset(ReportRangePreset preset, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  switch (preset) {
    case ReportRangePreset.thisWeek:
      final start = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(start: start, end: today.add(const Duration(days: 1)));
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

final reportRangeProvider = StateProvider<DateTimeRange>(
  (ref) => rangeForPreset(ReportRangePreset.thisMonth),
);

final reportEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref
      .watch(appDatabaseProvider)
      .timeEntriesDao
      .watchEntriesInRange(range.start.toUtc(), range.end.toUtc());
});

final reportProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(appDatabaseProvider).projectsDao.watchAllProjects();
});
