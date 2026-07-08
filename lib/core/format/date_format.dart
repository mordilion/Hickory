import 'package:intl/intl.dart';

enum DateFormatStyle {
  de,
  iso,
  us,
  long;

  String get wireName => name;

  static DateFormatStyle fromWireName(String value) => switch (value) {
        'de' => DateFormatStyle.de,
        'iso' => DateFormatStyle.iso,
        'us' => DateFormatStyle.us,
        'long' => DateFormatStyle.long,
        _ => throw FormatException('Unknown date format style: $value'),
      };
}

enum TimeFormatStyle {
  h24,
  h24Sec,
  h12,
  h12Sec;

  String get wireName => switch (this) {
        TimeFormatStyle.h24 => '24h',
        TimeFormatStyle.h24Sec => '24h_sec',
        TimeFormatStyle.h12 => '12h',
        TimeFormatStyle.h12Sec => '12h_sec',
      };

  static TimeFormatStyle fromWireName(String value) => switch (value) {
        '24h' => TimeFormatStyle.h24,
        '24h_sec' => TimeFormatStyle.h24Sec,
        '12h' => TimeFormatStyle.h12,
        '12h_sec' => TimeFormatStyle.h12Sec,
        _ => throw FormatException('Unknown time format style: $value'),
      };
}

const defaultDateFormatStyle = DateFormatStyle.iso;
const defaultTimeFormatStyle = TimeFormatStyle.h24;

/// German locale for date patterns (month abbreviations in [DateFormatStyle.long]
/// read as German, e.g. "Dez." not "Dec.") — matches the rest of the app's
/// German-language UI. Requires `initializeDateFormatting('de_DE')` to have
/// run first (see `main.dart`); tests must call it in `setUpAll`.
String formatDate(DateTime dt, [DateFormatStyle style = defaultDateFormatStyle]) {
  final local = dt.toLocal();
  final pattern = switch (style) {
    DateFormatStyle.de => 'dd.MM.yyyy',
    DateFormatStyle.iso => 'yyyy-MM-dd',
    DateFormatStyle.us => 'MM/dd/yyyy',
    DateFormatStyle.long => 'd. MMM y',
  };
  return DateFormat(pattern, 'de_DE').format(local);
}

/// English locale for time patterns deliberately: the 12h styles' AM/PM
/// marker follows the design spec's examples ("2:30 PM"), not a German
/// equivalent. Requires `initializeDateFormatting('en_US')` to have run
/// first (see `main.dart`); tests must call it in `setUpAll`.
String formatTime(DateTime dt, [TimeFormatStyle style = defaultTimeFormatStyle]) {
  final local = dt.toLocal();
  final pattern = switch (style) {
    TimeFormatStyle.h24 => 'HH:mm',
    TimeFormatStyle.h24Sec => 'HH:mm:ss',
    TimeFormatStyle.h12 => 'h:mm a',
    TimeFormatStyle.h12Sec => 'h:mm:ss a',
  };
  return DateFormat(pattern, 'en_US').format(local);
}
