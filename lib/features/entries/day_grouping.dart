import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';
import 'break_rule_calculations.dart';

/// One calendar day's worth of entries for [EntriesList], with pre-summed
/// [totalDuration] and [breakDuration] so the widget doesn't recompute them
/// per frame.
class EntryDayGroup {
  const EntryDayGroup({
    required this.day,
    required this.entries,
    required this.totalDuration,
    required this.breakDuration,
    required this.requiredBreak,
  });

  /// Local midnight for this group's calendar day.
  final DateTime day;
  final List<TimeEntry> entries;
  final Duration totalDuration;
  final Duration breakDuration;

  /// Break the active rule tiers demand for [totalDuration], or null when no
  /// tier applies. Computed here rather than at the render site because the
  /// week/month/year roll-up counts offending days too.
  final Duration? requiredBreak;

  /// True when a tier applies and [breakDuration] falls short of it.
  bool get isBreakInsufficient {
    final required = requiredBreak;
    return required != null && breakDuration < required;
  }
}

/// Groups [entries] by the local calendar day of [TimeEntry.startAt],
/// newest day first; entries within a day keep their input order. Each
/// group's [EntryDayGroup.totalDuration] is the sum of
/// [TimeEntryDuration.workedDuration] across that day's entries, and
/// [EntryDayGroup.breakDuration] is [dayBreakDuration] applied to that
/// day's entries -- [includePausedTimeInBreak] forwards to that function's
/// `includePausedTime` (see its doc comment). [tiers] drives each group's
/// [EntryDayGroup.requiredBreak]; the default empty list means "no break rule
/// configured", which leaves that field null.
///
/// [extraDays] names calendar days that must appear even though no entry
/// falls on them; each yields a group with an empty [EntryDayGroup.entries]
/// and zero totals. A day that also carries entries is unaffected. This is
/// what lets a caller show a day whose only record is an absence -- without
/// it such a day would have no node at all, and the rows hanging off it
/// would be unreachable.
List<EntryDayGroup> groupEntriesByDay(
  List<TimeEntry> entries, {
  List<BreakRuleTier> tiers = const [],
  bool includePausedTimeInBreak = false,
  Iterable<DateTime> extraDays = const [],
}) {
  final entriesByDay = <DateTime, List<TimeEntry>>{};
  for (final day in extraDays) {
    entriesByDay.putIfAbsent(DateTime(day.year, day.month, day.day), () => []);
  }
  for (final entry in entries) {
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    entriesByDay.putIfAbsent(day, () => []).add(entry);
  }
  final sortedDays = entriesByDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in sortedDays)
      _dayGroup(
        day,
        entriesByDay[day]!,
        tiers: tiers,
        includePausedTimeInBreak: includePausedTimeInBreak,
      ),
  ];
}

EntryDayGroup _dayGroup(
  DateTime day,
  List<TimeEntry> dayEntries, {
  required List<BreakRuleTier> tiers,
  required bool includePausedTimeInBreak,
}) {
  final total = dayEntries.fold(
    Duration.zero,
    (sum, entry) => sum + entry.workedDuration,
  );
  return EntryDayGroup(
    day: day,
    entries: dayEntries,
    totalDuration: total,
    breakDuration: dayBreakDuration(
      dayEntries,
      includePausedTime: includePausedTimeInBreak,
    ),
    requiredBreak: requiredBreakForWorked(total, tiers),
  );
}
