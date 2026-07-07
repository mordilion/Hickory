import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/time_entries_table.dart';

part 'time_entries_dao.g.dart';

@DriftAccessor(tables: [TimeEntries])
class TimeEntriesDao extends DatabaseAccessor<AppDatabase> with _$TimeEntriesDaoMixin {
  TimeEntriesDao(super.db);

  static const _uuid = Uuid();

  Stream<List<TimeEntry>> watchAllEntries() {
    return (select(timeEntries)..orderBy([(t) => OrderingTerm.desc(t.startAt)])).watch();
  }

  /// There should only ever be zero or one running entry (endAt == null) at
  /// a time; that invariant is enforced by app logic (stop-before-start),
  /// not a DB constraint.
  Stream<TimeEntry?> watchRunningEntry() {
    return (select(timeEntries)..where((t) => t.endAt.isNull())).watchSingleOrNull();
  }

  Future<TimeEntry> startEntry({
    required String deviceId,
    String? projectId,
    String? description,
  }) async {
    final now = DateTime.now().toUtc();
    final entry = TimeEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: Value(projectId),
      description: Value(description),
      startAt: now,
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(timeEntries).insert(entry);
    return (select(timeEntries)..where((t) => t.id.equals(entry.id.value))).getSingle();
  }

  Future<void> stopEntry(String id) {
    final now = DateTime.now().toUtc();
    return (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(endAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<TimeEntry> createManualEntry({
    required String deviceId,
    required DateTime startAt,
    required DateTime endAt,
    String? projectId,
    String? description,
  }) async {
    final now = DateTime.now().toUtc();
    final entry = TimeEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: Value(projectId),
      description: Value(description),
      startAt: startAt.toUtc(),
      endAt: Value(endAt.toUtc()),
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(timeEntries).insert(entry);
    return (select(timeEntries)..where((t) => t.id.equals(entry.id.value))).getSingle();
  }

  Future<void> updateEntry(
    String id, {
    Value<String?> projectId = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<DateTime> startAt = const Value.absent(),
    Value<DateTime?> endAt = const Value.absent(),
  }) {
    return (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(
        projectId: projectId,
        description: description,
        startAt: startAt,
        endAt: endAt,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> deleteEntry(String id) {
    return (delete(timeEntries)..where((t) => t.id.equals(id))).go();
  }
}
