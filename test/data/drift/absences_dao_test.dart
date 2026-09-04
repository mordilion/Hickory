import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';

void main() {
  late AppDatabase db;
  late String typeId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final type = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacation', paid: true, sortOrder: 0,
    );
    typeId = type.id;
  });

  tearDown(() async {
    await db.close();
  });

  test('createAbsence stores a full-day absence', () async {
    final absence = await db.absencesDao.createAbsence(
      deviceId: 'device-1',
      date: DateTime(2026, 9, 7),
      absenceTypeId: typeId,
      portion: absencePortionFullDay,
    );
    expect(absence.date, DateTime(2026, 9, 7));
    expect(absence.portion, absencePortionFullDay);
    expect(absence.absenceTypeId, typeId);
    expect(absence.startAt, isNull);
    expect(absence.endAt, isNull);
    expect(absence.note, isNull);
  });

  test('createAbsence stores a time range and a note', () async {
    final from = DateTime(2026, 9, 7, 9).toUtc();
    final to = DateTime(2026, 9, 7, 11).toUtc();
    final absence = await db.absencesDao.createAbsence(
      deviceId: 'device-1',
      date: DateTime(2026, 9, 7),
      absenceTypeId: typeId,
      portion: absencePortionRange,
      startAt: from,
      endAt: to,
      note: 'Doctor',
    );
    expect(absence.startAt?.toUtc(), from);
    expect(absence.endAt?.toUtc(), to);
    expect(absence.note, 'Doctor');
  });

  test('watchAllAbsences returns rows ascending by date', () async {
    await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 9),
      absenceTypeId: typeId, portion: absencePortionFullDay,
    );
    await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 7),
      absenceTypeId: typeId, portion: absencePortionFullDay,
    );

    final dates = (await db.absencesDao.watchAllAbsences().first)
        .map((a) => a.date)
        .toList();
    expect(dates, [DateTime(2026, 9, 7), DateTime(2026, 9, 9)]);
  });

  test('countByType counts only that type', () async {
    final other = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Sick leave', paid: true, sortOrder: 1,
    );
    await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 7),
      absenceTypeId: typeId, portion: absencePortionFullDay,
    );
    await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 8),
      absenceTypeId: typeId, portion: absencePortionFullDay,
    );
    await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 9),
      absenceTypeId: other.id, portion: absencePortionFullDay,
    );

    expect(await db.absencesDao.countByType(typeId), 2);
    expect(await db.absencesDao.countByType(other.id), 1);
  });

  test('countByType returns zero for a type nothing references', () async {
    expect(await db.absencesDao.countByType('never-used'), 0);
  });

  test('deleteAbsence removes only that row', () async {
    final kept = await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 7),
      absenceTypeId: typeId, portion: absencePortionFullDay,
    );
    final removed = await db.absencesDao.createAbsence(
      deviceId: 'd', date: DateTime(2026, 9, 8),
      absenceTypeId: typeId, portion: absencePortionFullDay,
    );
    await db.absencesDao.deleteAbsence(removed.id);

    final remaining = await db.absencesDao.watchAllAbsences().first;
    expect(remaining.map((a) => a.id), [kept.id]);
  });
}
