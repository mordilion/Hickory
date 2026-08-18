import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/iso_week.dart';

void main() {
  group('mondayOf', () {
    test('returns the same day for a Monday', () {
      expect(mondayOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
    });

    test('reaches back across a month boundary for a Sunday', () {
      // 2026-08-02 is a Sunday; its ISO week starts 2026-07-27.
      expect(mondayOf(DateTime(2026, 8, 2)), DateTime(2026, 7, 27));
    });

    test('drops the time component', () {
      expect(
        mondayOf(DateTime(2026, 8, 18, 23, 45, 30)),
        DateTime(2026, 8, 17),
      );
    });
  });

  group('isoWeekNumber', () {
    test('numbers a mid-year day', () {
      expect(isoWeekNumber(DateTime(2026, 8, 18)), 34);
    });

    test('puts 2027-01-01 in week 53 of the previous ISO year', () {
      expect(isoWeekNumber(DateTime(2027, 1, 1)), 53);
    });

    test('puts 2024-12-30 in week 1 of the next ISO year', () {
      expect(isoWeekNumber(DateTime(2024, 12, 30)), 1);
    });

    test('numbers the first week of a year starting on a Thursday', () {
      // 2026-01-01 is a Thursday, so its week is week 1 of 2026.
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1);
    });
  });

  group('isoDayKey', () {
    test('zero-pads month and day', () {
      expect(isoDayKey(DateTime(2026, 8, 4)), '2026-08-04');
    });
  });
}
