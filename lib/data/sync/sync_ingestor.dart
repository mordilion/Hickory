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
      await db.delete(db.clients).go();
      await db.delete(db.jiraWorklogs).go();
      await db.delete(db.breakRuleTiers).go();
      await db.delete(db.personioAttendances).go();
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
      case EntityTypes.client:
        if (entity.isDeleted) {
          await (db.delete(db.clients)..where((c) => c.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.clients)
              .insertOnConflictUpdate(Client.fromJson(entity.payload!).toCompanion(true));
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
          // A payload written by a peer on an older app version may predate
          // quickAddDurationsMinutes (v5), countPausedTimeAsBreak (v7), or
          // the target/balance columns (v9): fromJson's generated
          // deserializer requires every non-nullable field to be present
          // and throws otherwise, which would abort this entire sync
          // transaction. Backfill each such field's table default before
          // decoding, so ingesting an older peer's settings event never
          // breaks sync. (Every other non-nullable column added to an
          // already-synced entity — e.g. TimeEntries.totalPausedSeconds in
          // v2 — has the same exposure and isn't guarded; not addressed
          // here, out of scope for this fix.) Note what the backfill
          // cannot save: if such an older peer's settings event *wins*
          // last-write-wins, these defaults are what gets applied, so the
          // seven configured targets are reset to 0 — whole-row
          // last-write-wins across a mixed-version fleet, the same
          // exposure countPausedTimeAsBreak has had since v7.
          final payload = {
            'quickAddDurationsMinutes': '15,30,45,60',
            'countPausedTimeAsBreak': false,
            'targetMinutesMonday': 0,
            'targetMinutesTuesday': 0,
            'targetMinutesWednesday': 0,
            'targetMinutesThursday': 0,
            'targetMinutesFriday': 0,
            'targetMinutesSaturday': 0,
            'targetMinutesSunday': 0,
            'targetInputMode': 'perWeekday',
            'balanceResetMode': 'none',
            'absenceTrackingEnabled': false,
            ...entity.payload!,
          };
          // toCompanion(false), unlike every other case here: with `true`
          // a null nullable field becomes Value.absent(), and
          // insertOnConflictUpdate leaves an absent column untouched, so a
          // payload that clears carryOverMaxMinutes would leave the peer's
          // stale bound in place and the two devices would compute
          // different balances from the same entries. This payload is a
          // whole row under last-write-wins, so an explicit null is
          // exactly what should be written; the backfill above guarantees
          // every non-nullable field is present.
          await db
              .into(db.appSettings)
              .insertOnConflictUpdate(AppSettingsRow.fromJson(payload).toCompanion(false));
        }
      case EntityTypes.jiraWorklog:
        if (entity.isDeleted) {
          await (db.delete(db.jiraWorklogs)..where((w) => w.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.jiraWorklogs)
              .insertOnConflictUpdate(JiraWorklogRow.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.breakRuleTier:
        if (entity.isDeleted) {
          await (db.delete(db.breakRuleTiers)..where((t) => t.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.breakRuleTiers)
              .insertOnConflictUpdate(BreakRuleTier.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.absenceType:
        if (entity.isDeleted) {
          await (db.delete(db.absenceTypes)..where((t) => t.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.absenceTypes)
              .insertOnConflictUpdate(AbsenceType.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.absence:
        if (entity.isDeleted) {
          await (db.delete(db.absences)..where((a) => a.id.equals(entity.entityId))).go();
        } else {
          // toCompanion(false): startAt, endAt and note are nullable and
          // null is meaningful here -- a row that switched from a range to
          // a full day has no start time, and with `true` that null would
          // become Value.absent() and leave the peer's stale time in place.
          await db
              .into(db.absences)
              .insertOnConflictUpdate(Absence.fromJson(entity.payload!).toCompanion(false));
        }
      case EntityTypes.personioAttendance:
        if (entity.isDeleted) {
          await (db.delete(db.personioAttendances)..where((a) => a.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.personioAttendances)
              .insertOnConflictUpdate(
                PersonioAttendanceRow.fromJson(entity.payload!).toCompanion(true),
              );
        }
      default:
        // Tag isn't wired into the app yet (no DAO to apply it to) --
        // ignored until a later milestone adds it.
        break;
    }
  }
}
