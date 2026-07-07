import 'package:drift/drift.dart';

/// Raw ingested rows from every device's JSONL event log, kept around so
/// [materialize] can be re-run (a "rebuild") without re-reading every file
/// from disk. This table plus [SyncFileStates] is a derived, disposable
/// cache — the JSONL files on disk remain the source of truth.
@DataClassName('SyncEventRow')
@TableIndex(name: 'idx_events_entity_id', columns: {#entityId})
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get deviceId => text()();
  IntColumn get seq => integer()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get sourceFile => text()();

  @override
  Set<Column> get primaryKey => {id};
}
