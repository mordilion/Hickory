// What the tracking is missing over a report range. Pure: no Riverpod, no
// Flutter beyond DateTimeRange, no database access beyond drift's row
// types — the same shape as balance_calculations.dart.

import 'package:flutter/material.dart' show DateTimeRange;

import '../../data/drift/database.dart';
import '../entries/break_rule_calculations.dart';
import 'balance_calculations.dart' show DayBalance;

/// The gaps and slips in one range's tracking.
class QualityFigures {
  const QualityFigures({
    required this.unbookedWorkDays,
    required this.shortBreakDays,
    required this.failedPushCount,
    required this.absenceDaysByTypeName,
  });

  /// Work days inside the range that carry neither a tracked entry nor an
  /// absence — the days someone forgot. Ascending.
  final List<DateTime> unbookedWorkDays;

  /// Days whose break time falls short of what the configured tiers demand
  /// for the time worked. Ascending.
  final List<DateTime> shortBreakDays;

  /// Entries whose last push to Jira or Personio failed, counted by the
  /// caller — the Sync tab owns that state and already lists it per entry.
  final int failedPushCount;

  /// Absence days per type name, for the range. A type that no longer
  /// resolves is left out rather than counted under a guessed name.
  final Map<String, int> absenceDaysByTypeName;

  bool get isClean =>
      unbookedWorkDays.isEmpty && shortBreakDays.isEmpty && failedPushCount == 0;
}

DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

bool _inRange(DateTime day, DateTimeRange range) =>
    !day.isBefore(_dayOf(range.start)) && day.isBefore(_dayOf(range.end));

/// Folds the range's days into [QualityFigures].
///
/// [balances] decides which days are work days and how much was worked on
/// them, so this agrees with the balance block by construction rather than
/// by re-deriving the targets. [entries] is only needed for the break
/// calculation, which works off the gaps between a day's entries.
QualityFigures qualityFigures({
  required List<DayBalance> balances,
  required List<TimeEntry> entries,
  required List<Absence> absences,
  required Map<String, AbsenceType> absenceTypesById,
  required List<BreakRuleTier> tiers,
  required bool includePausedTimeInBreak,
  required int failedPushCount,
  required DateTimeRange range,
}) {
  final entriesByDay = <DateTime, List<TimeEntry>>{};
  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final day = _dayOf(entry.startAt.toLocal());
    entriesByDay.putIfAbsent(day, () => []).add(entry);
  }

  final absenceDays = <DateTime>{};
  final absenceCounts = <String, int>{};
  for (final absence in absences) {
    final day = _dayOf(absence.date);
    if (!_inRange(day, range)) continue;
    absenceDays.add(day);
    final type = absenceTypesById[absence.absenceTypeId];
    if (type == null) continue;
    absenceCounts.update(type.name, (count) => count + 1, ifAbsent: () => 1);
  }

  final unbooked = <DateTime>[];
  final shortBreaks = <DateTime>[];
  for (final balance in balances) {
    final day = balance.day;
    if (!_inRange(day, range)) continue;

    final dayEntries = entriesByDay[day] ?? const <TimeEntry>[];
    final isWorkDay = balance.target > Duration.zero;
    if (isWorkDay && dayEntries.isEmpty && !absenceDays.contains(day)) {
      unbooked.add(day);
    }

    final required = requiredBreakForWorked(balance.worked, tiers);
    if (required == null) continue;
    final taken = dayBreakDuration(dayEntries, includePausedTime: includePausedTimeInBreak);
    if (taken < required) shortBreaks.add(day);
  }

  unbooked.sort();
  shortBreaks.sort();
  return QualityFigures(
    unbookedWorkDays: unbooked,
    shortBreakDays: shortBreaks,
    failedPushCount: failedPushCount,
    absenceDaysByTypeName: absenceCounts,
  );
}
