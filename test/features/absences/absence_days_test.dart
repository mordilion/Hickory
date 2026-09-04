import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/absences/absence_days.dart';

import '../../support/app_settings_fixture.dart';

void main() {
  // 2026-09-07 is a Monday, 2026-09-13 the Sunday after it.
  final monday = DateTime(2026, 9, 7);
  final friday = DateTime(2026, 9, 11);
  final sunday = DateTime(2026, 9, 13);

  final workWeek = appSettingsFixture(
    targetMinutesMonday: 480,
    targetMinutesTuesday: 480,
    targetMinutesWednesday: 480,
    targetMinutesThursday: 480,
    targetMinutesFriday: 480,
  );

  test('a single work day yields that day', () {
    expect(absenceDaysBetween(monday, monday, workWeek), [monday]);
  });

  test('a Monday-to-Friday span yields five days', () {
    expect(absenceDaysBetween(monday, friday, workWeek), hasLength(5));
  });

  test('the weekend is skipped', () {
    final days = absenceDaysBetween(monday, sunday, workWeek);
    expect(days, hasLength(5));
    expect(days.last, friday);
  });

  test('a span starting on a free day still yields the work days after it', () {
    final saturday = DateTime(2026, 9, 5);
    final days = absenceDaysBetween(saturday, monday, workWeek);
    expect(days, [monday]);
  });

  test('a reversed span yields nothing', () {
    expect(absenceDaysBetween(friday, monday, workWeek), isEmpty);
  });

  test('with no target configured at all there are no work days', () {
    expect(absenceDaysBetween(monday, friday, appSettingsFixture()), isEmpty);
  });

  test('the time of day is dropped from both ends', () {
    final days = absenceDaysBetween(
      DateTime(2026, 9, 7, 23, 30),
      DateTime(2026, 9, 8, 0, 15),
      workWeek,
    );
    expect(days, [DateTime(2026, 9, 7), DateTime(2026, 9, 8)]);
  });

  test('a span across a month boundary is enumerated correctly', () {
    // 2026-09-30 is a Wednesday, 2026-10-01 a Thursday.
    final days = absenceDaysBetween(
      DateTime(2026, 9, 30),
      DateTime(2026, 10, 1),
      workWeek,
    );
    expect(days, [DateTime(2026, 9, 30), DateTime(2026, 10, 1)]);
  });
}
