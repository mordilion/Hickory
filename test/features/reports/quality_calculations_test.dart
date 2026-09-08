import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/features/reports/balance_calculations.dart';
import 'package:hickory/features/reports/quality_calculations.dart';

final monday = DateTime(2026, 9, 7);
final tuesday = DateTime(2026, 9, 8);

TimeEntry _entry(DateTime day, {required int startHour, required int minutes, String id = 'e'}) {
  final start = DateTime(day.year, day.month, day.day, startHour);
  return TimeEntry(
    id: id,
    startAt: start.toUtc(),
    endAt: start.add(Duration(minutes: minutes)).toUtc(),
    totalPausedSeconds: 0,
    source: 'manual',
    deviceId: 'd',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Absence _absence(DateTime day, {String typeId = 'type-1', String id = 'a'}) => Absence(
      id: id,
      date: day,
      absenceTypeId: typeId,
      portion: absencePortionFullDay,
      deviceId: 'd',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

AbsenceType _type(String id, String name) => AbsenceType(
      id: id,
      name: name,
      paid: true,
      sortOrder: 0,
      deviceId: 'd',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

BreakRuleTier _tier({required int afterMinutes, required int requiredBreakMinutes}) =>
    BreakRuleTier(
      id: 't1',
      afterMinutes: afterMinutes,
      requiredBreakMinutes: requiredBreakMinutes,
      deviceId: 'd',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

QualityFigures figures({
  List<DayBalance> balances = const [],
  List<TimeEntry> entries = const [],
  List<Absence> absences = const [],
  Map<String, AbsenceType> types = const {},
  List<BreakRuleTier> tiers = const [],
  int failedPushCount = 0,
  DateTimeRange? range,
}) => qualityFigures(
      balances: balances,
      entries: entries,
      absences: absences,
      absenceTypesById: types,
      tiers: tiers,
      includePausedTimeInBreak: false,
      failedPushCount: failedPushCount,
      range: range ?? DateTimeRange(start: monday, end: DateTime(2026, 9, 14)),
    );

void main() {
  test('a work day with neither an entry nor an absence is unbooked', () {
    final result = figures(
      balances: [
        DayBalance(day: monday, worked: Duration.zero, target: const Duration(hours: 8)),
      ],
    );

    expect(result.unbookedWorkDays, [monday]);
  });

  test('a day covered by an absence is not unbooked', () {
    final result = figures(
      balances: [
        DayBalance(day: monday, worked: Duration.zero, target: const Duration(hours: 8)),
      ],
      absences: [_absence(monday)],
      types: {'type-1': _type('type-1', 'Urlaub')},
    );

    expect(result.unbookedWorkDays, isEmpty);
  });

  test('a free day without a booking is not a gap', () {
    final result = figures(
      balances: [
        DayBalance(day: DateTime(2026, 9, 12), worked: Duration.zero, target: Duration.zero),
      ],
    );

    expect(result.unbookedWorkDays, isEmpty);
  });

  test('a day outside the range is not counted', () {
    final result = figures(
      balances: [
        DayBalance(
          day: DateTime(2026, 9, 20),
          worked: Duration.zero,
          target: const Duration(hours: 8),
        ),
      ],
    );

    expect(result.unbookedWorkDays, isEmpty);
  });

  test('a day whose break falls short of the rule is listed', () {
    // Six hours in two entries five minutes apart, against a tier that
    // demands 30 minutes after six hours.
    final result = figures(
      balances: [
        DayBalance(day: monday, worked: const Duration(hours: 6), target: const Duration(hours: 8)),
      ],
      entries: [
        _entry(monday, startHour: 8, minutes: 180, id: 'a'),
        _entry(monday, startHour: 11, minutes: 175, id: 'b'),
      ],
      tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
    );

    expect(result.shortBreakDays, [monday]);
  });

  test('a day that meets the rule is not listed', () {
    final result = figures(
      balances: [
        DayBalance(day: monday, worked: const Duration(hours: 6), target: const Duration(hours: 8)),
      ],
      entries: [
        _entry(monday, startHour: 8, minutes: 180, id: 'a'),
        _entry(monday, startHour: 12, minutes: 180, id: 'b'),
      ],
      tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
    );

    expect(result.shortBreakDays, isEmpty);
  });

  test('without a rule no day is short of a break', () {
    final result = figures(
      balances: [
        DayBalance(day: monday, worked: const Duration(hours: 9), target: const Duration(hours: 8)),
      ],
      entries: [_entry(monday, startHour: 8, minutes: 540)],
    );

    expect(result.shortBreakDays, isEmpty);
  });

  test('absence days are counted per type name', () {
    final result = figures(
      balances: const [],
      absences: [
        _absence(monday, id: 'a1'),
        _absence(tuesday, id: 'a2'),
        _absence(DateTime(2026, 9, 9), typeId: 'type-2', id: 'a3'),
      ],
      types: {'type-1': _type('type-1', 'Urlaub'), 'type-2': _type('type-2', 'Krank')},
    );

    expect(result.absenceDaysByTypeName, {'Urlaub': 2, 'Krank': 1});
  });

  test('an absence whose type is gone is not counted under a guessed name', () {
    final result = figures(absences: [_absence(monday)], types: const {});

    expect(result.absenceDaysByTypeName, isEmpty);
  });

  test('the failed-push count is passed through', () {
    expect(figures(failedPushCount: 3).failedPushCount, 3);
  });
}
