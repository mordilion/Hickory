/// Splits a weekly target across the chosen work days.
///
/// Returns a value for all seven weekdays (`DateTime.monday` …
/// `DateTime.sunday`); non-work days get `0`. The remainder of an uneven
/// division is handed to the earliest work days, so the seven values sum to
/// exactly [weeklyMinutes] — a settings screen that showed the sum back to
/// the user would otherwise drift by a few minutes each time it round-trips.
/// A negative [weeklyMinutes] is treated as zero rather than rejected: the
/// only caller is a text field, and an empty week is a meaningful state.
Map<int, int> distributeWeeklyMinutes(int weeklyMinutes, Set<int> workDays) {
  final total = weeklyMinutes < 0 ? 0 : weeklyMinutes;
  final days = workDays.toList()..sort();
  final result = {for (var weekday = 1; weekday <= 7; weekday++) weekday: 0};
  if (days.isEmpty) return result;

  final base = total ~/ days.length;
  var remainder = total % days.length;
  for (final weekday in days) {
    result[weekday] = base + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder--;
  }
  return result;
}
