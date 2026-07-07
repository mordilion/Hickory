import 'package:drift/drift.dart';

/// Tracks which JSONL files have already been ingested into [Events], so a
/// sync pass can skip files whose mtime/size haven't changed instead of
/// re-parsing everything on every run.
@DataClassName('SyncFileState')
class SyncFileStates extends Table {
  TextColumn get filePath => text()();
  DateTimeColumn get lastMtime => dateTime()();
  IntColumn get lastSize => integer()();

  @override
  Set<Column> get primaryKey => {filePath};
}
