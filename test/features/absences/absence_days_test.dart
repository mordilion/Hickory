import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
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

  group('absenceSpanDays', () {
    test('a span inside one day is that day, with the clock window it was given', () {
      final days = absenceSpanDays(
        DateTime(2026, 9, 7, 9),
        DateTime(2026, 9, 7, 11),
        workWeek,
      );

      expect(days, hasLength(1));
      expect(days.single.date, monday);
      expect(days.single.portion, absencePortionRange);
      expect(days.single.startAt, DateTime(2026, 9, 7, 9));
      expect(days.single.endAt, DateTime(2026, 9, 7, 11));
    });

    test('a span across days is clipped at its ends and whole in between', () {
      // Read exactly as the same line in the manual form: away from
      // Monday 09:00 until Wednesday 11:00, without interruption.
      final days = absenceSpanDays(
        DateTime(2026, 9, 7, 9),
        DateTime(2026, 9, 9, 11),
        workWeek,
      );

      expect(days.map((day) => day.date), [
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 8),
        DateTime(2026, 9, 9),
      ]);
      expect(days.first.startAt, DateTime(2026, 9, 7, 9));
      expect(
        days.first.endAt,
        DateTime(2026, 9, 8),
        reason: 'the first day runs to midnight, not to the end time',
      );
      expect(
        days[1].portion,
        absencePortionFullDay,
        reason: 'a day in the middle is away from start to finish',
      );
      expect(days[1].startAt, isNull);
      expect(days.last.startAt, DateTime(2026, 9, 9));
      expect(days.last.endAt, DateTime(2026, 9, 9, 11));
    });

    test('free days inside a span are skipped and do not take the clipping with them', () {
      final days = absenceSpanDays(
        DateTime(2026, 9, 4, 14),
        DateTime(2026, 9, 8, 10),
        workWeek,
      );

      // Friday the 4th, then the weekend is skipped, then Monday and Tuesday.
      expect(days.map((day) => day.date), [
        DateTime(2026, 9, 4),
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 8),
      ]);
      expect(days.first.startAt, DateTime(2026, 9, 4, 14));
      expect(
        days[1].portion,
        absencePortionFullDay,
        reason: 'Monday is neither end of the span, so it is a whole day',
      );
      expect(days.last.endAt, DateTime(2026, 9, 8, 10));
    });

    test('a last day the span ends at midnight of is left out', () {
      final days = absenceSpanDays(
        DateTime(2026, 9, 7, 9),
        DateTime(2026, 9, 9),
        workWeek,
      );

      expect(
        days.map((day) => day.date),
        [DateTime(2026, 9, 7), DateTime(2026, 9, 8)],
        reason: 'an absence ending at midnight covers nothing of that day',
      );
    });

    test('a span that ends before it starts yields nothing', () {
      expect(
        absenceSpanDays(DateTime(2026, 9, 7, 11), DateTime(2026, 9, 7, 9), workWeek),
        isEmpty,
      );
    });
  });
}
