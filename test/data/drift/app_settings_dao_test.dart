import 'package:drift/drift.dart' show Value;
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

  test('new settings columns start at their documented defaults', () async {
    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.targetMinutesMonday, 0);
    expect(settings.targetMinutesSunday, 0);
    expect(settings.targetInputMode, 'perWeekday');
    expect(settings.balanceResetMode, 'none');
    expect(settings.balanceResetDay, isNull);
    expect(settings.carryOverMaxMinutes, isNull);
    expect(settings.absenceTrackingEnabled, isFalse);
  });

  test('updateSettings stores targets and the balance reset rule', () async {
    final updated = await db.appSettingsDao.updateSettings(
      targetMinutesMonday: 480,
      targetMinutesFriday: 300,
      targetInputMode: 'perWeek',
      balanceResetMode: 'carryOver',
      balanceResetDay: const Value(1),
      balanceResetMonth: const Value(7),
      carryOverMaxMinutes: const Value(1200),
    );
    expect(updated.targetMinutesMonday, 480);
    expect(updated.targetMinutesFriday, 300);
    expect(updated.targetMinutesTuesday, 0, reason: 'untouched days keep their value');
    expect(updated.targetInputMode, 'perWeek');
    expect(updated.balanceResetMode, 'carryOver');
    expect(updated.balanceResetDay, 1);
    expect(updated.balanceResetMonth, 7);
    expect(updated.carryOverMaxMinutes, 1200);
  });

  test('a nullable balance field can be cleared back to null', () async {
    await db.appSettingsDao.updateSettings(carryOverMaxMinutes: const Value(1200));
    final cleared = await db.appSettingsDao.updateSettings(
      carryOverMaxMinutes: const Value(null),
    );
    expect(cleared.carryOverMaxMinutes, isNull);
  });

  test('omitting a nullable balance field leaves it untouched', () async {
    await db.appSettingsDao.updateSettings(carryOverMaxMinutes: const Value(1200));
    final untouched = await db.appSettingsDao.updateSettings(dateFormat: 'de');
    expect(untouched.carryOverMaxMinutes, 1200);
  });
}
