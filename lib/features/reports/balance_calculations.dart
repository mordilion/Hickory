// Flex-time ("Gleitzeit") balance arithmetic. Pure: no Riverpod, no
// Flutter, no database access beyond drift's row types — the same shape as
// report_calculations.dart, and testable with plain in-memory lists.
//
// Nothing here is materialized in the database on purpose: a cached
// balance would need recomputation after every cross-device event-log
// merge, and those merges happen at arbitrary times.

import '../../data/drift/database.dart';
import 'report_calculations.dart' show totalsByDay;

/// Target work minutes for [weekday] (`DateTime.monday` … `DateTime.sunday`).
/// `0` means the day is not a work day.
int targetMinutesForWeekday(AppSettingsRow settings, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return settings.targetMinutesMonday;
    case DateTime.tuesday:
      return settings.targetMinutesTuesday;
    case DateTime.wednesday:
      return settings.targetMinutesWednesday;
    case DateTime.thursday:
      return settings.targetMinutesThursday;
    case DateTime.friday:
      return settings.targetMinutesFriday;
    case DateTime.saturday:
      return settings.targetMinutesSaturday;
    default:
      return settings.targetMinutesSunday;
  }
}

/// Whether any target is configured at all. False in a fresh install, where
/// every tracked minute would otherwise read as overtime — callers show an
/// empty state pointing at Settings instead of a number.
bool hasAnyTarget(AppSettingsRow settings) => [
      settings.targetMinutesMonday,
      settings.targetMinutesTuesday,
      settings.targetMinutesWednesday,
      settings.targetMinutesThursday,
      settings.targetMinutesFriday,
      settings.targetMinutesSaturday,
      settings.targetMinutesSunday,
    ].any((minutes) => minutes > 0);

/// One calendar day's contribution to the balance.
class DayBalance {
  const DayBalance({
    required this.day,
    required this.worked,
    required this.target,
  });

  /// Local midnight of the day, the same key [totalsByDay] groups by.
  final DateTime day;
  final Duration worked;
  final Duration target;

  Duration get balance => worked - target;
}

/// Per-day balances, ascending by day.
///
/// Only days carrying at least one finished entry are returned. While
/// absence tracking is off (phase 1 always), a day off cannot be recorded,
/// so counting empty work days would manufacture a deficit. Phase 2 makes
/// this conditional on `settings.absenceTrackingEnabled`.
List<DayBalance> dayBalances(List<TimeEntry> entries, AppSettingsRow settings) {
  final workedByDay = totalsByDay(entries);
  final days = workedByDay.keys.toList()..sort();
  return [
    for (final day in days)
      DayBalance(
        day: day,
        worked: workedByDay[day]!,
        target: Duration(minutes: targetMinutesForWeekday(settings, day.weekday)),
      ),
  ];
}

/// The cutoff date falling in [year], with the configured day clamped to
/// that month's length — a 29 February rule becomes 28 February in a
/// non-leap year rather than silently rolling into March.
DateTime? _cutoffInYear(AppSettingsRow settings, int year) {
  final month = settings.balanceResetMonth;
  final day = settings.balanceResetDay;
  if (month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1) return null;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > daysInMonth ? daysInMonth : day);
}

/// The most recent cutoff on or before [day], or null when no usable rule
/// is configured. A rule with `balanceResetMode == 'none'`, or one missing
/// its date, has no cutoff at all.
DateTime? lastCutoffOnOrBefore(AppSettingsRow settings, DateTime day) {
  if (settings.balanceResetMode == 'none') return null;
  final thisYear = _cutoffInYear(settings, day.year);
  if (thisYear == null) return null;
  if (!thisYear.isAfter(day)) return thisYear;
  return _cutoffInYear(settings, day.year - 1);
}

/// Applies the reset rule to a balance that has just crossed a cutoff.
Duration _afterCutoff(Duration balance, AppSettingsRow settings) {
  if (settings.balanceResetMode == 'resetToZero') return Duration.zero;
  final max = settings.carryOverMaxMinutes;
  final min = settings.carryOverMinMinutes;
  if (max != null && balance.inMinutes > max) return Duration(minutes: max);
  if (min != null && balance.inMinutes < min) return Duration(minutes: min);
  return balance;
}

/// The running balance up to and including [asOf].
///
/// Applied as a single forward pass: days are added in order, and whenever
/// one or more cutoffs fall between the previous day and the current one
/// the accumulated balance is reset or clamped first. Deterministic and
/// linear in the number of worked days, no matter how long the history —
/// a recursive "balance of the previous period" formulation would re-walk
/// the same years once per cutoff.
Duration runningBalance(
  List<DayBalance> balances,
  AppSettingsRow settings, {
  required DateTime asOf,
}) {
  var total = Duration.zero;
  // Seeded with the first worked day (or asOf, if there is none) rather
  // than the epoch — starting at 1970 would walk every no-op cutoff year
  // between then and the first real day for no reason.
  var previous = balances.isNotEmpty ? balances.first.day : asOf;

  void applyCutoffsBetween(DateTime from, DateTime to) {
    if (settings.balanceResetMode == 'none') return;
    for (var year = from.year; year <= to.year; year++) {
      final cutoff = _cutoffInYear(settings, year);
      if (cutoff == null) return;
      if (cutoff.isAfter(from) && !cutoff.isAfter(to)) {
        total = _afterCutoff(total, settings);
      }
    }
  }

  for (final day in balances) {
    if (day.day.isAfter(asOf)) break;
    applyCutoffsBetween(previous, day.day);
    total += day.balance;
    previous = day.day;
  }
  applyCutoffsBetween(previous, asOf);
  return total;
}
