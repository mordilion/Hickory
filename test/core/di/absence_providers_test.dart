import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/absence_providers.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Waits for [provider] to emit.
  ///
  /// Riverpod 3's `StreamProvider.future` never completes in a plain test --
  /// verified in this repository against a provider that only wraps
  /// `Stream.value`, so it is not a drift interaction. Subscribing and
  /// polling the synchronous value is the shape that works.
  Future<T> emittedValue<T>(StreamProvider<T> provider) async {
    container.listen(provider, (previous, next) {});
    for (var attempt = 0; attempt < 100; attempt++) {
      final value = container.read(provider).value;
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('$provider did not emit within a second');
  }

  test('absenceTypesProvider emits the stored types', () async {
    await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacation', paid: true, sortOrder: 0,
    );
    final types = await emittedValue(absenceTypesProvider);
    expect(types.single.name, 'Vacation');
  });

  test('absenceTypesByIdProvider keys the types by id', () async {
    final created = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacation', paid: true, sortOrder: 0,
    );
    await emittedValue(absenceTypesProvider);
    final byId = container.read(absenceTypesByIdProvider);
    expect(byId[created.id]?.name, 'Vacation');
  });

  test('absenceTypesByIdProvider is empty while the types are loading', () {
    expect(container.read(absenceTypesByIdProvider), isEmpty);
  });

  test('absencesProvider emits the stored absences', () async {
    final type = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Vacation', paid: true, sortOrder: 0,
    );
    await db.absencesDao.createAbsence(
      deviceId: 'd',
      date: DateTime(2026, 9, 7),
      absenceTypeId: type.id,
      portion: absencePortionFullDay,
    );
    final absences = await emittedValue(absencesProvider);
    expect(absences.single.date, DateTime(2026, 9, 7));
  });
}
