import 'package:drift/drift.dart' show Value;
import 'package:sync_engine/sync_engine.dart';

import '../drift/database.dart';
import 'entity_types.dart';
import 'sync_log_writer.dart';

/// Thin write-through wrapper around the DAOs: every mutation is applied to
/// the local drift cache immediately (via the DAO, for instant UI feedback)
/// and also appended to the device's own event log, per the architecture
/// plan's "apply locally AND log" rule. DAOs stay sync-agnostic and
/// independently testable; this is the only place the two are combined.
class SyncedWrites {
  SyncedWrites({required this.db, required this.logWriter});

  final AppDatabase db;
  final SyncLogWriter logWriter;

  Future<Project> createProject({
    required String name,
    required String colorHex,
    String? clientId,
    bool billable = true,
    int? hourlyRateCents,
    String? currency,
  }) async {
    final project = await db.projectsDao.createProject(
      name: name,
      colorHex: colorHex,
      clientId: clientId,
      billable: billable,
      hourlyRateCents: hourlyRateCents,
      currency: currency,
    );
    await logWriter.appendEvent(
      entityType: EntityTypes.project,
      entityId: project.id,
      op: EventOp.create,
      payload: project.toJson(),
    );
    return project;
  }

  Future<TimeEntry> startEntry({
    required String deviceId,
    String? projectId,
    String? description,
  }) async {
    final entry = await db.timeEntriesDao.startEntry(
      deviceId: deviceId,
      projectId: projectId,
      description: description,
    );
    await _logCurrentState(entry.id, EventOp.create);
    return entry;
  }

  Future<void> stopEntry(String id) async {
    await db.timeEntriesDao.stopEntry(id);
    await _logCurrentState(id, EventOp.update);
  }

  Future<TimeEntry> createManualEntry({
    required String deviceId,
    required DateTime startAt,
    required DateTime endAt,
    String? projectId,
    String? description,
  }) async {
    final entry = await db.timeEntriesDao.createManualEntry(
      deviceId: deviceId,
      startAt: startAt,
      endAt: endAt,
      projectId: projectId,
      description: description,
    );
    await _logCurrentState(entry.id, EventOp.create);
    return entry;
  }

  Future<void> updateEntry(
    String id, {
    Value<String?> projectId = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<DateTime> startAt = const Value.absent(),
    Value<DateTime?> endAt = const Value.absent(),
  }) async {
    await db.timeEntriesDao.updateEntry(
      id,
      projectId: projectId,
      description: description,
      startAt: startAt,
      endAt: endAt,
    );
    await _logCurrentState(id, EventOp.update);
  }

  Future<void> deleteEntry(String id) async {
    await db.timeEntriesDao.deleteEntry(id);
    await logWriter.appendEvent(
      entityType: EntityTypes.timeEntry,
      entityId: id,
      op: EventOp.delete,
      payload: null,
    );
  }

  Future<void> _logCurrentState(String timeEntryId, EventOp op) async {
    final current =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(timeEntryId))).getSingle();
    await logWriter.appendEvent(
      entityType: EntityTypes.timeEntry,
      entityId: timeEntryId,
      op: op,
      payload: current.toJson(),
    );
  }
}
