import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
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
  bool absenceTracking = false,
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
    absenceTrackingEnabled: absenceTracking,
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

AbsenceType typeFixture({
  String id = 'type-1',
  String name = 'Vacation',
  bool paid = true,
}) {
  return AbsenceType(
    id: id,
    name: name,
    paid: paid,
    sortOrder: 0,
    deviceId: 'test',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Absence absenceOn(
  DateTime day, {
  String id = 'absence-1',
  String typeId = 'type-1',
  String portion = absencePortionFullDay,
  DateTime? startAt,
  DateTime? endAt,
}) {
  return Absence(
    id: id,
    date: DateTime(day.year, day.month, day.day),
    absenceTypeId: typeId,
    portion: portion,
    startAt: startAt,
    endAt: endAt,
    note: null,
    deviceId: 'test',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}


BalanceAdjustment adjustmentOn(DateTime date, int deltaMinutes, {String id = 'adj-1'}) =>
    BalanceAdjustment(
      id: id,
      date: date,
      deltaMinutes: deltaMinutes,
      note: null,
      deviceId: 'device-1',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

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

  // Pins the *detection* of every crossing in the gap, not the fact that
  // the rule is applied once per crossing: _afterCutoff is idempotent, so
  // no assertion can tell one application from three. The value is in
  // catching a walk that skips a crossing altogether.
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

  final friday = DateTime(2026, 9, 11);

  test('absences are ignored while absence tracking is off', () {
    final balances = dayBalances(
      [entryOn(monday, 420)],
      settingsWith(monday: 480),
      absences: [absenceOn(monday)],
      absenceTypesById: {'type-1': typeFixture()},
    );
    expect(balances.single.absenceCredit, Duration.zero);
    expect(balances.single.balance, const Duration(minutes: -60));
  });

  test('a paid full-day absence makes the day neutral', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [absenceOn(monday)],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(balances.single.worked, Duration.zero);
    expect(balances.single.target, const Duration(minutes: 480));
    expect(balances.single.absenceCredit, const Duration(minutes: 480));
    expect(balances.single.balance, Duration.zero);
  });

  test('an unpaid full-day absence is neutral and reports no target', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [absenceOn(monday)],
      absenceTypesById: {'type-1': typeFixture(paid: false)},
      through: monday,
    );
    expect(balances.single.target, Duration.zero, reason: 'unpaid time is taken off the target');
    expect(balances.single.absenceCredit, Duration.zero);
    expect(balances.single.balance, Duration.zero);
  });

  test('a paid half day plus half a day of work is neutral', () {
    final balances = dayBalances(
      [entryOn(monday, 240)],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [absenceOn(monday, portion: absencePortionHalfDay)],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(balances.single.absenceCredit, const Duration(minutes: 240));
    expect(balances.single.balance, Duration.zero);
  });

  test('an unpaid half day halves the target', () {
    final balances = dayBalances(
      [entryOn(monday, 240)],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [absenceOn(monday, portion: absencePortionHalfDay)],
      absenceTypesById: {'type-1': typeFixture(paid: false)},
      through: monday,
    );
    expect(balances.single.target, const Duration(minutes: 240));
    expect(balances.single.balance, Duration.zero);
  });

  test('a paid range credits its own length', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(
          monday,
          portion: absencePortionRange,
          startAt: DateTime(2026, 9, 7, 9).toUtc(),
          endAt: DateTime(2026, 9, 7, 11).toUtc(),
        ),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(balances.single.absenceCredit, const Duration(minutes: 120));
    expect(balances.single.balance, const Duration(minutes: -360));
  });

  test('a paid range does not credit minutes also tracked as work', () {
    // entryOn starts at 09:00 local, so 60 minutes of it sit inside the
    // 09:00-11:00 absence.
    final balances = dayBalances(
      [entryOn(monday, 60)],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(
          monday,
          portion: absencePortionRange,
          startAt: DateTime(2026, 9, 7, 9).toUtc(),
          endAt: DateTime(2026, 9, 7, 11).toUtc(),
        ),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(balances.single.absenceCredit, const Duration(minutes: 60));
    expect(balances.single.worked, const Duration(minutes: 60));
    expect(balances.single.balance, const Duration(minutes: -360));
  });

  test('two overlapping entries do not subtract the same minute twice', () {
    final balances = dayBalances(
      [entryOn(monday, 60, id: 'a'), entryOn(monday, 30, id: 'b')],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(
          monday,
          portion: absencePortionRange,
          startAt: DateTime(2026, 9, 7, 9).toUtc(),
          endAt: DateTime(2026, 9, 7, 11).toUtc(),
        ),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(
      balances.single.absenceCredit,
      const Duration(minutes: 60),
      reason: 'both entries start at 09:00, so together they cover 60 minutes, not 90',
    );
  });

  test('work on a paid full-day absence counts as a plus', () {
    final balances = dayBalances(
      [entryOn(monday, 120)],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [absenceOn(monday)],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(balances.single.balance, const Duration(minutes: 120));
  });

  // Two absences on one day is the only shape in which the paid/unpaid
  // split and the credit cap interact at all: with a single absence each
  // is applied on its own.
  test('a paid and an unpaid half day on one day cancel out', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(monday, id: 'paid', portion: absencePortionHalfDay),
        absenceOn(monday, id: 'unpaid', typeId: 'type-2', portion: absencePortionHalfDay),
      ],
      absenceTypesById: {
        'type-1': typeFixture(paid: true),
        'type-2': typeFixture(id: 'type-2', paid: false),
      },
      through: monday,
    );
    // The unpaid half takes 240 minutes off the target; the paid half
    // credits the other 240 and is not capped away by it.
    expect(balances.single.target, const Duration(minutes: 240));
    expect(balances.single.absenceCredit, const Duration(minutes: 240));
    expect(balances.single.balance, Duration.zero);
  });

  test('two paid absences on one day are capped at the day\'s target together', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(monday, id: 'full'),
        absenceOn(monday, id: 'half', portion: absencePortionHalfDay),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    // 480 + 240 claimed, 480 credited: absence excuses work, it never
    // manufactures overtime.
    expect(balances.single.absenceCredit, const Duration(minutes: 480));
    expect(balances.single.balance, Duration.zero);
  });

  test('an unpaid full day leaves a paid absence beside it nothing to credit', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(monday, id: 'unpaid', typeId: 'type-2'),
        absenceOn(monday, id: 'paid', portion: absencePortionHalfDay),
      ],
      absenceTypesById: {
        'type-1': typeFixture(paid: true),
        'type-2': typeFixture(id: 'type-2', paid: false),
      },
      through: monday,
    );
    // The unpaid day already removed the whole target, so the cap —
    // effective target, not the raw one — holds the paid credit at zero
    // rather than turning it into overtime.
    expect(balances.single.target, Duration.zero);
    expect(balances.single.absenceCredit, Duration.zero);
    expect(balances.single.balance, Duration.zero);
  });

  test('a work day with neither entries nor absence is a deficit while tracking is on', () {
    final balances = dayBalances(
      [entryOn(monday, 480)],
      settingsWith(monday: 480, tuesday: 480, absenceTracking: true),
      through: tuesday,
    );
    expect(balances.map((b) => b.day), [monday, tuesday]);
    expect(balances.last.balance, const Duration(minutes: -480));
  });

  test('a day with no target and no entries is skipped even while tracking is on', () {
    final balances = dayBalances(
      [entryOn(monday, 480)],
      settingsWith(monday: 480, absenceTracking: true),
      through: saturday,
    );
    expect(balances.map((b) => b.day), [monday]);
  });

  test('an absence whose type is unknown contributes nothing', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [absenceOn(monday, typeId: 'deleted-type')],
      absenceTypesById: const {},
      through: monday,
    );
    expect(balances.single.absenceCredit, Duration.zero);
    expect(balances.single.target, const Duration(minutes: 480));
    expect(balances.single.balance, const Duration(minutes: -480));
  });

  test('through extends the enumerated range past the last known day', () {
    final balances = dayBalances(
      [entryOn(monday, 480)],
      settingsWith(
        monday: 480, tuesday: 480, wednesday: 480, thursday: 480, friday: 480,
        absenceTracking: true,
      ),
      through: friday,
    );
    expect(balances, hasLength(5));
    expect(balances.last.day, friday);
  });

  test('a running entry still contributes no day while tracking is on', () {
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
    expect(
      dayBalances(
        [running],
        settingsWith(monday: 480, absenceTracking: true),
      ),
      isEmpty,
      reason: 'with no finished entry and no absence there is no known day to start from',
    );
  });

  test('a paused entry inside a paid range is not charged for the pause', () {
    // 09:00-11:00, but with the middle hour paused: only 60 minutes were
    // actually worked, so only 60 minutes should count as overlap with the
    // absence, leaving the other 60 minutes of the range as credit.
    final pausedEntry = TimeEntry(
      id: 'paused',
      startAt: DateTime(2026, 9, 7, 9).toUtc(),
      endAt: DateTime(2026, 9, 7, 11).toUtc(),
      totalPausedSeconds: 3600,
      source: 'manual',
      deviceId: 'test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final balances = dayBalances(
      [pausedEntry],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(
          monday,
          portion: absencePortionRange,
          startAt: DateTime(2026, 9, 7, 9).toUtc(),
          endAt: DateTime(2026, 9, 7, 11).toUtc(),
        ),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(balances.single.worked, const Duration(minutes: 60));
    expect(balances.single.absenceCredit, const Duration(minutes: 60));
    expect(
      balances.single.balance,
      const Duration(minutes: -360),
      reason: 'the paused hour was never worked, so it is absence credit, not overlap',
    );
  });

  test('a paid range on a day with a zero target yields a zero balance and no credit', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(
          saturday,
          portion: absencePortionRange,
          startAt: DateTime(2026, 9, 12, 9).toUtc(),
          endAt: DateTime(2026, 9, 12, 11).toUtc(),
        ),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: saturday,
    );
    expect(balances.single.target, Duration.zero);
    expect(
      balances.single.absenceCredit,
      Duration.zero,
      reason: 'being absent on a non-work day cannot earn a credit',
    );
    expect(balances.single.balance, Duration.zero);
  });

  test('a paid range longer than the target yields a neutral day rather than a surplus', () {
    final balances = dayBalances(
      const [],
      settingsWith(monday: 480, absenceTracking: true),
      absences: [
        absenceOn(
          monday,
          portion: absencePortionRange,
          startAt: DateTime(2026, 9, 7, 8).toUtc(),
          endAt: DateTime(2026, 9, 7, 20).toUtc(),
        ),
      ],
      absenceTypesById: {'type-1': typeFixture(paid: true)},
      through: monday,
    );
    expect(
      balances.single.absenceCredit,
      const Duration(minutes: 480),
      reason: 'credit is capped at the effective target, not the raw 720-minute span',
    );
    expect(
      balances.single.balance,
      Duration.zero,
      reason: 'being absent cannot earn overtime',
    );
  });

  group('figuresForRange', () {
    test('sums only the days inside the range, whose end is exclusive', () {
      final balances = [
        DayBalance(
          day: DateTime(2026, 9, 7),
          worked: const Duration(hours: 9),
          target: const Duration(hours: 8),
        ),
        DayBalance(
          day: DateTime(2026, 9, 8),
          worked: const Duration(hours: 7),
          target: const Duration(hours: 8),
        ),
        DayBalance(
          day: DateTime(2026, 9, 9),
          worked: const Duration(hours: 8),
          target: const Duration(hours: 8),
        ),
      ];

      final figures = figuresForRange(
        balances,
        DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 9)),
      );

      expect(figures.worked, const Duration(hours: 16));
      expect(figures.target, const Duration(hours: 16));
      expect(figures.balance, Duration.zero);
      expect(figures.workDays, 2, reason: 'the 9th is the exclusive end, so it is out');
    });

    test('counts paid absence toward the range, as the day balance does', () {
      final figures = figuresForRange(
        [
          DayBalance(
            day: DateTime(2026, 9, 7),
            worked: Duration.zero,
            target: const Duration(hours: 8),
            absenceCredit: const Duration(hours: 8),
          ),
        ],
        DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 8)),
      );

      expect(figures.absenceCredit, const Duration(hours: 8));
      expect(figures.balance, Duration.zero, reason: 'a paid day off is neutral');
      expect(figures.completion, 1.0);
    });

    test('averages over work days, not calendar days', () {
      final balances = [
        DayBalance(
          day: DateTime(2026, 9, 7),
          worked: const Duration(hours: 10),
          target: const Duration(hours: 8),
        ),
        // A Saturday that was worked: no target, so it is not a work day,
        // but every one of its minutes is a surplus.
        DayBalance(
          day: DateTime(2026, 9, 12),
          worked: const Duration(hours: 2),
          target: Duration.zero,
        ),
      ];

      final figures = figuresForRange(
        balances,
        DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 14)),
      );

      expect(figures.workDays, 1);
      expect(figures.balance, const Duration(hours: 4));
      expect(
        figures.averagePerWorkDay,
        const Duration(hours: 10),
        reason: "the Saturday's two hours are a surplus, not part of a working day",
      );
    });

    test('an empty range reports zeroes rather than dividing by nothing', () {
      final figures = figuresForRange(
        const [],
        DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 8)),
      );

      expect(figures.worked, Duration.zero);
      expect(figures.averagePerWorkDay, Duration.zero);
      expect(figures.completion, 0);
    });

    test('a range of free days reports no completion instead of dividing by zero', () {
      final figures = figuresForRange(
        [
          DayBalance(
            day: DateTime(2026, 9, 12),
            worked: const Duration(hours: 3),
            target: Duration.zero,
          ),
        ],
        DateTimeRange(start: DateTime(2026, 9, 12), end: DateTime(2026, 9, 13)),
      );

      expect(figures.completion, 0);
      expect(figures.balance, const Duration(hours: 3));
    });
  });

  group('balance corrections', () {
    test('a correction is added on its effective date', () {
      final settings = settingsWith(monday: 480);
      final balances = dayBalances([entryOn(monday, 480)], settings);

      expect(
        runningBalance(
          balances,
          settings,
          asOf: DateTime(2026, 9, 30),
          adjustments: [adjustmentOn(monday, -120)],
        ),
        const Duration(minutes: -120),
      );
    });

    test('a correction on a day with no work of its own still counts', () {
      final settings = settingsWith(monday: 480);

      expect(
        runningBalance(
          const [],
          settings,
          asOf: DateTime(2026, 9, 30),
          adjustments: [adjustmentOn(DateTime(2026, 9, 12), 90)],
        ),
        const Duration(minutes: 90),
        reason: 'a correction is a fact about a day, not an annotation on a worked one',
      );
    });

    test('a correction after the reporting date is not counted yet', () {
      final settings = settingsWith(monday: 480);

      expect(
        runningBalance(
          const [],
          settings,
          asOf: DateTime(2026, 9, 10),
          adjustments: [adjustmentOn(DateTime(2026, 9, 20), 90)],
        ),
        Duration.zero,
      );
    });

    test('a correction before the cutoff is wiped with everything else', () {
      final settings = settingsWith(
        monday: 480,
        balanceResetMode: 'resetToZero',
        balanceResetDay: 1,
        balanceResetMonth: 9,
      );

      expect(
        runningBalance(
          const [],
          settings,
          asOf: DateTime(2026, 9, 30),
          adjustments: [adjustmentOn(DateTime(2026, 8, 31), 300)],
        ),
        Duration.zero,
      );
    });

    test('a correction on the cutoff date belongs to the new period', () {
      // The cutoff takes effect at the start of the date it names -- the
      // same rule a worked day follows -- so a correction dated on it is
      // the first entry of the period that begins there, not the last of
      // the one that ends. Work and corrections must agree on this, or a
      // payout booked the same day as the shift it settles would land on
      // the other side of the line from the hours it cancels.
      final settings = settingsWith(
        monday: 480,
        balanceResetMode: 'resetToZero',
        balanceResetDay: 1,
        balanceResetMonth: 9,
      );

      expect(
        runningBalance(
          const [],
          settings,
          asOf: DateTime(2026, 9, 30),
          adjustments: [adjustmentOn(DateTime(2026, 9, 1), -60)],
        ),
        const Duration(minutes: -60),
      );
    });

    test('corrections inside the range count toward the range balance', () {
      final figures = figuresForRange(
        [
          DayBalance(
            day: DateTime(2026, 9, 7),
            worked: const Duration(hours: 8),
            target: const Duration(hours: 8),
          ),
        ],
        DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 14)),
        adjustments: [
          adjustmentOn(DateTime(2026, 9, 8), -60),
          adjustmentOn(DateTime(2026, 9, 20), 600, id: 'adj-2'),
        ],
      );

      expect(
        figures.balance,
        const Duration(minutes: -60),
        reason: 'the correction outside the range is not this range\'s business',
      );
    });
  });
}
