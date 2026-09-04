import '../../data/drift/database.dart';
import '../reports/balance_calculations.dart' show targetMinutesForWeekday;

/// The calendar days a bulk absence entry actually covers: every day from
/// [from] to [to] inclusive whose weekday has a target above zero.
///
/// Free days are skipped rather than recorded as absences, because an
/// absence on a day with no target would credit nothing and only add a row
/// the user then has to look at. A reversed span yields nothing rather
/// than throwing: the only caller is a pair of date pickers, and an empty
/// result is a state the form already has to report.
List<DateTime> absenceDaysBetween(
  DateTime from,
  DateTime to,
  AppSettingsRow settings,
) {
  final first = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  if (last.isBefore(first)) return const [];

  final days = <DateTime>[];
  for (
    var day = first;
    !day.isAfter(last);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    if (targetMinutesForWeekday(settings, day.weekday) > 0) days.add(day);
  }
  return days;
}
