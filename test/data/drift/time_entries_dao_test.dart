import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';

// Plain test() (not testWidgets): no widget pumping needed.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('pauseEntry sets pausedAt on a running entry', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);

    final paused =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(paused.pausedAt, isNotNull);
    expect(paused.endAt, isNull);
  });

  test('resumeEntry clears pausedAt and accumulates totalPausedSeconds', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await db.timeEntriesDao.resumeEntry(entry.id);

    final resumed =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(resumed.pausedAt, isNull);
    expect(resumed.totalPausedSeconds, greaterThanOrEqualTo(1));
  });

  test('multiple pause/resume cycles accumulate totalPausedSeconds monotonically', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');

    await db.timeEntriesDao.pauseEntry(entry.id);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await db.timeEntriesDao.resumeEntry(entry.id);
    final afterFirstCycle =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();

    await db.timeEntriesDao.pauseEntry(entry.id);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await db.timeEntriesDao.resumeEntry(entry.id);
    final afterSecondCycle =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();

    expect(
      afterSecondCycle.totalPausedSeconds,
      greaterThan(afterFirstCycle.totalPausedSeconds),
    );
    expect(afterSecondCycle.pausedAt, isNull);
  });

  test('stopEntry while paused finalizes endAt to the pausedAt timestamp, not now', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);
    final pausedRow =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    final pausedAt = pausedRow.pausedAt!;

    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.timeEntriesDao.stopEntry(entry.id);

    final stopped =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(stopped.endAt, pausedAt);
    expect(stopped.pausedAt, isNull);
  });

  test('stopEntry on a running (not paused) entry sets endAt to now, as before', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.stopEntry(entry.id);

    final stopped =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(stopped.endAt, isNotNull);
    expect(stopped.pausedAt, isNull);
  });
}
