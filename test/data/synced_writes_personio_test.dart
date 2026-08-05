import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_personio_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('deleteEntry marks a pushed attendance pendingDelete instead of removing it', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: 'period-1',
        status: PersonioAttendanceStatus.synced,
        lastError: null,
        syncedAt: DateTime.utc(2026, 7, 7, 10),
      ),
    );

    await writes.deleteEntry(entry.id);

    final remainingEntry =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    expect(remainingEntry, isNull);

    final attendance = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(attendance, isNotNull);
    expect(attendance!.status, PersonioAttendanceStatus.pendingDelete);
  });

  test('deleteEntry removes the tracking row outright if it was never pushed', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: null,
        status: PersonioAttendanceStatus.error,
        lastError: 'network error',
        syncedAt: null,
      ),
    );

    await writes.deleteEntry(entry.id);

    expect(await db.personioAttendancesDao.getForEntry(entry.id), isNull);
  });

  test('deleteEntry with no Personio tracking row at all still deletes the entry', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );

    await writes.deleteEntry(entry.id);

    final remainingEntry =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    expect(remainingEntry, isNull);
  });
}
