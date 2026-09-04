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

  test('createType stores the type and returns the stored row', () async {
    final type = await db.absenceTypesDao.createType(
      deviceId: 'device-1',
      name: 'Vacation',
      paid: true,
      sortOrder: 0,
    );
    expect(type.name, 'Vacation');
    expect(type.paid, isTrue);
    expect(type.sortOrder, 0);
    expect(type.deviceId, 'device-1');
    expect(type.id, isNotEmpty);
  });

  test('watchAllTypes orders by sortOrder, then by name', () async {
    await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Sick leave', paid: true, sortOrder: 1,
    );
    await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Unpaid leave', paid: false, sortOrder: 0,
    );
    await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Public holiday', paid: true, sortOrder: 1,
    );

    final names = (await db.absenceTypesDao.watchAllTypes().first)
        .map((t) => t.name)
        .toList();
    expect(names, ['Unpaid leave', 'Public holiday', 'Sick leave']);
  });

  test('updateType changes only the fields passed in', () async {
    final created = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacaton', paid: true, sortOrder: 2,
    );
    final renamed = await db.absenceTypesDao.updateType(created.id, name: 'Vacation');
    expect(renamed.name, 'Vacation');
    expect(renamed.paid, isTrue, reason: 'untouched fields keep their value');
    expect(renamed.sortOrder, 2);

    final unpaid = await db.absenceTypesDao.updateType(created.id, paid: false);
    expect(unpaid.name, 'Vacation');
    expect(unpaid.paid, isFalse);
  });

  test('updateType bumps updatedAt so the sync log orders correctly', () async {
    final created = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacation', paid: true, sortOrder: 0,
    );
    final updated = await db.absenceTypesDao.updateType(created.id, name: 'Holiday');
    expect(updated.updatedAt.isBefore(created.updatedAt), isFalse);
  });

  test('deleteType removes only that type', () async {
    final kept = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacation', paid: true, sortOrder: 0,
    );
    final removed = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Sick leave', paid: true, sortOrder: 1,
    );
    await db.absenceTypesDao.deleteType(removed.id);

    final remaining = await db.absenceTypesDao.getAllTypes();
    expect(remaining.map((t) => t.id), [kept.id]);
  });
}
