import 'package:drift/drift.dart';

import 'projects_table.dart';

/// Values used in [TimeEntries.source]: 'manual' (timer/manual entry) or
/// 'auto' (desktop activity-tracking, added in a later milestone).
@DataClassName('TimeEntry')
class TimeEntries extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startAt => dateTime()();
  // Null endAt means this is the currently running entry.
  DateTimeColumn get endAt => dateTime().nullable()();
  // Set while the entry is paused (endAt still null); null while running or
  // stopped. Cleared back to null on resume.
  DateTimeColumn get pausedAt => dateTime().nullable()();
  // Sum of every pause span for this entry, across as many pause/resume
  // cycles as the user performs. Subtracted from (endAt ?? pausedAt ?? now)
  // - startAt to get the actual worked duration — see workedDuration in
  // lib/data/drift/time_entry_extensions.dart.
  IntColumn get totalPausedSeconds => integer().withDefault(const Constant(0))();
  BoolColumn get billableOverride => boolean().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get deviceId => text()();
  // Optional Jira issue key this entry books time against (e.g. "PROJ-123"),
  // independent of projectId. See
  // docs/superpowers/specs/2026-07-12-jira-ticket-booking-design.md.
  TextColumn get jiraTicketKey => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
