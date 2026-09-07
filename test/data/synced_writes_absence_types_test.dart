import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_absence_type_writes_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('deleting a type that absences still reference is refused', () async {
    final type = await writes.createAbsenceType(
      deviceId: 'dev_a', name: 'Vacation', paid: true, sortOrder: 0,
    );
    await writes.createAbsence(
      deviceId: 'dev_a',
      date: DateTime(2026, 9, 7),
      absenceTypeId: type.id,
      portion: absencePortionFullDay,
    );

    // The guard belongs here rather than in the settings screen: the
    // tables carry no foreign key, so nothing below this line would stop
    // the delete from leaving absences pointing at a type that is gone --
    // exactly as deleteProject and deleteClient already refuse.
    await expectLater(
      writes.deleteAbsenceType(type.id),
      throwsA(isA<AbsenceTypeInUseException>()),
    );
    expect(await db.absenceTypesDao.getAllTypes(), hasLength(1));
  });

  test('the refusal carries how many days use the type', () async {
    final type = await writes.createAbsenceType(
      deviceId: 'dev_a', name: 'Vacation', paid: true, sortOrder: 0,
    );
    for (final day in [DateTime(2026, 9, 7), DateTime(2026, 9, 8)]) {
      await writes.createAbsence(
        deviceId: 'dev_a',
        date: day,
        absenceTypeId: type.id,
        portion: absencePortionFullDay,
      );
    }

    expect(
      writes.deleteAbsenceType(type.id),
      throwsA(
        isA<AbsenceTypeInUseException>().having((e) => e.count, 'count', 2),
      ),
    );
  });

  test('a type nothing references is deleted', () async {
    final type = await writes.createAbsenceType(
      deviceId: 'dev_a', name: 'Vacation', paid: true, sortOrder: 0,
    );

    await writes.deleteAbsenceType(type.id);

    expect(await db.absenceTypesDao.getAllTypes(), isEmpty);
  });
}
