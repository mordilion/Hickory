import 'date_format.dart' show TimeFormatStyle;

/// Formats [d] as `H:MM` or `H:MM:SS`. Seconds are shown only when [style]
/// is one of the "...Sec" variants, mirroring the same show-seconds choice
/// [TimeFormatStyle] already makes for point-in-time display via
/// `formatTime` -- so a duration next to a clock time (or a settings-driven
/// clock time elsewhere on screen) shows the same precision. Defaults to
/// showing seconds so call sites without a settings-driven style (e.g. the
/// live running-timer numeral) keep their existing always-on-seconds look.
String formatDuration(Duration d, [TimeFormatStyle style = TimeFormatStyle.h24Sec]) {
  final showSeconds = style == TimeFormatStyle.h24Sec || style == TimeFormatStyle.h12Sec;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final h = hours.toString().padLeft(2, '0');
  final m = minutes.toString().padLeft(2, '0');
  if (!showSeconds) return '$h:$m';
  final seconds = d.inSeconds.remainder(60);
  final s = seconds.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
