import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';

/// One calendar day's worth of entries for [EntriesList], with a
/// pre-summed [totalDuration] so the widget doesn't recompute it per frame.
class EntryDayGroup {
  const EntryDayGroup({required this.day, required this.entries, required this.totalDuration});

  /// Local midnight for this group's calendar day.
  final DateTime day;
  final List<TimeEntry> entries;
  final Duration totalDuration;
}

/// Groups [entries] by the local calendar day of [TimeEntry.startAt],
/// newest day first; entries within a day keep their input order. Each
/// group's [EntryDayGroup.totalDuration] is the sum of
/// [TimeEntryDuration.workedDuration] across that day's entries.
List<EntryDayGroup> groupEntriesByDay(List<TimeEntry> entries) {
  final entriesByDay = <DateTime, List<TimeEntry>>{};
  for (final entry in entries) {
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    entriesByDay.putIfAbsent(day, () => []).add(entry);
  }
  final sortedDays = entriesByDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in sortedDays)
      EntryDayGroup(
        day: day,
        entries: entriesByDay[day]!,
        totalDuration: entriesByDay[day]!.fold(
          Duration.zero,
          (sum, entry) => sum + entry.workedDuration,
        ),
      ),
  ];
}
