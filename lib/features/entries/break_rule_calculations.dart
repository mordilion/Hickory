import '../../data/drift/database.dart';

/// Sum of the gaps between chronologically consecutive entries in
/// [dayEntries] (all entries must share the same calendar day and have a
/// non-null [TimeEntry.endAt] -- guaranteed by [EntriesList]'s "finished
/// entries only" filter and day_grouping.dart's grouping). Entries are
/// sorted by [TimeEntry.startAt] first since callers make no ordering
/// guarantee. Overlapping or back-to-back entries contribute zero for that
/// gap. A day with 0 or 1 entries has zero break time. Mirrors
/// docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md's
/// "gaps between entries within the same calendar day" definition -- the
/// overnight gap into the next day is never part of this, and explicit
/// Timer-pause time ([TimeEntry.totalPausedSeconds]) is unrelated.
Duration dayBreakDuration(List<TimeEntry> dayEntries) {
  if (dayEntries.length < 2) return Duration.zero;
  final sorted = [...dayEntries]..sort((a, b) => a.startAt.compareTo(b.startAt));
  var total = Duration.zero;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].startAt.difference(sorted[i - 1].endAt!);
    if (gap > Duration.zero) total += gap;
  }
  return total;
}

/// The break time required once [workedDuration] is reached, per [tiers]:
/// the tier with the highest [BreakRuleTier.afterMinutes] that is `<=`
/// [workedDuration]'s minutes. Returns null if [tiers] is empty or every
/// tier's threshold exceeds [workedDuration] (no requirement yet).
Duration? requiredBreakForWorked(Duration workedDuration, List<BreakRuleTier> tiers) {
  final workedMinutes = workedDuration.inMinutes;
  BreakRuleTier? best;
  for (final tier in tiers) {
    if (tier.afterMinutes > workedMinutes) continue;
    if (best == null || tier.afterMinutes > best.afterMinutes) best = tier;
  }
  return best == null ? null : Duration(minutes: best.requiredBreakMinutes);
}
