import '../../data/drift/database.dart';
import '../../data/drift/tables/absences_table.dart';
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

/// One day of a continuous absence span, as it will be stored.
///
/// [startAt] and [endAt] are local times on [date] (the caller converts
/// them, like every other write does); they are null on a [portion] of
/// `fullDay`.
class AbsenceSpanDay {
  const AbsenceSpanDay({
    required this.date,
    required this.portion,
    this.startAt,
    this.endAt,
  });

  final DateTime date;
  final String portion;
  final DateTime? startAt;
  final DateTime? endAt;
}

/// Splits a continuous absence from [from] to [to] — both carrying a clock
/// time — into the rows that represent it, one per work day.
///
/// Read the way the same line reads in the manual entry form: away from
/// Monday 09:00 until Wednesday 11:00 without interruption. The first day
/// therefore runs from its clock time to midnight, the last from midnight
/// to its clock time, and every day in between is a whole day. A span
/// inside one day keeps both times, which is the common case (an
/// appointment). Free days are skipped exactly as in [absenceDaysBetween],
/// and skipping one never moves the clipping onto another day: the clock
/// times belong to the calendar days [from] and [to], not to the first and
/// last day that happens to be recorded.
///
/// Yields nothing when [to] is not after [from], or when no work day falls
/// in the span — an empty result is a state the form reports rather than
/// an error.
List<AbsenceSpanDay> absenceSpanDays(
  DateTime from,
  DateTime to,
  AppSettingsRow settings,
) {
  if (!to.isAfter(from)) return const [];

  final firstDay = DateTime(from.year, from.month, from.day);
  final lastDay = DateTime(to.year, to.month, to.day);
  if (firstDay == lastDay) {
    return [
      AbsenceSpanDay(
        date: firstDay,
        portion: absencePortionRange,
        startAt: from,
        endAt: to,
      ),
    ];
  }

  // An absence ending at midnight covers nothing of that day, so the day
  // it names gets no row at all.
  final endsAtMidnight = to == lastDay;

  final days = <AbsenceSpanDay>[];
  for (final day in absenceDaysBetween(firstDay, lastDay, settings)) {
    if (day == lastDay && endsAtMidnight) continue;
    if (day == firstDay) {
      days.add(
        AbsenceSpanDay(
          date: day,
          portion: absencePortionRange,
          startAt: from,
          endAt: DateTime(day.year, day.month, day.day + 1),
        ),
      );
      continue;
    }
    if (day == lastDay) {
      days.add(
        AbsenceSpanDay(
          date: day,
          portion: absencePortionRange,
          startAt: day,
          endAt: to,
        ),
      );
      continue;
    }
    days.add(AbsenceSpanDay(date: day, portion: absencePortionFullDay));
  }
  return days;
}
