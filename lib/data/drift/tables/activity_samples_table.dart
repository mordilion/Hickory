import 'package:drift/drift.dart';

/// Raw desktop activity observations (which app/window was focused, when).
/// Named `ActivitySampleRow` (not `ActivitySample`) to avoid clashing with
/// `package:activity_tracker`'s own `ActivitySample` — the plugin's live
/// stream type — since both are imported together wherever samples are
/// recorded.
///
/// Per the architecture plan these are synced like any other entity
/// (decision 6: raw activity data is shared across devices, not kept
/// local-only), so every row is also an append-only sync event — samples
/// are only ever created, never updated or deleted.
@DataClassName('ActivitySampleRow')
class ActivitySamples extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  TextColumn get appName => text()();
  TextColumn get windowTitle => text().nullable()();
  DateTimeColumn get observedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
