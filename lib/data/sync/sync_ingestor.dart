import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:sync_engine/sync_engine.dart';

import '../drift/database.dart';
import 'entity_types.dart';
import 'sync_paths.dart';

/// Reads every device's JSONL log under a sync root, merges them, and
/// applies the result to the real drift tables. The `events` +
/// `sync_file_states` tables (see [EventsDao]) are a derived cache of the
/// raw log lines, kept so unchanged files can be skipped and so a rebuild
/// never has to re-read files from disk that haven't changed.
class SyncIngestor {
  SyncIngestor({required this.db, required this.syncRoot});

  final AppDatabase db;
  final Directory syncRoot;

  /// Ingests any changed file under `entries/*/*.jsonl` and re-materializes
  /// every entity touched by newly-ingested events into the app's tables.
  Future<void> syncNow() async {
    final dir = entriesDir(syncRoot);
    if (!await dir.exists()) return;

    final touchedEntityIds = <String>{};

    await for (final deviceDir in dir.list()) {
      if (deviceDir is! Directory) continue;
      await for (final entry in deviceDir.list()) {
        if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
        final touched = await _ingestFile(entry);
        touchedEntityIds.addAll(touched);
      }
    }

    if (touchedEntityIds.isNotEmpty) {
      await _materializeAndApply(touchedEntityIds);
    }
  }

  /// Drops the derived cache entirely and rebuilds it from the JSONL files
  /// on disk. Always safe to call: the log is the source of truth, so the
  /// cache can be thrown away and re-derived at any time.
  Future<void> rebuildFromScratch() async {
    await db.eventsDao.clearAll();
    await db.transaction(() async {
      await db.delete(db.timeEntries).go();
      await db.delete(db.projects).go();
    });
    await syncNow();
  }

  Future<Set<String>> _ingestFile(File file) async {
    final stat = await file.stat();
    final known = await db.eventsDao.getFileState(file.path);
    if (known != null &&
        known.lastMtime.isAtSameMomentAs(stat.modified) &&
        known.lastSize == stat.size) {
      return const {};
    }

    final content = await file.readAsString();
    final decoded = decodeJsonl(content);

    if (decoded.events.isNotEmpty) {
      await db.eventsDao.insertEventsIfAbsent(
        decoded.events
            .map(
              (e) => EventsCompanion.insert(
                id: e.id,
                entityType: e.entityType,
                entityId: e.entityId,
                op: e.op.wireName,
                ts: e.ts,
                deviceId: e.deviceId,
                seq: e.seq,
                payloadJson: Value(e.payload == null ? null : jsonEncode(e.payload)),
                sourceFile: file.path,
              ),
            )
            .toList(),
      );
    }

    await db.eventsDao.upsertFileState(
      filePath: file.path,
      lastMtime: stat.modified,
      lastSize: stat.size,
    );

    return decoded.events.map((e) => e.entityId).toSet();
  }

  Future<void> _materializeAndApply(Set<String> entityIds) async {
    final rows = await db.eventsDao.eventsForEntityIds(entityIds);
    final events = rows.map(
      (r) => SyncEvent(
        id: r.id,
        entityType: r.entityType,
        entityId: r.entityId,
        op: EventOp.fromWireName(r.op),
        ts: r.ts,
        deviceId: r.deviceId,
        seq: r.seq,
        payload: r.payloadJson == null
            ? null
            : jsonDecode(r.payloadJson!) as Map<String, dynamic>,
      ),
    );
    final materialized = materialize(events);

    await db.transaction(() async {
      for (final entity in materialized.values) {
        await _applyMaterializedEntity(entity);
      }
    });
  }

  Future<void> _applyMaterializedEntity(MaterializedEntity entity) async {
    switch (entity.entityType) {
      case EntityTypes.project:
        if (entity.isDeleted) {
          await (db.delete(db.projects)..where((p) => p.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.projects)
              .insertOnConflictUpdate(Project.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.timeEntry:
        if (entity.isDeleted) {
          await (db.delete(db.timeEntries)..where((t) => t.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.timeEntries)
              .insertOnConflictUpdate(TimeEntry.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.activitySample:
        // Samples are append-only observations — no delete events are ever
        // written for them, so there's nothing to do for entity.isDeleted.
        if (!entity.isDeleted) {
          await db
              .into(db.activitySamples)
              .insertOnConflictUpdate(ActivitySampleRow.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.appSettings:
        // Singleton settings row — never deleted, so entity.isDeleted never
        // fires for it in practice, but the guard stays for symmetry with
        // every other case here.
        if (!entity.isDeleted) {
          await db
              .into(db.appSettings)
              .insertOnConflictUpdate(AppSettingsRow.fromJson(entity.payload!).toCompanion(true));
        }
      default:
        // Client/Tag aren't wired into the app yet (no DAO to apply them
        // to) — ignored until a later milestone adds them.
        break;
    }
  }
}
