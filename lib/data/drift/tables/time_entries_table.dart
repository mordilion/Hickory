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
  BoolColumn get billableOverride => boolean().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
