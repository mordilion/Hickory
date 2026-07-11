import 'package:intl/intl.dart';

import '../../data/drift/database.dart' show AppSettingsRow;

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

/// Date patterns are all-numeric except [DateFormatStyle.long], whose month
/// abbreviation follows [localeName] (the active app language). The default
/// stays 'de_DE' so callers that don't care keep today's output. For the
/// long style, use a skeleton so ordering/punctuation localize too.
/// Requires `initializeDateFormatting(localeName)` to have run first (see
/// `main.dart`); tests must call it in `setUpAll`.
String formatDate(
  DateTime dt, [
  DateFormatStyle style = defaultDateFormatStyle,
  String localeName = 'de_DE',
]) {
  final local = dt.toLocal();
  if (style == DateFormatStyle.long) {
    return DateFormat.yMMMd(localeName).format(local);
  }
  final pattern = switch (style) {
    DateFormatStyle.de => 'dd.MM.yyyy',
    DateFormatStyle.iso => 'yyyy-MM-dd',
    DateFormatStyle.us => 'MM/dd/yyyy',
    DateFormatStyle.long => throw StateError('handled above'),
  };
  return DateFormat(pattern, localeName).format(local);
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

extension AppSettingsStyles on AppSettingsRow? {
  DateFormatStyle get dateStyle =>
      this == null ? defaultDateFormatStyle : DateFormatStyle.fromWireName(this!.dateFormat);

  TimeFormatStyle get timeStyle =>
      this == null ? defaultTimeFormatStyle : TimeFormatStyle.fromWireName(this!.timeFormat);
}
