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

  test('lastCutoffOnOrBefore returns null when no rule is configured', () {
    expect(lastCutoffOnOrBefore(settingsWith(), DateTime(2026, 9, 7)), isNull);
  });

  test('lastCutoffOnOrBefore returns null when the rule lacks a date', () {
    final settings = settingsWith(balanceResetMode: 'resetToZero');
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 9, 7)), isNull);
  });

  test('lastCutoffOnOrBefore picks this year once the date has passed', () {
    final settings = settingsWith(
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 7,
    );
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 9, 7)), DateTime(2026, 7, 1));
  });

  test('lastCutoffOnOrBefore falls back to last year before the date', () {
    final settings = settingsWith(
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 7,
    );
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 3, 1)), DateTime(2025, 7, 1));
  });

  test('a 29 February cutoff clamps to the 28th in a non-leap year', () {
    final settings = settingsWith(
      balanceResetMode: 'resetToZero',
      balanceResetDay: 29,
      balanceResetMonth: 2,
    );
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 6, 1)), DateTime(2026, 2, 28));
  });

  test('without a rule the balance is the plain sum', () {
    final settings = settingsWith(monday: 480, tuesday: 480);
    final balances = dayBalances(
      [entryOn(monday, 540, id: 'a'), entryOn(tuesday, 540, id: 'b')],
      settings,
    );
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 120),
    );
  });

  test('resetToZero drops everything earned before the cutoff', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 9,
    );
    // 2026-08-31 is a Monday, 2026-09-07 the next one.
    final balances = dayBalances(
      [entryOn(DateTime(2026, 8, 31), 540, id: 'a'), entryOn(monday, 540, id: 'b')],
      settings,
    );
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 60),
      reason: 'only the day after the 1 September cutoff survives',
    );
  });

  test('a cutoff after the last worked day still applies', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 10,
    );
    final balances = dayBalances([entryOn(monday, 540)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 10, 5)),
      Duration.zero,
    );
  });

  test('carryOver clamps the surviving balance to the maximum', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'carryOver',
      balanceResetDay: 1,
      balanceResetMonth: 9,
      carryOverMaxMinutes: 30,
    );
    final balances = dayBalances([entryOn(DateTime(2026, 8, 31), 600)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 30),
      reason: '120 minutes earned, only 30 carried over',
    );
  });

  test('carryOver clamps a deficit to the minimum', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'carryOver',
      balanceResetDay: 1,
      balanceResetMonth: 9,
      carryOverMinMinutes: -30,
    );
    final balances = dayBalances([entryOn(DateTime(2026, 8, 31), 300)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: -30),
    );
  });

  test('carryOver leaves a balance inside the bounds alone', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'carryOver',
      balanceResetDay: 1,
      balanceResetMonth: 9,
      carryOverMaxMinutes: 600,
      carryOverMinMinutes: -600,
    );
    final balances = dayBalances([entryOn(DateTime(2026, 8, 31), 540)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 60),
    );
  });

  test('several cutoffs in a gap between worked days all apply', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 1,
    );
    // 2024-01-08 and 2026-01-05 are both Mondays, with two cutoffs between.
    final balances = dayBalances(
      [entryOn(DateTime(2024, 1, 8), 600, id: 'a'), entryOn(DateTime(2026, 1, 5), 540, id: 'b')],
      settings,
    );
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 2, 1)),
      const Duration(minutes: 60),
    );
  });

  test('days after asOf are ignored', () {
    final settings = settingsWith(monday: 480, tuesday: 480);
    final balances = dayBalances(
      [entryOn(monday, 540, id: 'a'), entryOn(tuesday, 540, id: 'b')],
      settings,
    );
    expect(runningBalance(balances, settings, asOf: monday), const Duration(minutes: 60));
  });
}
