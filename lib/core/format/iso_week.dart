// ISO 8601 calendar helpers. The convention is fixed rather than
// locale-derived: all six supported languages use it, and a locale-dependent
// week number would put the same day in different weeks per language.
//
// Every function here takes a local date, ignores the time component, and
// returns local midnight. Day arithmetic goes through the DateTime constructor
// (which normalizes out-of-range values) rather than add/subtract, so a
// daylight-saving boundary can't shift a result off midnight.

/// Local-midnight Monday of [day]'s ISO week.
DateTime mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// ISO 8601 week number (1-53) of [day].
int isoWeekNumber(DateTime day) {
  final monday = mondayOf(day);
  // The week's Thursday decides which ISO year the week belongs to.
  final thursday = DateTime(monday.year, monday.month, monday.day + 3);
  final firstThursday = _firstThursdayOf(thursday.year);
  final firstWeekMonday = DateTime(
    firstThursday.year,
    firstThursday.month,
    firstThursday.day - 3,
  );
  return _wholeDaysBetween(firstWeekMonday, monday) ~/ 7 + 1;
}

/// `2026-08-04` -- the canonical date part of an expansion key. Zero-padded so
/// keys compare as plain strings.
String isoDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _firstThursdayOf(int year) {
  final january1 = DateTime(year, 1, 1);
  final offset = (DateTime.thursday - january1.weekday + 7) % 7;
  return DateTime(year, 1, 1 + offset);
}

/// Calendar days from [from] to [to]. Goes through UTC because a local
/// `difference` spanning a daylight-saving change is 23 or 25 hours, which
/// truncates to the wrong number of days.
int _wholeDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
