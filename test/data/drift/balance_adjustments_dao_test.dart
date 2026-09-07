import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('createAdjustment stores a signed delta with its date and note', () async {
    final adjustment = await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'device-1',
      date: DateTime(2026, 9, 7),
      deltaMinutes: -1440,
      note: '3 days paid out',
    );

    expect(adjustment.deltaMinutes, -1440);
    expect(adjustment.note, '3 days paid out');
    expect(adjustment.date, DateTime(2026, 9, 7));
  });

  test('createAdjustment leaves the note unset when there is none', () async {
    final adjustment = await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'device-1',
      date: DateTime(2026, 9, 7),
      deltaMinutes: 60,
    );

    expect(adjustment.note, isNull);
  });

  test('watchAllAdjustments returns rows ascending by date', () async {
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'd', date: DateTime(2026, 9, 9), deltaMinutes: 60,
    );
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'd', date: DateTime(2026, 9, 7), deltaMinutes: 30,
    );

    final dates = (await db.balanceAdjustmentsDao.watchAllAdjustments().first)
        .map((adjustment) => adjustment.date);
    expect(dates, [DateTime(2026, 9, 7), DateTime(2026, 9, 9)]);
  });

  test('deleteAdjustment removes only that row', () async {
    final kept = await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'd', date: DateTime(2026, 9, 7), deltaMinutes: 30,
    );
    final removed = await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'd', date: DateTime(2026, 9, 8), deltaMinutes: 60,
    );

    await db.balanceAdjustmentsDao.deleteAdjustment(removed.id);

    final remaining = await db.balanceAdjustmentsDao.watchAllAdjustments().first;
    expect(remaining.map((adjustment) => adjustment.id), [kept.id]);
  });
}
