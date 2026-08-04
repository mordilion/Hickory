import '../../data/drift/database.dart';

/// Sum of the gaps between chronologically consecutive entries in
/// [dayEntries] (all entries must share the same calendar day and have a
/// non-null [TimeEntry.endAt] -- guaranteed by [EntriesList]'s "finished
/// entries only" filter and day_grouping.dart's grouping). Entries are
/// sorted by [TimeEntry.startAt] first since callers make no ordering
/// guarantee. Overlapping or back-to-back entries contribute zero for that
/// gap. Mirrors
/// docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md's
/// "gaps between entries within the same calendar day" definition -- the
/// overnight gap into the next day is never part of this.
///
/// [includePausedTime], off by default, additionally adds each entry's
/// explicit Timer-pause time ([TimeEntry.totalPausedSeconds]) -- an opt-in
/// (see [AppSettingsRow.countPausedTimeAsBreak]) for users who track a
/// lunch break via the pause button rather than stopping and restarting
/// the timer, where the default gaps-only definition would otherwise
/// undercount (even down to zero, for a single-entry day) their actual
/// break time. A day with 0 or 1 entries and paused time excluded has zero
/// break time.
Duration dayBreakDuration(List<TimeEntry> dayEntries, {bool includePausedTime = false}) {
  var total = includePausedTime
      ? dayEntries.fold(
          Duration.zero,
          (sum, entry) => sum + Duration(seconds: entry.totalPausedSeconds),
        )
      : Duration.zero;
  if (dayEntries.length < 2) return total;
  final sorted = [...dayEntries]..sort((a, b) => a.startAt.compareTo(b.startAt));
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
