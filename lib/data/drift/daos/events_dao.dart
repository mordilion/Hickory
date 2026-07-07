import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/events_table.dart';
import '../tables/sync_file_states_table.dart';

part 'events_dao.g.dart';

@DriftAccessor(tables: [Events, SyncFileStates])
class EventsDao extends DatabaseAccessor<AppDatabase> with _$EventsDaoMixin {
  EventsDao(super.db);

  /// Event ids are content-addressed by the writer (never mutated once
  /// written), so re-ingesting an already-known event is a safe no-op.
  Future<void> insertEventsIfAbsent(List<Insertable<SyncEventRow>> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(events, rows, mode: InsertMode.insertOrIgnore));
  }

  Future<List<SyncEventRow>> eventsForEntityIds(Iterable<String> entityIds) {
    final ids = entityIds.toSet();
    if (ids.isEmpty) return Future.value(const []);
    return (select(events)..where((e) => e.entityId.isIn(ids))).get();
  }

  Future<List<SyncEventRow>> allEvents() => select(events).get();

  Future<void> clearAll() async {
    await delete(events).go();
    await delete(syncFileStates).go();
  }

  Future<SyncFileState?> getFileState(String filePath) {
    return (select(syncFileStates)..where((s) => s.filePath.equals(filePath)))
        .getSingleOrNull();
  }

  Future<void> upsertFileState({
    required String filePath,
    required DateTime lastMtime,
    required int lastSize,
  }) {
    return into(syncFileStates).insertOnConflictUpdate(
      SyncFileStatesCompanion.insert(
        filePath: filePath,
        lastMtime: lastMtime,
        lastSize: lastSize,
      ),
    );
  }
}
