import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/entries/entry_time_range.dart';

void main() {
  group('endFollowingStart', () {
    test('moving the start date moves the end onto the same day', () {
      final end = endFollowingStart(
        previousStartAt: DateTime(2026, 7, 1, 9, 30),
        previousEndAt: DateTime(2026, 7, 1, 10, 30),
        newStartAt: DateTime(2026, 7, 15, 9, 30),
      );

      expect(end, DateTime(2026, 7, 15, 10, 30));
    });

    test('moving the start time keeps the duration', () {
      final end = endFollowingStart(
        previousStartAt: DateTime(2026, 7, 1, 9, 30),
        previousEndAt: DateTime(2026, 7, 1, 10, 0),
        newStartAt: DateTime(2026, 7, 1, 14, 15),
      );

      expect(end, DateTime(2026, 7, 1, 14, 45));
    });

    test('a range spanning midnight keeps spanning it', () {
      final end = endFollowingStart(
        previousStartAt: DateTime(2026, 7, 1, 23, 0),
        previousEndAt: DateTime(2026, 7, 2, 1, 0),
        newStartAt: DateTime(2026, 7, 10, 23, 0),
      );

      expect(end, DateTime(2026, 7, 11, 1, 0));
    });

    test('an already-inverted range is left inverted rather than repaired', () {
      final end = endFollowingStart(
        previousStartAt: DateTime(2026, 7, 1, 10, 0),
        previousEndAt: DateTime(2026, 7, 1, 9, 0),
        newStartAt: DateTime(2026, 7, 5, 10, 0),
      );

      expect(end, DateTime(2026, 7, 5, 9, 0));
    });
  });
}
