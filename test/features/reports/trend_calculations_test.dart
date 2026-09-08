import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/balance_calculations.dart';
import 'package:hickory/features/reports/trend_calculations.dart';

DayBalance _day(DateTime day, {int workedMinutes = 0, int targetMinutes = 480}) => DayBalance(
      day: day,
      worked: Duration(minutes: workedMinutes),
      target: Duration(minutes: targetMinutes),
    );

void main() {
  group('granularityFor', () {
    test('a month is drawn per day', () {
      expect(
        granularityFor(
          DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 10, 1)),
        ),
        TrendGranularity.day,
      );
    });

    test('a year is drawn per week', () {
      expect(
        granularityFor(
          DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2027, 1, 1)),
        ),
        TrendGranularity.week,
      );
    });

    test('the switch happens where the caller says it does', () {
      final range = DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 11));
      expect(granularityFor(range, dayLimit: 5), TrendGranularity.week);
      expect(granularityFor(range, dayLimit: 20), TrendGranularity.day);
    });
  });

  group('trendBars', () {
    // 2026-09-07 is a Monday.
    final monday = DateTime(2026, 9, 7);

    test('one bar per day, in order', () {
      final bars = trendBars(
        [_day(monday, workedMinutes: 540), _day(monday.add(const Duration(days: 2)), workedMinutes: 300)],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 3))),
        TrendGranularity.day,
      );

      expect(bars, hasLength(3));
      expect(bars.first.worked, const Duration(minutes: 540));
      expect(bars.last.worked, const Duration(minutes: 300));
    });

    test('a day with nothing tracked is still a bar, so a gap shows as a gap', () {
      final bars = trendBars(
        [_day(monday, workedMinutes: 480)],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 2))),
        TrendGranularity.day,
        through: monday.add(const Duration(days: 1)),
      );

      expect(bars, hasLength(2));
      expect(bars.last.worked, Duration.zero);
      expect(
        bars.last.target,
        Duration.zero,
        reason: 'a day the balance never enumerated carries no target either',
      );
    });

    test('weekly bars sum the days of their ISO week', () {
      final bars = trendBars(
        [
          for (var offset = 0; offset < 5; offset++)
            _day(monday.add(Duration(days: offset)), workedMinutes: 480),
        ],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 7))),
        TrendGranularity.week,
      );

      expect(bars, hasLength(1));
      expect(bars.single.worked, const Duration(hours: 40));
      expect(bars.single.target, const Duration(hours: 40));
      expect(bars.single.start, monday, reason: 'a week bar starts on its Monday');
    });

    test('a week is split from the next one', () {
      final bars = trendBars(
        [
          _day(monday, workedMinutes: 480),
          _day(monday.add(const Duration(days: 7)), workedMinutes: 240),
        ],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 14))),
        TrendGranularity.week,
      );

      expect(bars, hasLength(2));
      expect(bars.last.worked, const Duration(minutes: 240));
    });

    test('days outside the range are left out', () {
      final bars = trendBars(
        [_day(monday.subtract(const Duration(days: 1)), workedMinutes: 480), _day(monday, workedMinutes: 60)],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 1))),
        TrendGranularity.day,
      );

      expect(bars, hasLength(1));
      expect(bars.single.worked, const Duration(minutes: 60));
    });

    test('an all-time range does not enumerate a century of empty bars', () {
      // rangeForPreset(all) spans 2000..2100. Bars are only drawn where
      // there is something to draw plus what the range and the data share.
      final bars = trendBars(
        [_day(monday, workedMinutes: 480)],
        DateTimeRange(start: DateTime(2000), end: DateTime(2100)),
        TrendGranularity.week,
      );

      expect(bars, hasLength(1));
    });

    test('the rest of a running month is not drawn as bars that have not happened', () {
      final bars = trendBars(
        [_day(monday, workedMinutes: 480)],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 20))),
        TrendGranularity.day,
        through: monday.add(const Duration(days: 2)),
      );

      expect(bars, hasLength(3), reason: 'up to today, not to the end of the range');
    });

    test('a reporting date beyond the range does not extend it', () {
      final bars = trendBars(
        [_day(monday, workedMinutes: 480)],
        DateTimeRange(start: monday, end: monday.add(const Duration(days: 2))),
        TrendGranularity.day,
        through: monday.add(const Duration(days: 30)),
      );

      expect(bars, hasLength(2));
    });
  });
}
