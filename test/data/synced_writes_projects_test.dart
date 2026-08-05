import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

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

  test('updateProject persists the given fields and returns the updated row', () async {
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
  });

  test('archiveProject marks the project archived', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await writes.archiveProject(project.id);

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isTrue);
  });

  test('unarchiveProject clears the archived flag', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await writes.archiveProject(project.id);

    await writes.unarchiveProject(project.id);

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isFalse);
  });
}
