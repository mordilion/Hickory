import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/balance_adjustment_providers.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/data/drift/database.dart';

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

  test('balanceAdjustmentsProvider emits the stored corrections', () async {
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'd', date: DateTime(2026, 9, 7), deltaMinutes: -120, note: 'paid out',
    );

    // container.read(...future) never completes in a plain test under this
    // Riverpod version, even over a Stream.value; listening and polling is
    // the pattern the other provider tests in this directory use.
    final states = <AsyncValue<List<BalanceAdjustment>>>[];
    container.listen(balanceAdjustmentsProvider, (_, next) => states.add(next), fireImmediately: true);

    for (var attempt = 0; attempt < 50 && states.last.value == null; attempt++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    expect(states.last.value?.single.deltaMinutes, -120);
  });
}
