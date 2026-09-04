import '../../data/drift/database.dart';
import 'report_calculations.dart' show totalsByDay;

/// Target work minutes for [weekday] (`DateTime.monday` … `DateTime.sunday`).
/// `0` means the day is not a work day.
///
/// Flex-time ("Gleitzeit") balance arithmetic. Pure: no Riverpod, no
/// Flutter, no database access beyond drift's row types — the same shape as
/// report_calculations.dart, and testable with plain in-memory lists.
///
/// Nothing here is materialized in the database on purpose: a cached
/// balance would need recomputation after every cross-device event-log
/// merge, and those merges happen at arbitrary times.
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
