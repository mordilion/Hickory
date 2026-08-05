import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/entity_types.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/sync_paths.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_synced_writes_projects_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  /// Reads the device's current-month log file and returns the last
  /// appended event for [entityId], so tests can assert SyncedWrites
  /// actually logged the mutation, not just wrote the DB row.
  SyncEvent lastLoggedEvent(String entityId) {
    final file = currentMonthLogFile(syncRoot, 'dev_a');
    final result = decodeJsonl(file.readAsStringSync());
    return result.events.lastWhere((e) => e.entityId == entityId);
  }

  test('updateProject persists the given fields, returns the updated row, and logs the event', () async {
    final project = await writes.createProject(name: 'Old Name', colorHex: '#5B8DEF');

    final updated = await writes.updateProject(
      project.id,
      name: const Value('New Name'),
      billable: const Value(false),
    );

    expect(updated.name, 'New Name');
    expect(updated.billable, isFalse);
    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.name, 'New Name');
    expect(row.billable, isFalse);

    final event = lastLoggedEvent(project.id);
    expect(event.entityType, EntityTypes.project);
    expect(event.op, EventOp.update);
    expect(event.payload?['name'], 'New Name');
    expect(event.payload?['billable'], isFalse);
  });

  test('archiveProject marks the project archived and logs the event', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await writes.archiveProject(project.id);

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isTrue);

    final event = lastLoggedEvent(project.id);
    expect(event.op, EventOp.update);
    expect(event.payload?['archived'], isTrue);
  });

  test('unarchiveProject clears the archived flag and logs the event', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await writes.archiveProject(project.id);

    await writes.unarchiveProject(project.id);

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isFalse);

    final event = lastLoggedEvent(project.id);
    expect(event.op, EventOp.update);
    expect(event.payload?['archived'], isFalse);
  });

  test('deleteProject removes the project and logs a delete event when it has no entries', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await writes.deleteProject(project.id);

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, isEmpty);
    final event = lastLoggedEvent(project.id);
    expect(event.entityType, EntityTypes.project);
    expect(event.op, EventOp.delete);
    expect(event.payload, isNull);
  });

  test('deleteProject throws and leaves the project untouched when it has entries', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.timeEntriesDao.startEntry(deviceId: 'dev_a', projectId: project.id);

    await expectLater(writes.deleteProject(project.id), throwsA(isA<ProjectHasTimeEntriesException>()));

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, hasLength(1));
  });
}
