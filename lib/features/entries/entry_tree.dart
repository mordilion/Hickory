import '../../core/format/iso_week.dart';
import '../../data/drift/database.dart';
import 'day_grouping.dart';

/// A year of entries, newest month first.
class EntryYearGroup {
  const EntryYearGroup({
    required this.year,
    required this.months,
    required this.totalDuration,
    required this.breakDuration,
    required this.insufficientBreakDays,
  });

  final int year;
  final List<EntryMonthGroup> months;
  final Duration totalDuration;
  final Duration breakDuration;

  /// Number of days below this node whose break falls short of the rule.
  final int insufficientBreakDays;
}

/// A calendar month of entries, newest week first.
class EntryMonthGroup {
  const EntryMonthGroup({
    required this.year,
    required this.month,
    required this.weeks,
    required this.totalDuration,
    required this.breakDuration,
    required this.insufficientBreakDays,
  });

  final int year;
  final int month;
  final List<EntryWeekGroup> weeks;
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}

/// One ISO week's entries *within a single month*, newest day first.
///
/// A week crossing a month boundary yields two of these -- one per month -- so
/// month and year totals stay true to the calendar period. [monday] is the
/// week's calendar Monday (shared by both halves), while [firstDay] and
/// [lastDay] cover only the days this node actually holds.
class EntryWeekGroup {
  const EntryWeekGroup({
    required this.isoWeek,
    required this.monday,
    required this.year,
    required this.month,
    required this.firstDay,
    required this.lastDay,
    required this.days,
    required this.totalDuration,
    required this.breakDuration,
    required this.insufficientBreakDays,
  });

  final int isoWeek;
  final DateTime monday;
  final int year;
  final int month;
  final DateTime firstDay;
  final DateTime lastDay;
  final List<EntryDayGroup> days;
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}

String yearTreeKey(int year) => 'y$year';

String monthTreeKey(int year, int month) =>
    'm$year-${month.toString().padLeft(2, '0')}';

/// The month is part of the key because a week crossing a month boundary
/// becomes two nodes sharing one [EntryWeekGroup.monday]; without it,
/// collapsing one half would collapse the other. Keeping the key computable
/// from the calendar alone is what lets [defaultExpandedKeys] name today's
/// week without knowing which days actually hold entries.
String weekTreeKey(DateTime monday, int year, int month) =>
    'w${isoDayKey(monday)}-$year-${month.toString().padLeft(2, '0')}';

String dayTreeKey(DateTime day) => 'd${isoDayKey(day)}';

/// Expansion keys for the path to [today]: its year, month, ISO week and the
/// day itself.
Set<String> defaultExpandedKeys(DateTime today) => {
  yearTreeKey(today.year),
  monthTreeKey(today.year, today.month),
  weekTreeKey(mondayOf(today), today.year, today.month),
  dayTreeKey(DateTime(today.year, today.month, today.day)),
};

/// Groups [entries] into Year > Month > ISO week > Day, newest first at every
/// level, with worked/break totals and offending-day counts rolled up.
///
/// [tiers] and [includePausedTimeInBreak] pass straight through to
/// [groupEntriesByDay]. A week spanning a month boundary is split at that
/// boundary (see [EntryWeekGroup]).
List<EntryYearGroup> buildEntryTree(
  List<TimeEntry> entries, {
  required List<BreakRuleTier> tiers,
  bool includePausedTimeInBreak = false,
}) {
  final days = groupEntriesByDay(
    entries,
    tiers: tiers,
    includePausedTimeInBreak: includePausedTimeInBreak,
  );

  // Dart maps keep insertion order and `days` is newest-first, so the first
  // time a week, month or year is seen it is also the newest one -- every
  // level comes out sorted without a single sort call.
  final daysByWeek = <String, List<EntryDayGroup>>{};
  for (final day in days) {
    // The month/year part of the key is the *day's* own, never the week's:
    // that is what splits a boundary-crossing week into two nodes.
    final key = weekTreeKey(mondayOf(day.day), day.day.year, day.day.month);
    daysByWeek.putIfAbsent(key, () => []).add(day);
  }

  final weeksByMonth = <String, List<EntryWeekGroup>>{};
  for (final dayGroups in daysByWeek.values) {
    final week = _weekGroup(dayGroups);
    weeksByMonth
        .putIfAbsent(monthTreeKey(week.year, week.month), () => [])
        .add(week);
  }

  final monthsByYear = <int, List<EntryMonthGroup>>{};
  for (final weeks in weeksByMonth.values) {
    final month = _monthGroup(weeks);
    monthsByYear.putIfAbsent(month.year, () => []).add(month);
  }

  return [for (final months in monthsByYear.values) _yearGroup(months)];
}

EntryWeekGroup _weekGroup(List<EntryDayGroup> days) {
  final newest = days.first.day;
  return EntryWeekGroup(
    isoWeek: isoWeekNumber(newest),
    monday: mondayOf(newest),
    year: newest.year,
    month: newest.month,
    // `days` is newest-first, so the last element is the earliest day.
    firstDay: days.last.day,
    lastDay: newest,
    days: days,
    totalDuration: _sum(days.map((day) => day.totalDuration)),
    breakDuration: _sum(days.map((day) => day.breakDuration)),
    insufficientBreakDays: days.where((day) => day.isBreakInsufficient).length,
  );
}

EntryMonthGroup _monthGroup(List<EntryWeekGroup> weeks) => EntryMonthGroup(
  year: weeks.first.year,
  month: weeks.first.month,
  weeks: weeks,
  totalDuration: _sum(weeks.map((week) => week.totalDuration)),
  breakDuration: _sum(weeks.map((week) => week.breakDuration)),
  insufficientBreakDays: weeks.fold(
    0,
    (sum, week) => sum + week.insufficientBreakDays,
  ),
);

EntryYearGroup _yearGroup(List<EntryMonthGroup> months) => EntryYearGroup(
  year: months.first.year,
  months: months,
  totalDuration: _sum(months.map((month) => month.totalDuration)),
  breakDuration: _sum(months.map((month) => month.breakDuration)),
  insufficientBreakDays: months.fold(
    0,
    (sum, month) => sum + month.insufficientBreakDays,
  ),
);

Duration _sum(Iterable<Duration> durations) =>
    durations.fold(Duration.zero, (sum, duration) => sum + duration);

/// One rendered line of the entries list. [EntryTreeEntriesRow] is the card of
/// entry tiles that follows an expanded day's header.
sealed class EntryTreeRow {
  const EntryTreeRow();
}

class EntryTreeYearRow extends EntryTreeRow {
  const EntryTreeYearRow(this.year);

  final EntryYearGroup year;
}

class EntryTreeMonthRow extends EntryTreeRow {
  const EntryTreeMonthRow(this.month);

  final EntryMonthGroup month;
}

class EntryTreeWeekRow extends EntryTreeRow {
  const EntryTreeWeekRow(this.week);

  final EntryWeekGroup week;
}

class EntryTreeDayRow extends EntryTreeRow {
  const EntryTreeDayRow(this.day);

  final EntryDayGroup day;
}

class EntryTreeEntriesRow extends EntryTreeRow {
  const EntryTreeEntriesRow(this.day);

  final EntryDayGroup day;
}

/// Flattens [years] into the rows currently visible for [expanded] (keys from
/// [yearTreeKey] and friends).
///
/// A node's children are emitted only while its own key is present, so a
/// collapsed year costs one row no matter how much sits below it. Keys naming
/// nodes that no longer exist are ignored.
List<EntryTreeRow> flattenEntryTree(
  List<EntryYearGroup> years,
  Set<String> expanded,
) {
  final rows = <EntryTreeRow>[];
  for (final year in years) {
    rows.add(EntryTreeYearRow(year));
    if (!expanded.contains(yearTreeKey(year.year))) continue;
    for (final month in year.months) {
      rows.add(EntryTreeMonthRow(month));
      if (!expanded.contains(monthTreeKey(month.year, month.month))) continue;
      for (final week in month.weeks) {
        rows.add(EntryTreeWeekRow(week));
        if (!expanded.contains(
          weekTreeKey(week.monday, week.year, week.month),
        )) {
          continue;
        }
        for (final day in week.days) {
          rows.add(EntryTreeDayRow(day));
          if (!expanded.contains(dayTreeKey(day.day))) continue;
          rows.add(EntryTreeEntriesRow(day));
        }
      }
    }
  }
  return rows;
}
