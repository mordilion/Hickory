import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  final now = DateTime(2026, 8, 7, 14, 30); // a Friday

  group('rangeForPreset', () {
    test('today returns just the current calendar day', () {
      final range = rangeForPreset(ReportRangePreset.today, now: now);
      expect(range.start, DateTime(2026, 8, 7));
      expect(range.end, DateTime(2026, 8, 8));
    });

    test('yesterday returns the previous calendar day', () {
      final range = rangeForPreset(ReportRangePreset.yesterday, now: now);
      expect(range.start, DateTime(2026, 8, 6));
      expect(range.end, DateTime(2026, 8, 7));
    });
  });
}
