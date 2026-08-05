import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert creates a pending row with no personioAttendanceId yet', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));

    final row = await db.personioAttendancesDao.getForEntry('entry_1');
    expect(row, isNotNull);
    expect(row!.status, PersonioAttendanceStatus.pending);
    expect(row.personioAttendanceId, isNull);
  });

  test('upsert on an existing id updates it in place', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_1',
        personioAttendanceId: const Value('period-1'),
        status: const Value(PersonioAttendanceStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 12)),
      ),
    );

    final rows = await db.personioAttendancesDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.personioAttendanceId, 'period-1');
    expect(rows.single.status, PersonioAttendanceStatus.synced);
  });

  test('deleteForEntry removes the tracking row', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));
    await db.personioAttendancesDao.deleteForEntry('entry_1');

    expect(await db.personioAttendancesDao.getForEntry('entry_1'), isNull);
  });

  test('latestSyncedAt returns null when nothing has been synced', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));

    expect(await db.personioAttendancesDao.latestSyncedAt(), isNull);
  });

  test('latestSyncedAt returns the newest syncedAt among synced rows only', () async {
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_1',
        status: const Value(PersonioAttendanceStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 10)),
      ),
    );
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_2',
        status: const Value(PersonioAttendanceStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 15)),
      ),
    );
    // An error row with a later syncedAt-looking value must not win -- only
    // `synced` rows count.
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_3',
        status: const Value(PersonioAttendanceStatus.error),
        syncedAt: Value(DateTime.utc(2026, 7, 20)),
      ),
    );

    // .toUtc() before comparing: drift returns DateTime columns in local
    // time by default, and Dart's DateTime.== requires matching isUtc flags
    // even when both values represent the same instant.
    final latest = await db.personioAttendancesDao.latestSyncedAt();
    expect(latest!.toUtc(), DateTime.utc(2026, 7, 15));
  });
}
