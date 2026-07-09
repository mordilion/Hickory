import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    await initializeDateFormatting('en_US');
  });

  final reference = DateTime(2026, 12, 24, 14, 30, 5);

  group('formatDate', () {
    test('de', () => expect(formatDate(reference, DateFormatStyle.de), '24.12.2026'));
    test('iso', () => expect(formatDate(reference, DateFormatStyle.iso), '2026-12-24'));
    test('us', () => expect(formatDate(reference, DateFormatStyle.us), '12/24/2026'));
    test('long', () => expect(formatDate(reference, DateFormatStyle.long), '24. Dez. 2026'));
    test('defaults to iso when no style is given',
        () => expect(formatDate(reference), '2026-12-24'));
  });

  group('formatTime', () {
    test('24h', () => expect(formatTime(reference, TimeFormatStyle.h24), '14:30'));
    test('24h_sec', () => expect(formatTime(reference, TimeFormatStyle.h24Sec), '14:30:05'));
    test('12h', () => expect(formatTime(reference, TimeFormatStyle.h12), '2:30 PM'));
    test('12h_sec', () => expect(formatTime(reference, TimeFormatStyle.h12Sec), '2:30:05 PM'));
    test('defaults to 24h when no style is given',
        () => expect(formatTime(reference), '14:30'));
  });

  group('wireName round-trip', () {
    test('DateFormatStyle', () {
      for (final style in DateFormatStyle.values) {
        expect(DateFormatStyle.fromWireName(style.wireName), style);
      }
    });
    test('TimeFormatStyle', () {
      for (final style in TimeFormatStyle.values) {
        expect(TimeFormatStyle.fromWireName(style.wireName), style);
      }
    });
  });

  group('AppSettingsStyles', () {
    test('falls back to defaults when settings row is null', () {
      const AppSettingsRow? settings = null;
      expect(settings.dateStyle, defaultDateFormatStyle);
      expect(settings.timeStyle, defaultTimeFormatStyle);
    });

    test('resolves via fromWireName when settings row is present', () {
      final settings = AppSettingsRow(
        id: 'default',
        dateFormat: 'de',
        timeFormat: '12h_sec',
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(settings.dateStyle, DateFormatStyle.de);
      expect(settings.timeStyle, TimeFormatStyle.h12Sec);
    });
  });
}
