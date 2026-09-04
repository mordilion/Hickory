// Flex-time ("Gleitzeit") balance arithmetic. Pure: no Riverpod, no
// Flutter, no database access beyond drift's row types — the same shape as
// report_calculations.dart, and testable with plain in-memory lists.
//
// Nothing here is materialized in the database on purpose: a cached
// balance would need recomputation after every cross-device event-log
// merge, and those merges happen at arbitrary times.

import '../../data/drift/database.dart';
import '../../data/drift/tables/absences_table.dart';
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
    this.absenceCredit = Duration.zero,
  });

  /// Local midnight of the day, the same key [totalsByDay] groups by.
  final DateTime day;
  final Duration worked;

  /// The day's target after unpaid absences have been taken off it.
  final Duration target;

  /// Time credited by paid absences on this day. Zero unless absence
  /// tracking is on.
  final Duration absenceCredit;

  Duration get balance => worked + absenceCredit - target;
}

/// Entries grouped by the local day they start on — the same grouping
/// [totalsByDay] uses, so a range absence is compared against exactly the
/// entries that day's worked total was built from.
Map<DateTime, List<TimeEntry>> _entriesByDay(List<TimeEntry> entries) {
  final byDay = <DateTime, List<TimeEntry>>{};
  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(entry);
  }
  return byDay;
}

/// Minutes between [from] and [to] already covered by tracked work.
/// Overlapping entries are merged first, so two entries covering the same
/// minute do not subtract it twice.
int _overlapMinutes(DateTime from, DateTime to, List<TimeEntry> dayEntries) {
  final spans = <(DateTime, DateTime)>[];
  for (final entry in dayEntries) {
    final end = entry.endAt;
    if (end == null) continue;
    final start = entry.startAt.isAfter(from) ? entry.startAt : from;
    final stop = end.isBefore(to) ? end : to;
    if (!stop.isAfter(start)) continue;
    spans.add((start, stop));
  }
  if (spans.isEmpty) return 0;
  spans.sort((a, b) => a.$1.compareTo(b.$1));

  var covered = Duration.zero;
  var currentStart = spans.first.$1;
  var currentEnd = spans.first.$2;
  for (final span in spans.skip(1)) {
    if (span.$1.isAfter(currentEnd)) {
      covered += currentEnd.difference(currentStart);
      currentStart = span.$1;
      currentEnd = span.$2;
      continue;
    }
    if (span.$2.isAfter(currentEnd)) currentEnd = span.$2;
  }
  return (covered + currentEnd.difference(currentStart)).inMinutes;
}

/// What one absence contributes on its day, in minutes.
///
/// A full day is worth the day's whole target and a half day exactly half
/// of it — neither stores a minute figure, so both stay correct if the
/// target is changed later. A range is worth its own length minus any
/// overlap with tracked work, so an appointment that was also tracked as
/// work cannot be counted twice. Full and half days are deliberately not
/// reduced by tracked work: someone who works on a vacation day should see
/// that time as a plus.
int absenceMinutes(
  Absence absence,
  int dayTargetMinutes,
  List<TimeEntry> dayEntries,
) {
  switch (absence.portion) {
    case absencePortionFullDay:
      return dayTargetMinutes;
    case absencePortionHalfDay:
      return dayTargetMinutes ~/ 2;
    case absencePortionRange:
      final from = absence.startAt;
      final to = absence.endAt;
      if (from == null || to == null || !to.isAfter(from)) return 0;
      final minutes =
          to.difference(from).inMinutes - _overlapMinutes(from, to, dayEntries);
      return minutes < 0 ? 0 : minutes;
    default:
      // A portion this version does not know, written by a newer peer.
      // Contributing nothing is the safe reading: it neither invents
      // credit nor removes target the user did not ask to remove.
      return 0;
  }
}

/// Per-day balances, ascending by day.
///
/// With absence tracking **off**, only days carrying at least one finished
/// entry are returned and [absences] is ignored entirely: a day off cannot
/// be recorded, so counting empty work days would manufacture a deficit.
///
/// With it **on**, every work day between the first known day and
/// [through] is returned, so a work day with neither entries nor an
/// absence shows up as a deficit — that visibility is the point of the
/// feature. Days that are neither a work day nor carry anything are still
/// skipped, so a weekend adds no rows.
///
/// [through] is the last day to enumerate, normally today. It only extends
/// the range; days before the first entry or absence are never invented,
/// because a balance cannot start before the user did.
List<DayBalance> dayBalances(
  List<TimeEntry> entries,
  AppSettingsRow settings, {
  List<Absence> absences = const [],
  Map<String, AbsenceType> absenceTypesById = const {},
  DateTime? through,
}) {
  final workedByDay = totalsByDay(entries);

  if (!settings.absenceTrackingEnabled) {
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

  final entriesByDay = _entriesByDay(entries);
  final absencesByDay = <DateTime, List<Absence>>{};
  for (final absence in absences) {
    final date = absence.date;
    final day = DateTime(date.year, date.month, date.day);
    absencesByDay.putIfAbsent(day, () => []).add(absence);
  }

  final known = <DateTime>{...workedByDay.keys, ...absencesByDay.keys};
  if (known.isEmpty) return const [];
  final first = known.reduce((a, b) => a.isBefore(b) ? a : b);
  var last = known.reduce((a, b) => a.isAfter(b) ? a : b);
  if (through != null && through.isAfter(last)) last = through;

  final result = <DayBalance>[];
  for (
    var day = first;
    !day.isAfter(last);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final worked = workedByDay[day] ?? Duration.zero;
    final dayAbsences = absencesByDay[day] ?? const <Absence>[];
    final target = targetMinutesForWeekday(settings, day.weekday);
    if (target == 0 && worked == Duration.zero && dayAbsences.isEmpty) continue;

    var paidMinutes = 0;
    var unpaidMinutes = 0;
    for (final absence in dayAbsences) {
      final type = absenceTypesById[absence.absenceTypeId];
      // An absence whose type cannot be resolved — deleted, or not loaded
      // yet — contributes nothing rather than being guessed at.
      if (type == null) continue;
      final minutes =
          absenceMinutes(absence, target, entriesByDay[day] ?? const []);
      if (type.paid) {
        paidMinutes += minutes;
      } else {
        unpaidMinutes += minutes;
      }
    }

    final effectiveTarget = target - unpaidMinutes;
    result.add(
      DayBalance(
        day: day,
        worked: worked,
        target: Duration(minutes: effectiveTarget < 0 ? 0 : effectiveTarget),
        absenceCredit: Duration(minutes: paidMinutes),
      ),
    );
  }
  return result;
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
