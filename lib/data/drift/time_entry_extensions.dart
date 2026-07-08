import 'database.dart';

/// Duration actually worked on this entry, with all paused time excluded.
/// While running this counts up live (re-evaluate the getter on each timer
/// tick to see it change); while paused it's frozen at the moment
/// [TimeEntry.pausedAt] was set; while stopped it's fixed.
extension TimeEntryDuration on TimeEntry {
  Duration get workedDuration {
    final effectiveEnd = endAt ?? pausedAt ?? DateTime.now().toUtc();
    return effectiveEnd.difference(startAt) - Duration(seconds: totalPausedSeconds);
  }
}
