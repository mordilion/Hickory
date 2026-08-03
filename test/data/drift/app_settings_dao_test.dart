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

  test('watchSettings emits the hardcoded default when no row exists', () async {
    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.dateFormat, 'iso');
    expect(settings.timeFormat, '24h');
  });

  test('updateSettings upserts a single row and only changes the given fields', () async {
    final first = await db.appSettingsDao.updateSettings(dateFormat: 'de');
    expect(first.dateFormat, 'de');
    expect(first.timeFormat, '24h');

    final second = await db.appSettingsDao.updateSettings(timeFormat: '12h');
    expect(second.dateFormat, 'de');
    expect(second.timeFormat, '12h');

    final rows = await db.select(db.appSettings).get();
    expect(rows, hasLength(1), reason: 'must stay a singleton, never a second row');
  });

  test('watchSettings reflects updateSettings reactively', () async {
    final stream = db.appSettingsDao.watchSettings().map((s) => s.dateFormat);
    final expectation = expectLater(stream, emitsInOrder(['iso', 'us']));

    await db.appSettingsDao.updateSettings(dateFormat: 'us');

    await expectation;
  });

  test('watchSettings default row includes the default quick-add durations', () async {
    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.quickAddDurationsMinutes, '15,30,45,60');
  });

  test('updateSettings updates quickAddDurationsMinutes independently of other fields', () async {
    final first = await db.appSettingsDao.updateSettings(quickAddDurationsMinutes: '10,20');
    expect(first.quickAddDurationsMinutes, '10,20');
    expect(first.dateFormat, 'iso');

    final second = await db.appSettingsDao.updateSettings(dateFormat: 'de');
    expect(second.quickAddDurationsMinutes, '10,20', reason: 'must not be reset by an unrelated update');
  });
}
