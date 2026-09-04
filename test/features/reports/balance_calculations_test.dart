import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/balance_calculations.dart';

import '../../support/app_settings_fixture.dart';

AppSettingsRow settingsWith({
  int monday = 0,
  int tuesday = 0,
  int wednesday = 0,
  int thursday = 0,
  int friday = 0,
  int saturday = 0,
  int sunday = 0,
  String balanceResetMode = 'none',
  int? balanceResetDay,
  int? balanceResetMonth,
  int? carryOverMaxMinutes,
  int? carryOverMinMinutes,
}) {
  return appSettingsFixture(
    targetMinutesMonday: monday,
    targetMinutesTuesday: tuesday,
    targetMinutesWednesday: wednesday,
    targetMinutesThursday: thursday,
    targetMinutesFriday: friday,
    targetMinutesSaturday: saturday,
    targetMinutesSunday: sunday,
    balanceResetMode: balanceResetMode,
    balanceResetDay: balanceResetDay,
    balanceResetMonth: balanceResetMonth,
    carryOverMaxMinutes: carryOverMaxMinutes,
    carryOverMinMinutes: carryOverMinMinutes,
  );
}

/// A finished entry running [minutes] from 09:00 local time on [day].
TimeEntry entryOn(DateTime day, int minutes, {String id = 'e'}) {
  final start = DateTime(day.year, day.month, day.day, 9);
  return TimeEntry(
    id: id,
    startAt: start.toUtc(),
    endAt: start.add(Duration(minutes: minutes)).toUtc(),
    totalPausedSeconds: 0,
    source: 'manual',
    deviceId: 'test',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  // 2026-09-07 is a Monday.
  final monday = DateTime(2026, 9, 7);
  final tuesday = DateTime(2026, 9, 8);
  final saturday = DateTime(2026, 9, 12);

  test('targetMinutesForWeekday reads the column matching the weekday', () {
    final settings = settingsWith(monday: 480, saturday: 120);
    expect(targetMinutesForWeekday(settings, DateTime.monday), 480);
    expect(targetMinutesForWeekday(settings, DateTime.saturday), 120);
    expect(targetMinutesForWeekday(settings, DateTime.sunday), 0);
  });

  test('hasAnyTarget is false only when every weekday is zero', () {
    expect(hasAnyTarget(settingsWith()), isFalse);
    expect(hasAnyTarget(settingsWith(sunday: 1)), isTrue);
  });

  test('a day worked short of its target yields a negative balance', () {
    final balances = dayBalances([entryOn(monday, 420)], settingsWith(monday: 480));
    expect(balances, hasLength(1));
    expect(balances.single.worked, const Duration(minutes: 420));
    expect(balances.single.target, const Duration(minutes: 480));
    expect(balances.single.balance, const Duration(minutes: -60));
  });

  test('several entries on one day are summed into a single day', () {
    final balances = dayBalances(
      [entryOn(monday, 240, id: 'a'), entryOn(monday, 240, id: 'b')],
      settingsWith(monday: 480),
    );
    expect(balances, hasLength(1));
    expect(balances.single.balance, Duration.zero);
  });

  test('time tracked on a day with no target counts fully as a plus', () {
    final balances = dayBalances([entryOn(saturday, 120)], settingsWith(monday: 480));
    expect(balances.single.target, Duration.zero);
    expect(balances.single.balance, const Duration(minutes: 120));
  });

  test('a work day without any entry is not counted while absences are off', () {
    final balances = dayBalances([entryOn(monday, 480)], settingsWith(monday: 480, tuesday: 480));
    expect(balances.map((b) => b.day), [monday]);
  });

  test('a running entry does not contribute a day', () {
    final running = TimeEntry(
      id: 'running',
      startAt: DateTime(monday.year, monday.month, monday.day, 9).toUtc(),
      endAt: null,
      totalPausedSeconds: 0,
      source: 'manual',
      deviceId: 'test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    expect(dayBalances([running], settingsWith(monday: 480)), isEmpty);
  });

  test('days come back ascending regardless of input order', () {
    final balances = dayBalances(
      [entryOn(tuesday, 60, id: 'b'), entryOn(monday, 60, id: 'a')],
      settingsWith(monday: 480, tuesday: 480),
    );
    expect(balances.map((b) => b.day), [monday, tuesday]);
  });
}
