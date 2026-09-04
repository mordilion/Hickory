// Shared text-field formatting for the work-time settings editors: hours
// typed by the user round-trip through whole minutes on disk.

/// Parses an hours field ("7,7" or "7.7") into whole minutes; null when the
/// text is not a number.
int? hoursTextToMinutes(String text) {
  final hours = double.tryParse(text.trim().replaceAll(',', '.'));
  if (hours == null) return null;
  return (hours * 60).round();
}

String minutesToHoursText(int minutes) {
  if (minutes == 0) return '';
  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toStringAsFixed(2).replaceAll('.', ',');
}
