import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/quit_behavior.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

// Plain test() (not testWidgets): no widget pumping needed.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory syncRoot;
  late AppDatabase db;
  late SyncedWrites writes;

  setUp(() {
    syncRoot = Directory.systemTemp.createTempSync('hickory_quit_behavior_test_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) {
      syncRoot.deleteSync(recursive: true);
    }
  });

  test('a paused entry is stopped', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);

    await stopPausedEntryOnQuit(db, writes);

    final result = await db.timeEntriesDao.getRunningEntry();
    expect(result, isNull); // no longer "running" (endAt is now set)
  });

  test('a running (not paused) entry is left untouched', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');

    await stopPausedEntryOnQuit(db, writes);

    final result = await db.timeEntriesDao.getRunningEntry();
    expect(result?.id, entry.id);
    expect(result?.endAt, isNull);
  });

  test('no open entry at all is a no-op', () async {
    await stopPausedEntryOnQuit(db, writes); // must not throw

    expect(await db.timeEntriesDao.getRunningEntry(), isNull);
  });
}
