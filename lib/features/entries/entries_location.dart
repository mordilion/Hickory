import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/format/iso_week.dart';
import 'entry_tree.dart';

part 'entries_location.g.dart';

/// Where the entries list currently is: the years list, one year, one month, or
/// one ISO week. Only one level shows at a time -- the list drills down rather
/// than expanding in place (see
/// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md).
sealed class EntriesLocation {
  const EntriesLocation();
}

final class EntriesYearsLocation extends EntriesLocation {
  const EntriesYearsLocation();

  @override
  bool operator ==(Object other) => other is EntriesYearsLocation;

  @override
  int get hashCode => 0;
}

final class EntriesYearLocation extends EntriesLocation {
  const EntriesYearLocation(this.year);

  final int year;

  @override
  bool operator ==(Object other) =>
      other is EntriesYearLocation && other.year == year;

  @override
  int get hashCode => year.hashCode;
}

final class EntriesMonthLocation extends EntriesLocation {
  const EntriesMonthLocation(this.year, this.month);

  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is EntriesMonthLocation &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// [monday] is the week's calendar Monday; [year] and [month] name the half it
/// belongs to, since a week crossing a month boundary is two nodes.
final class EntriesWeekLocation extends EntriesLocation {
  const EntriesWeekLocation({
    required this.monday,
    required this.year,
    required this.month,
  });

  final DateTime monday;
  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is EntriesWeekLocation &&
      other.monday == monday &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(monday, year, month);
}

/// What to render for the current location.
sealed class EntriesView {
  const EntriesView();
}

final class EntriesYearsView extends EntriesView {
  const EntriesYearsView(this.years);

  final List<EntryYearGroup> years;
}

final class EntriesMonthsView extends EntriesView {
  const EntriesMonthsView(this.year);

  final EntryYearGroup year;
}

final class EntriesWeeksView extends EntriesView {
  const EntriesWeeksView(this.month);

  final EntryMonthGroup month;
}

/// The deepest view: one week's days, each with its own entries.
final class EntriesWeekView extends EntriesView {
  const EntriesWeekView(this.week);

  final EntryWeekGroup week;
}

/// One level up, or null at the years list.
EntriesLocation? parentOf(EntriesLocation location) => switch (location) {
  EntriesYearsLocation() => null,
  EntriesYearLocation() => const EntriesYearsLocation(),
  EntriesMonthLocation(:final year) => EntriesYearLocation(year),
  EntriesWeekLocation(:final year, :final month) => EntriesMonthLocation(
    year,
    month,
  ),
};

/// Where to open on a cold start: the week holding [today] if it has entries,
/// otherwise the newest week there is, otherwise the years list. Landing on the
/// current week keeps today's entries one glance away, the way the flat list
/// used to.
EntriesLocation initialLocation(List<EntryYearGroup> years, DateTime today) {
  if (years.isEmpty) return const EntriesYearsLocation();
  final monday = mondayOf(today);
  for (final year in years) {
    for (final month in year.months) {
      for (final week in month.weeks) {
        if (week.monday == monday &&
            week.year == today.year &&
            week.month == today.month) {
          return _locationOf(week);
        }
      }
    }
  }
  return _locationOf(years.first.months.first.weeks.first);
}

/// Resolves [location] against [years], falling back to the nearest surviving
/// ancestor when the node it names is gone -- deleting a week's last entry
/// must not leave the list stranded on an empty view.
EntriesView viewFor(List<EntryYearGroup> years, EntriesLocation location) {
  if (location is EntriesYearsLocation) return EntriesYearsView(years);

  final wantedYear = switch (location) {
    EntriesYearLocation(:final year) => year,
    EntriesMonthLocation(:final year) => year,
    EntriesWeekLocation(:final year) => year,
    EntriesYearsLocation() => null,
  };
  final year = years
      .where((candidate) => candidate.year == wantedYear)
      .firstOrNull;
  if (year == null) return EntriesYearsView(years);
  if (location is EntriesYearLocation) return EntriesMonthsView(year);

  final wantedMonth = switch (location) {
    EntriesMonthLocation(:final month) => month,
    EntriesWeekLocation(:final month) => month,
    _ => null,
  };
  final month = year.months
      .where((candidate) => candidate.month == wantedMonth)
      .firstOrNull;
  if (month == null) return EntriesMonthsView(year);
  if (location is EntriesMonthLocation) return EntriesWeeksView(month);

  final wanted = location as EntriesWeekLocation;
  final week = month.weeks
      .where((candidate) => candidate.monday == wanted.monday)
      .firstOrNull;
  if (week == null) return EntriesWeeksView(month);
  return EntriesWeekView(week);
}

EntriesLocation _locationOf(EntryWeekGroup week) => EntriesWeekLocation(
  monday: week.monday,
  year: week.year,
  month: week.month,
);

/// The list's current location. Kept alive so switching tabs doesn't send you
/// back to the start, and deliberately not persisted: every app start reopens
/// the current week. Null means "not navigated yet", which the list resolves
/// through [initialLocation] once it knows what data exists.
@Riverpod(keepAlive: true)
class EntriesLocationController extends _$EntriesLocationController {
  @override
  EntriesLocation? build() => null;

  void goTo(EntriesLocation location) => state = location;
}
