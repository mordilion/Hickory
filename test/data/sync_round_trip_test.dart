import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/data/drift/tables/app_settings_table.dart' show appSettingsRowId;
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
import 'package:hickory/data/sync/entity_types.dart';
import 'package:hickory/data/sync/sync_ingestor.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:sync_engine/sync_engine.dart' show EventOp;

import '../support/app_settings_fixture.dart';

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
    'ingesting an app_settings event written before quickAddDurationsMinutes '
    'existed (an older peer) backfills the default instead of throwing',
    () async {
      // Simulates a peer device still on schema v4: its event payload
      // predates the quickAddDurationsMinutes column entirely, rather than
      // merely omitting it, since v4 never had it to serialize. Built via a
      // real row's .toJson() (matching the exact wire format the app
      // actually produces, including its DateTime encoding) with the new
      // column removed, rather than hand-writing the payload's shape.
      final v4Payload = appSettingsFixture(dateFormat: 'de', timeFormat: '12h').toJson()
        ..remove('quickAddDurationsMinutes');

      final peerLogWriter = SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_old');
      await peerLogWriter.appendEvent(
        entityType: EntityTypes.appSettings,
        entityId: appSettingsRowId,
        op: EventOp.update,
        payload: v4Payload,
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);

      await ingestor.syncNow();

      final rows = await readerDb.select(readerDb.appSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.dateFormat, 'de');
      expect(rows.single.quickAddDurationsMinutes, '15,30,45,60');
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

  test(
    'a personio attendance tracking row syncs to a second device, including a later update',
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
      );
      await writerWrites.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: 'period-1',
          status: PersonioAttendanceStatus.synced,
          lastError: null,
          syncedAt: DateTime.utc(2026, 7, 7, 10),
        ),
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final attendances = await readerDb.personioAttendancesDao.getAll();
      expect(attendances, hasLength(1));
      expect(attendances.single.personioAttendanceId, 'period-1');
      expect(attendances.single.status, PersonioAttendanceStatus.synced);

      // Same correctness property as the Jira worklog case above: a second
      // device only knows an entry was already pushed if the tracking row
      // itself synced.
      await writerWrites.deletePersonioAttendanceState(entry.id);
      await ingestor.syncNow();

      expect(await readerDb.personioAttendancesDao.getAll(), isEmpty);
    },
  );

  test(
    'a break rule tier syncs to a second device, including deletion',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final tier = await writerWrites.createBreakRuleTier(
        deviceId: 'dev_a',
        afterMinutes: 360,
        requiredBreakMinutes: 30,
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final tiers = await readerDb.breakRuleTiersDao.getAllTiers();
      expect(tiers, hasLength(1));
      expect(tiers.single.afterMinutes, 360);

      await writerWrites.deleteBreakRuleTier(tier.id);
      await ingestor.syncNow();

      expect(await readerDb.breakRuleTiersDao.getAllTiers(), isEmpty);
    },
  );

  test(
    'replaceBreakRuleTiers swaps the whole tier set and syncs the result',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      await writerWrites.createBreakRuleTier(
        deviceId: 'dev_a',
        afterMinutes: 120,
        requiredBreakMinutes: 10,
      );

      await writerWrites.replaceBreakRuleTiers(
        deviceId: 'dev_a',
        tiers: const [
          BreakRuleTierValues(afterMinutes: 360, requiredBreakMinutes: 30),
          BreakRuleTierValues(afterMinutes: 540, requiredBreakMinutes: 45),
        ],
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final tiers = await readerDb.breakRuleTiersDao.getAllTiers();
      expect(tiers, hasLength(2));
      expect(tiers.map((t) => t.afterMinutes), [360, 540]);
    },
  );

  test(
    'a client syncs to a second device, including archive and delete',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final client = await writerWrites.createClient(name: 'Acme Inc');
      await writerWrites.archiveClient(client.id);

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final clients = await readerDb.select(readerDb.clients).get();
      expect(clients, hasLength(1));
      expect(clients.single.name, 'Acme Inc');
      expect(clients.single.archived, isTrue);

      await writerWrites.deleteClient(client.id);
      await ingestor.syncNow();

      expect(await readerDb.select(readerDb.clients).get(), isEmpty);
    },
  );

  test(
    'rebuildFromScratch clears absences that no event backs',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final writes = SyncedWrites(
        db: db,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );
      final ingestor = SyncIngestor(db: db, syncRoot: syncRoot);

      final type = await writes.createAbsenceType(
        deviceId: 'dev_a',
        name: 'Vacation',
        paid: true,
        sortOrder: 0,
      );
      final absence = await writes.createAbsence(
        deviceId: 'dev_a',
        date: DateTime(2026, 9, 7),
        absenceTypeId: type.id,
        portion: absencePortionFullDay,
      );
      // Straight into the cache, no event written: the shape a half-applied
      // merge leaves behind, and the only thing a rebuild can clean up.
      await db.absencesDao.createAbsence(
        deviceId: 'dev_a',
        date: DateTime(2026, 9, 8),
        absenceTypeId: type.id,
        portion: absencePortionFullDay,
      );

      await ingestor.rebuildFromScratch();

      expect(
        (await db.select(db.absences).get()).map((row) => row.id),
        [absence.id],
      );
      expect(
        (await db.select(db.absenceTypes).get()).map((row) => row.id),
        [type.id],
      );
    },
  );

  test(
    'rebuildFromScratch clears and re-derives clients too',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final writes = SyncedWrites(
        db: db,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );
      final ingestor = SyncIngestor(db: db, syncRoot: syncRoot);

      final client = await writes.createClient(name: 'Acme Inc');

      await ingestor.rebuildFromScratch();

      final clients = await db.select(db.clients).get();
      expect(clients, hasLength(1));
      expect(clients.single.id, client.id);
    },
  );

  test('per-weekday targets and the reset rule reach a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    await writes.updateAppSettings(
      targetMinutesMonday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: const Value(1),
      balanceResetMonth: const Value(1),
    );

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    final row = (await readerDb.select(readerDb.appSettings).get()).single;
    expect(row.targetMinutesMonday, 480);
    expect(row.balanceResetMode, 'resetToZero');
    expect(row.balanceResetDay, 1);
    expect(row.balanceResetMonth, 1);
  });

  test('clearing a nullable settings field clears it on the second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    await writes.updateAppSettings(
      balanceResetMode: 'carryOver',
      balanceResetDay: const Value(1),
      balanceResetMonth: const Value(1),
      carryOverMaxMinutes: const Value(300),
      carryOverMinMinutes: const Value(-120),
    );

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
    await ingestor.syncNow();
    expect(
      (await readerDb.select(readerDb.appSettings).get()).single.carryOverMaxMinutes,
      300,
      reason: 'the peer has to hold the bound before clearing it can be observed',
    );

    // The upper bound is dropped on the writing device. Null here is a
    // value the user chose, not "this field was not part of the change" --
    // the payload is the whole row.
    await writes.updateAppSettings(carryOverMaxMinutes: const Value(null));
    await ingestor.syncNow();

    final row = (await readerDb.select(readerDb.appSettings).get()).single;
    expect(
      row.carryOverMaxMinutes,
      isNull,
      reason: 'a cleared bound must not leave the peer computing a different balance',
    );
    expect(row.carryOverMinMinutes, -120, reason: 'the untouched bound must survive');
  });

  test(
    'ingesting an app_settings event from a peer that predates the target '
    'columns backfills their defaults instead of throwing',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final full = await writerDb.appSettingsDao.updateSettings(dateFormat: 'de');
      final v8Payload = full.toJson()
        ..remove('targetMinutesMonday')
        ..remove('targetMinutesTuesday')
        ..remove('targetMinutesWednesday')
        ..remove('targetMinutesThursday')
        ..remove('targetMinutesFriday')
        ..remove('targetMinutesSaturday')
        ..remove('targetMinutesSunday')
        ..remove('targetInputMode')
        ..remove('balanceResetMode')
        ..remove('absenceTrackingEnabled');
      await SyncLogWriter(syncRoot: syncRoot, deviceId: 'old-peer').appendEvent(
        entityType: EntityTypes.appSettings,
        entityId: appSettingsRowId,
        op: EventOp.update,
        payload: v8Payload,
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

      final row = (await readerDb.select(readerDb.appSettings).get()).single;
      expect(row.dateFormat, 'de');
      expect(row.targetMinutesMonday, 0);
      expect(row.targetInputMode, 'perWeekday');
      expect(row.balanceResetMode, 'none');
      expect(row.absenceTrackingEnabled, isFalse);
    },
  );

  test('an absence type reaches a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    await writes.createAbsenceType(
      deviceId: 'writer', name: 'Vacation', paid: true, sortOrder: 0,
    );

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    final types = await readerDb.absenceTypesDao.getAllTypes();
    expect(types, hasLength(1));
    expect(types.single.name, 'Vacation');
    expect(types.single.paid, isTrue);
  });

  test('renaming an absence type reaches a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    final created = await writes.createAbsenceType(
      deviceId: 'writer', name: 'Vacaton', paid: true, sortOrder: 0,
    );
    await writes.updateAbsenceType(created.id, name: 'Vacation');

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    final types = await readerDb.absenceTypesDao.getAllTypes();
    expect(types.single.name, 'Vacation');
  });

  test('deleting an absence type reaches a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    final created = await writes.createAbsenceType(
      deviceId: 'writer', name: 'Vacation', paid: true, sortOrder: 0,
    );
    await writes.deleteAbsenceType(created.id);

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    expect(await readerDb.absenceTypesDao.getAllTypes(), isEmpty);
  });

  test('an absence, including its range and note, reaches a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    final type = await writes.createAbsenceType(
      deviceId: 'writer', name: 'Vacation', paid: true, sortOrder: 0,
    );
    final from = DateTime(2026, 9, 7, 9).toUtc();
    await writes.createAbsence(
      deviceId: 'writer',
      date: DateTime(2026, 9, 7),
      absenceTypeId: type.id,
      portion: absencePortionRange,
      startAt: from,
      endAt: from.add(const Duration(hours: 2)),
      note: 'Doctor',
    );

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    final rows = await readerDb.absencesDao.watchAllAbsences().first;
    expect(rows, hasLength(1));
    expect(rows.single.date, DateTime(2026, 9, 7));
    expect(rows.single.portion, absencePortionRange);
    // Drift hands a stored DateTime back as local regardless of how it was
    // written, so comparing instants (not DateTime.== , which also checks
    // the isUtc flag) is required here even though the code is correct.
    expect(rows.single.startAt?.toUtc(), from);
    expect(rows.single.note, 'Doctor');
  });

  test('deleting an absence reaches a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    final type = await writes.createAbsenceType(
      deviceId: 'writer', name: 'Vacation', paid: true, sortOrder: 0,
    );
    final absence = await writes.createAbsence(
      deviceId: 'writer',
      date: DateTime(2026, 9, 7),
      absenceTypeId: type.id,
      portion: absencePortionFullDay,
    );
    await writes.deleteAbsence(absence.id);

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    expect(await readerDb.absencesDao.watchAllAbsences().first, isEmpty);
  });

  test('editing an absence reaches a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    final type = await writes.createAbsenceType(
      deviceId: 'writer', name: 'Vacation', paid: true, sortOrder: 0,
    );
    final created = await writes.createAbsence(
      deviceId: 'writer',
      date: DateTime(2026, 9, 7),
      absenceTypeId: type.id,
      portion: absencePortionRange,
      startAt: DateTime(2026, 9, 7, 9).toUtc(),
      endAt: DateTime(2026, 9, 7, 11).toUtc(),
      note: 'Docter',
    );

    await writes.updateAbsence(
      created.id,
      portion: absencePortionFullDay,
      startAt: const Value(null),
      endAt: const Value(null),
      note: const Value('Doctor'),
    );

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    final absence = (await readerDb.select(readerDb.absences).get()).single;
    expect(absence.portion, absencePortionFullDay);
    expect(absence.note, 'Doctor');
    expect(
      absence.startAt,
      isNull,
      reason: 'a cleared time range must reach the peer as cleared, not stay behind',
    );
  });
}
