// What the tracking is missing over a report range. Pure: no Riverpod, no
// Flutter beyond DateTimeRange, no database access beyond drift's row
// types — the same shape as balance_calculations.dart.

import 'package:flutter/material.dart' show DateTimeRange;

import '../../data/drift/database.dart';
import '../../data/drift/tables/absences_table.dart';
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

  /// Absence days per type name, for the range — in days, not in rows: a
  /// half day counts 0.5 and a time range its share of that day. A type
  /// that no longer resolves is left out rather than counted under a
  /// guessed name.
  final Map<String, double> absenceDaysByTypeName;

  bool get isClean =>
      unbookedWorkDays.isEmpty && shortBreakDays.isEmpty && failedPushCount == 0;
}

DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// How much of a day [absence] takes up, in days.
///
/// A whole day is one and a half day is a half — those two carry no minute
/// figure at all, by design. A time range is measured against [dayTarget],
/// so two hours of an eight-hour day is a quarter and not a day off; it is
/// capped at one, since being absent longer than the day was owed does not
/// make it more than one day.
///
/// Without a target there is no scale to measure a range against. It then
/// counts as a whole day rather than as nothing: the row exists because
/// the user recorded an absence. In practice the recording form skips days
/// with no target, so this is a fallback rather than a path.
double _absenceDayShare(Absence absence, Duration? dayTarget) {
  switch (absence.portion) {
    case absencePortionHalfDay:
      return 0.5;
    case absencePortionRange:
      final from = absence.startAt;
      final to = absence.endAt;
      final target = dayTarget?.inMinutes ?? 0;
      if (from == null || to == null || target <= 0) return 1;
      final minutes = to.difference(from).inMinutes;
      if (minutes <= 0) return 0;
      final share = minutes / target;
      return share > 1 ? 1 : share;
    default:
      // fullDay, and any portion a newer peer wrote that this version does
      // not know: one recorded day off.
      return 1;
  }
}

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

  final targetByDay = {for (final balance in balances) balance.day: balance.target};
  final absenceDays = <DateTime>{};
  final absenceCounts = <String, double>{};
  for (final absence in absences) {
    final day = _dayOf(absence.date);
    if (!_inRange(day, range)) continue;
    absenceDays.add(day);
    final type = absenceTypesById[absence.absenceTypeId];
    if (type == null) continue;
    final share = _absenceDayShare(absence, targetByDay[day]);
    absenceCounts.update(type.name, (days) => days + share, ifAbsent: () => share);
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
