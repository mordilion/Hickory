import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/core/format/duration_format.dart';

void main() {
  final reference = const Duration(hours: 1, minutes: 23, seconds: 45);

  group('formatDuration', () {
    test('defaults to showing seconds when no style is given',
        () => expect(formatDuration(reference), '01:23:45'));
    test('24h_sec shows seconds', () {
      expect(formatDuration(reference, TimeFormatStyle.h24Sec), '01:23:45');
    });
    test('12h_sec shows seconds', () {
      expect(formatDuration(reference, TimeFormatStyle.h12Sec), '01:23:45');
    });
    test('24h hides seconds', () {
      expect(formatDuration(reference, TimeFormatStyle.h24), '01:23');
    });
    test('12h hides seconds', () {
      expect(formatDuration(reference, TimeFormatStyle.h12), '01:23');
    });
  });
}
