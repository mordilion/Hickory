import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/data/sync/sync_ingestor.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

// Plain test() (not testWidgets): no widget pumping needed, so this runs as
// a normal fast Dart VM test rather than spinning up flutter_tester.
void main() {
  // These tests deliberately open two independent in-memory AppDatabase
  // instances (simulating two separate devices) — that's expected here,
  // not the accidental-singleton-misuse case drift's warning guards against.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory syncRoot;

  setUp(() {
    syncRoot = Directory.systemTemp.createTempSync('hickory_sync_test_');
  });

  tearDown(() async {
    if (syncRoot.existsSync()) {
      syncRoot.deleteSync(recursive: true);
    }
  });

  test(
    'a second database rebuilt purely from the on-disk log matches the '
    'writer database, including an edit and a delete',
    () async {
      // Device A: writes a project and two entries directly to its own log.
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final project = await writerWrites.createProject(name: 'Hickory', colorHex: '#5B8DEF');

      final keptEntry = await writerWrites.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 7, 7, 9),
        endAt: DateTime.utc(2026, 7, 7, 10),
        projectId: project.id,
        description: 'first draft',
      );
      await writerWrites.updateEntry(
        keptEntry.id,
        description: const Value('edited description'),
      );

      final deletedEntry = await writerWrites.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 7, 7, 11),
        endAt: DateTime.utc(2026, 7, 7, 12),
        description: 'will be deleted',
      );
      await writerWrites.deleteEntry(deletedEntry.id);

      // Device B (or a fresh install of the same device): starts with an
      // empty database and the same sync root on disk, nothing else shared.
      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final projects = await readerDb.select(readerDb.projects).get();
      expect(projects, hasLength(1));
      expect(projects.single.name, 'Hickory');

      final entries = await readerDb.select(readerDb.timeEntries).get();
      expect(entries, hasLength(1), reason: 'the deleted entry must not resurface');
      expect(entries.single.id, keptEntry.id);
      expect(entries.single.description, 'edited description');
      expect(entries.single.projectId, project.id);
    },
  );

  test(
    'rebuildFromScratch reproduces the same state after wiping the cache',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final writes = SyncedWrites(
        db: db,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );
      final ingestor = SyncIngestor(db: db, syncRoot: syncRoot);

      final entry = await writes.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 7, 7, 9),
        endAt: DateTime.utc(2026, 7, 7, 10),
        description: 'only entry',
      );

      await ingestor.rebuildFromScratch();

      final entries = await db.select(db.timeEntries).get();
      expect(entries, hasLength(1));
      expect(entries.single.id, entry.id);
      expect(entries.single.description, 'only entry');
    },
  );

  test(
    'app settings sync as a singleton row across devices',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      await writerWrites.updateAppSettings(dateFormat: 'de', timeFormat: '12h');

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final rows = await readerDb.select(readerDb.appSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.dateFormat, 'de');
      expect(rows.single.timeFormat, '12h');
    },
  );

  test(
    'a jira worklog tracking row syncs to a second device, including a later update',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final entry = await writerWrites.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 7, 7, 9),
        endAt: DateTime.utc(2026, 7, 7, 10),
        jiraTicketKey: 'PROJ-1',
      );
      await writerWrites.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: 'PROJ-1',
          jiraWorklogId: '10001',
          status: JiraWorklogStatus.synced,
          lastError: null,
          syncedAt: DateTime.utc(2026, 7, 7, 10),
        ),
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final worklogs = await readerDb.jiraWorklogsDao.getAll();
      expect(worklogs, hasLength(1));
      expect(worklogs.single.jiraWorklogId, '10001');
      expect(worklogs.single.status, JiraWorklogStatus.synced);

      // Device B doesn't know the entry was already pushed unless the
      // tracking row itself synced — this is the correctness property the
      // design doc calls out as the reason JiraWorklogs must be synced.
      await writerWrites.deleteJiraWorklogState(entry.id);
      await ingestor.syncNow();

      expect(await readerDb.jiraWorklogsDao.getAll(), isEmpty);
    },
  );
}
