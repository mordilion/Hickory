import 'package:async/async.dart';
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

  test('createTier inserts a row and getAllTiers returns it ordered by afterMinutes', () async {
    await db.breakRuleTiersDao.createTier(deviceId: 'dev_a', afterMinutes: 540, requiredBreakMinutes: 45);
    await db.breakRuleTiersDao.createTier(deviceId: 'dev_a', afterMinutes: 360, requiredBreakMinutes: 30);

    final tiers = await db.breakRuleTiersDao.getAllTiers();
    expect(tiers, hasLength(2));
    expect(tiers.map((t) => t.afterMinutes), [360, 540]);
  });

  test('deleteTier removes the row', () async {
    final tier =
        await db.breakRuleTiersDao.createTier(deviceId: 'dev_a', afterMinutes: 360, requiredBreakMinutes: 30);
    await db.breakRuleTiersDao.deleteTier(tier.id);

    expect(await db.breakRuleTiersDao.getAllTiers(), isEmpty);
  });

  test('watchAllTiers emits on insert', () async {
    final queue = StreamQueue<int>(
      db.breakRuleTiersDao.watchAllTiers().map((tiers) => tiers.length),
    );
    addTearDown(queue.cancel);

    // Verify initial emission is 0 (empty list on subscription)
    expect(await queue.next, 0);

    // Insert a tier
    await db.breakRuleTiersDao.createTier(deviceId: 'dev_a', afterMinutes: 360, requiredBreakMinutes: 30);

    // Verify the stream emits 1 (one tier inserted)
    expect(await queue.next, 1);
  });
}
