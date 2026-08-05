import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/personio/personio_client.dart';
import 'package:hickory/features/personio/personio_sync_service.dart';
import 'package:mocktail/mocktail.dart';

class MockPersonioClient extends Mock implements PersonioClient {}

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;
  late MockPersonioClient client;
  late PersonioSyncService service;

  final from = DateTime.utc(2026, 7, 1);
  final to = DateTime.utc(2026, 7, 31);

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026, 7, 7));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_personio_sync_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
    client = MockPersonioClient();
    service = PersonioSyncService(db: db, client: client, writes: writes);
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('creates an attendance for a finished entry in range with no tracking row yet', () async {
    when(
      () => client.createAttendance(
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async => 'period-1');

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      description: 'Design review',
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.created, 1);
    final attendance = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(attendance!.personioAttendanceId, 'period-1');
    verify(
      () => client.createAttendance(start: entry.startAt, end: entry.endAt!, comment: 'Design review'),
    ).called(1);
  });

  test('entries outside the selected range are skipped', () async {
    await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 8, 7, 9),
      endAt: DateTime.utc(2026, 8, 7, 10),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.total, 0);
    verifyNever(
      () => client.createAttendance(
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    );
  });

  test('running (unfinished) entries are skipped', () async {
    await writes.startEntry(deviceId: 'dev_a');

    final result = await service.pushRange(from: from, to: to);

    expect(result.total, 0);
  });

  test('updates the attendance when the entry changed since the last sync', () async {
    when(
      () => client.updateAttendance(
        periodId: any(named: 'periodId'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async {});

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
        syncedAt: DateTime.utc(2020),
      ),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.updated, 1);
    verify(
      () => client.updateAttendance(
        periodId: 'period-1',
        start: entry.startAt,
        end: entry.endAt!,
        comment: any(named: 'comment'),
      ),
    ).called(1);
  });

  test('an up-to-date attendance is skipped', () async {
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
        syncedAt: DateTime.utc(2027),
      ),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.total, 0);
  });

  test(
    'deletes the remote attendance and the tracking row for a pendingDelete entry, regardless of range',
    () async {
      when(() => client.deleteAttendance(periodId: 'period-1')).thenAnswer((_) async {});

      final entry = await writes.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 1, 1, 9),
        endAt: DateTime.utc(2026, 1, 1, 10),
      );
      await writes.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: 'period-1',
          status: PersonioAttendanceStatus.pendingDelete,
          lastError: null,
          syncedAt: null,
        ),
      );

      // entry.startAt (January) is outside [from, to] (July) -- the delete
      // must still be reconciled, proving pendingDelete isn't date-filtered.
      final result = await service.pushRange(from: from, to: to);

      expect(result.deleted, 1);
      expect(await db.personioAttendancesDao.getForEntry(entry.id), isNull);
    },
  );

  test('a failed create is recorded with status error and counted as failed', () async {
    when(
      () => client.createAttendance(
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    ).thenThrow(PersonioApiException('boom'));

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.failed, 1);
    final attendance = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(attendance!.status, PersonioAttendanceStatus.error);
    expect(attendance.lastError, contains('boom'));
  });

  test('a failed pendingDelete stays pendingDelete and is retried on the next push', () async {
    when(
      () => client.deleteAttendance(periodId: 'period-1'),
    ).thenThrow(PersonioApiException('unreachable'));

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: 'period-1',
        status: PersonioAttendanceStatus.pendingDelete,
        lastError: null,
        syncedAt: null,
      ),
    );

    final firstResult = await service.pushRange(from: from, to: to);

    expect(firstResult.failed, 1);
    final afterFailure = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(afterFailure!.status, PersonioAttendanceStatus.pendingDelete);

    when(() => client.deleteAttendance(periodId: 'period-1')).thenAnswer((_) async {});

    final secondResult = await service.pushRange(from: from, to: to);

    expect(secondResult.deleted, 1);
    expect(await db.personioAttendancesDao.getForEntry(entry.id), isNull);
  });
}
