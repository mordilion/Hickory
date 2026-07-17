# Work-Time Calendar & Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Calendar view (month + week) showing tracked time against configurable, internationally-flexible work-time rules (daily min/max, tiered breaks, weekly/monthly targets, a running overtime/undertime balance), and lift the app's fixed 400×800 window size so the calendar has room to render.

**Architecture:** Three new synced Drift tables (`BreakRuleTiers`, `DayExceptions`, `BalanceAdjustments`) plus two new columns groups on the existing `AppSettings` singleton row. A pure-Dart calculation module (no DB/Flutter dependency) evaluates day- and period-level compliance on demand — mirrors `report_calculations.dart`, no materialized cache. Plain Riverpod providers wire the DAOs and calculation module into a new `Calendar` tab. Window resizing uses `window_manager`'s existing API plus a new local-only (unsynced) geometry store.

**Tech Stack:** Flutter, Riverpod (plain providers — see rationale below), Drift, `window_manager`, `path_provider`, `intl`.

**Full design:** `docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md`

## Global Constraints

- English only in code, comments, and commit messages (repo convention).
- ARB template locale is **German** (`lib/l10n/app_de.arb`, `template-arb-file: app_de.arb` in `l10n.yaml`) — write the German string first, then add the same key with a real translation to `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`. `test/l10n/arb_completeness_test.dart` fails the build if any locale's key set diverges.
- Providers touching Drift-generated row classes (`TimeEntry`, `AppSettingsRow`, `BreakRuleTier`, `DayException`, `BalanceAdjustment`, ...) must be **plain** `Provider`/`FutureProvider`/`StreamProvider`, not `@riverpod` codegen — mixing riverpod_generator with drift's generator in the same type trips `rrousselGit/riverpod#4323` (see `lib/features/reports/reports_providers.dart` and `lib/core/di/sync_providers.dart` for the existing precedent).
- Every new synced entity (`BreakRuleTiers`, `DayExceptions`, `BalanceAdjustments`) follows the exact existing pattern: Drift table → DAO → `EntityTypes` constant → `SyncedWrites` write-through method(s) → `SyncIngestor._applyMaterializedEntity` case → round-trip test in `test/data/sync_round_trip_test.dart`. Read `lib/data/sync/synced_writes.dart` and `lib/data/sync/sync_ingestor.dart` before touching them if anything here is unclear.
- Window geometry (size/position) is a per-device UI preference and must **never** be written to the synced event log — local file only, same pattern as `lib/core/locale/locale_store.dart` and `lib/core/window/background_notice_store.dart`.
- Don't add fixed dependency version numbers by hand; this plan introduces no new third-party dependencies (everything needed — `window_manager`, `path_provider`, `intl`, `drift` — is already in `pubspec.yaml`).
- Accessibility: status indicators must combine an icon with color, never color alone (repo a11y rule) — see Task 13.
- Weekday names in UI are produced via `DateFormat.EEEE(localeName)` (locale-aware), not hardcoded/ARB strings — avoids 7 keys × 6 languages for something `intl` already does correctly.
- After any Drift table/column change: run `dart run build_runner build --delete-conflicting-outputs` before running tests.

---

### Task 1: `AppSettings` — per-weekday targets and daily maximum

**Files:**
- Modify: `lib/data/drift/tables/app_settings_table.dart`
- Modify: `lib/data/drift/daos/app_settings_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/sync/synced_writes.dart`
- Test: `test/data/drift/app_settings_dao_test.dart`
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Produces: `AppSettings` table gains `targetMinutesMonday` … `targetMinutesSunday` (int, default `0`) and `maxDailyMinutes` (int, nullable). `AppSettingsDao.updateSettings(...)` and `SyncedWrites.updateAppSettings(...)` both gain the same 7 `int?` weekday params plus `Value<int?> maxDailyMinutes = const Value.absent()`. `AppDatabase.schemaVersion == 5`.

- [ ] **Step 1: Add the new columns to `AppSettings`**

Edit `lib/data/drift/tables/app_settings_table.dart`:

```dart
import 'package:drift/drift.dart';

/// A singleton settings row — always exactly one record, keyed by the
/// fixed id [appSettingsRowId] rather than a generated UUID, since there is
/// exactly one current value per synced identity. Deliberately holds more
/// than just date/time format so a future setting (e.g. the planned i18n
/// language preference) can be added as a new column without introducing a
/// second synced singleton entity type.
const appSettingsRowId = 'default';

@DataClassName('AppSettingsRow')
class AppSettings extends Table {
  TextColumn get id => text()();
  TextColumn get dateFormat => text().withDefault(const Constant('iso'))();
  TextColumn get timeFormat => text().withDefault(const Constant('24h'))();
  // Per-weekday minimum work-time target, in minutes. 0 means "not a work
  // day" — doubles as the free-day marker, no separate flag needed. See
  // docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md.
  IntColumn get targetMinutesMonday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesTuesday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesWednesday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesThursday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesFriday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesSaturday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesSunday => integer().withDefault(const Constant(0))();
  // Daily maximum work time in minutes; null = no maximum configured.
  IntColumn get maxDailyMinutes => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Register the migration**

Edit `lib/data/drift/database.dart`:

```dart
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(timeEntries, timeEntries.pausedAt);
        await m.addColumn(timeEntries, timeEntries.totalPausedSeconds);
      }
      if (from < 3) {
        await m.createTable(appSettings);
      }
      if (from < 4) {
        await m.addColumn(timeEntries, timeEntries.jiraTicketKey);
        await m.createTable(jiraWorklogs);
      }
      if (from < 5) {
        await m.addColumn(appSettings, appSettings.targetMinutesMonday);
        await m.addColumn(appSettings, appSettings.targetMinutesTuesday);
        await m.addColumn(appSettings, appSettings.targetMinutesWednesday);
        await m.addColumn(appSettings, appSettings.targetMinutesThursday);
        await m.addColumn(appSettings, appSettings.targetMinutesFriday);
        await m.addColumn(appSettings, appSettings.targetMinutesSaturday);
        await m.addColumn(appSettings, appSettings.targetMinutesSunday);
        await m.addColumn(appSettings, appSettings.maxDailyMinutes);
      }
    },
  );
```

- [ ] **Step 3: Extend the DAO**

Edit `lib/data/drift/daos/app_settings_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/app_settings_table.dart';

part 'app_settings_dao.g.dart';

@DriftAccessor(tables: [AppSettings])
class AppSettingsDao extends DatabaseAccessor<AppDatabase> with _$AppSettingsDaoMixin {
  AppSettingsDao(super.db);

  /// Streams the current settings row, or the app's hardcoded defaults
  /// (iso date, 24h time, no weekday targets, no daily maximum) if no row
  /// has been written yet.
  Stream<AppSettingsRow> watchSettings() {
    return (select(appSettings)..where((s) => s.id.equals(appSettingsRowId)))
        .watchSingleOrNull()
        .map((row) => row ?? _defaultRow());
  }

  Future<AppSettingsRow> updateSettings({
    String? dateFormat,
    String? timeFormat,
    int? targetMinutesMonday,
    int? targetMinutesTuesday,
    int? targetMinutesWednesday,
    int? targetMinutesThursday,
    int? targetMinutesFriday,
    int? targetMinutesSaturday,
    int? targetMinutesSunday,
    Value<int?> maxDailyMinutes = const Value.absent(),
  }) async {
    final current =
        await (select(appSettings)..where((s) => s.id.equals(appSettingsRowId))).getSingleOrNull() ??
            _defaultRow();
    final updated = AppSettingsRow(
      id: appSettingsRowId,
      dateFormat: dateFormat ?? current.dateFormat,
      timeFormat: timeFormat ?? current.timeFormat,
      targetMinutesMonday: targetMinutesMonday ?? current.targetMinutesMonday,
      targetMinutesTuesday: targetMinutesTuesday ?? current.targetMinutesTuesday,
      targetMinutesWednesday: targetMinutesWednesday ?? current.targetMinutesWednesday,
      targetMinutesThursday: targetMinutesThursday ?? current.targetMinutesThursday,
      targetMinutesFriday: targetMinutesFriday ?? current.targetMinutesFriday,
      targetMinutesSaturday: targetMinutesSaturday ?? current.targetMinutesSaturday,
      targetMinutesSunday: targetMinutesSunday ?? current.targetMinutesSunday,
      maxDailyMinutes: maxDailyMinutes.present ? maxDailyMinutes.value : current.maxDailyMinutes,
      updatedAt: DateTime.now().toUtc(),
    );
    await into(appSettings).insertOnConflictUpdate(updated);
    return updated;
  }

  AppSettingsRow _defaultRow() => AppSettingsRow(
        id: appSettingsRowId,
        dateFormat: 'iso',
        timeFormat: '24h',
        targetMinutesMonday: 0,
        targetMinutesTuesday: 0,
        targetMinutesWednesday: 0,
        targetMinutesThursday: 0,
        targetMinutesFriday: 0,
        targetMinutesSaturday: 0,
        targetMinutesSunday: 0,
        maxDailyMinutes: null,
        updatedAt: DateTime.now().toUtc(),
      );
}
```

- [ ] **Step 4: Extend `SyncedWrites.updateAppSettings`**

Edit `lib/data/sync/synced_writes.dart`, replacing the existing `updateAppSettings` method:

```dart
  /// Updates the shared, synced app settings row. Uses the fixed
  /// [appSettingsRowId] instead of a generated id — there is exactly one
  /// settings row per synced identity, so every device's write targets the
  /// same entity and last-write-wins resolves conflicts the same way it
  /// does for every other synced entity.
  Future<AppSettingsRow> updateAppSettings({
    String? dateFormat,
    String? timeFormat,
    int? targetMinutesMonday,
    int? targetMinutesTuesday,
    int? targetMinutesWednesday,
    int? targetMinutesThursday,
    int? targetMinutesFriday,
    int? targetMinutesSaturday,
    int? targetMinutesSunday,
    Value<int?> maxDailyMinutes = const Value.absent(),
  }) async {
    final updated = await db.appSettingsDao.updateSettings(
      dateFormat: dateFormat,
      timeFormat: timeFormat,
      targetMinutesMonday: targetMinutesMonday,
      targetMinutesTuesday: targetMinutesTuesday,
      targetMinutesWednesday: targetMinutesWednesday,
      targetMinutesThursday: targetMinutesThursday,
      targetMinutesFriday: targetMinutesFriday,
      targetMinutesSaturday: targetMinutesSaturday,
      targetMinutesSunday: targetMinutesSunday,
      maxDailyMinutes: maxDailyMinutes,
    );
    await logWriter.appendEvent(
      entityType: EntityTypes.appSettings,
      entityId: appSettingsRowId,
      op: EventOp.update,
      payload: updated.toJson(),
    );
    return updated;
  }
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors.

- [ ] **Step 6: Extend the DAO test**

Edit `test/data/drift/app_settings_dao_test.dart`, adding at the end of `main()` before the closing `}`:

```dart
  test('weekday targets default to 0 and maxDailyMinutes defaults to null', () async {
    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.targetMinutesMonday, 0);
    expect(settings.targetMinutesSunday, 0);
    expect(settings.maxDailyMinutes, isNull);
  });

  test('updateSettings sets weekday targets and maxDailyMinutes independently', () async {
    final first = await db.appSettingsDao.updateSettings(
      targetMinutesMonday: 480,
      targetMinutesFriday: 240,
      maxDailyMinutes: const Value(600),
    );
    expect(first.targetMinutesMonday, 480);
    expect(first.targetMinutesFriday, 240);
    expect(first.targetMinutesTuesday, 0);
    expect(first.maxDailyMinutes, 600);

    // A later update that doesn't touch maxDailyMinutes leaves it as-is...
    final second = await db.appSettingsDao.updateSettings(targetMinutesTuesday: 480);
    expect(second.maxDailyMinutes, 600);

    // ...but an update that explicitly passes null clears it.
    final third = await db.appSettingsDao.updateSettings(maxDailyMinutes: const Value(null));
    expect(third.maxDailyMinutes, isNull);
  });
```

Add the import at the top of the file if not already present:

```dart
import 'package:drift/drift.dart' show Value;
```

- [ ] **Step 7: Extend the sync round-trip test**

Edit `test/data/sync_round_trip_test.dart`, replacing the body of the existing `'app settings sync as a singleton row across devices'` test:

```dart
  test(
    'app settings sync as a singleton row across devices',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      await writerWrites.updateAppSettings(
        dateFormat: 'de',
        timeFormat: '12h',
        targetMinutesMonday: 480,
        maxDailyMinutes: const Value(600),
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final rows = await readerDb.select(readerDb.appSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.dateFormat, 'de');
      expect(rows.single.timeFormat, '12h');
      expect(rows.single.targetMinutesMonday, 480);
      expect(rows.single.maxDailyMinutes, 600);
    },
  );
```

- [ ] **Step 8: Run the tests**

Run: `flutter test test/data/drift/app_settings_dao_test.dart test/data/sync_round_trip_test.dart`
Expected: PASS (all tests, including the new ones)

- [ ] **Step 9: Commit**

```bash
git add lib/data/drift/tables/app_settings_table.dart lib/data/drift/daos/app_settings_dao.dart lib/data/drift/daos/app_settings_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/sync/synced_writes.dart test/data/drift/app_settings_dao_test.dart test/data/sync_round_trip_test.dart
git commit -m "feat(db): add per-weekday target hours and daily maximum to AppSettings"
```

---

### Task 2: `BreakRuleTiers` — table, DAO, migration

**Files:**
- Create: `lib/data/drift/tables/break_rule_tiers_table.dart`
- Create: `lib/data/drift/daos/break_rule_tiers_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/sync/entity_types.dart`
- Test: `test/data/drift/break_rule_tiers_dao_test.dart`

**Interfaces:**
- Produces: `BreakRuleTiers` table with `@DataClassName('BreakRuleTier')`, columns `id` (text, PK), `afterMinutes` (int), `requiredBreakMinutes` (int), `deviceId` (text), `createdAt`/`updatedAt` (datetime). `BreakRuleTiersDao` with `watchAllTiers()`, `getAllTiers()`, `createTier({required deviceId, afterMinutes, requiredBreakMinutes})`, `deleteTier(String id)`. `EntityTypes.breakRuleTier = 'break_rule_tier'`. `AppDatabase.schemaVersion == 6`.

- [ ] **Step 1: Create the table**

Create `lib/data/drift/tables/break_rule_tiers_table.dart`:

```dart
import 'package:drift/drift.dart';

/// A single break-time requirement: once a day's worked time reaches
/// [afterMinutes], at least [requiredBreakMinutes] of break time is
/// required that day. Multiple tiers let the user model tiered rules (e.g.
/// 30 min after 6h, 45 min after 9h) — evaluation picks the tier with the
/// highest [afterMinutes] that the day's worked time has reached. Synced
/// across the user's own devices via the event log, like every other
/// entity. See
/// docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md.
@DataClassName('BreakRuleTier')
class BreakRuleTiers extends Table {
  TextColumn get id => text()();
  IntColumn get afterMinutes => integer()();
  IntColumn get requiredBreakMinutes => integer()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Create the DAO**

Create `lib/data/drift/daos/break_rule_tiers_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/break_rule_tiers_table.dart';

part 'break_rule_tiers_dao.g.dart';

@DriftAccessor(tables: [BreakRuleTiers])
class BreakRuleTiersDao extends DatabaseAccessor<AppDatabase> with _$BreakRuleTiersDaoMixin {
  BreakRuleTiersDao(super.db);

  static const _uuid = Uuid();

  Stream<List<BreakRuleTier>> watchAllTiers() {
    return (select(breakRuleTiers)..orderBy([(t) => OrderingTerm.asc(t.afterMinutes)])).watch();
  }

  Future<List<BreakRuleTier>> getAllTiers() =>
      (select(breakRuleTiers)..orderBy([(t) => OrderingTerm.asc(t.afterMinutes)])).get();

  Future<BreakRuleTier> createTier({
    required String deviceId,
    required int afterMinutes,
    required int requiredBreakMinutes,
  }) async {
    final now = DateTime.now().toUtc();
    final tier = BreakRuleTiersCompanion.insert(
      id: _uuid.v4(),
      afterMinutes: afterMinutes,
      requiredBreakMinutes: requiredBreakMinutes,
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(breakRuleTiers).insert(tier);
    return (select(breakRuleTiers)..where((t) => t.id.equals(tier.id.value))).getSingle();
  }

  Future<void> deleteTier(String id) {
    return (delete(breakRuleTiers)..where((t) => t.id.equals(id))).go();
  }
}
```

- [ ] **Step 3: Register the table/DAO and add the migration**

Edit `lib/data/drift/database.dart`. Add imports:

```dart
import 'daos/break_rule_tiers_dao.dart';
import 'tables/break_rule_tiers_table.dart';
```

Add `BreakRuleTiers` to the `tables:` list and `BreakRuleTiersDao` to the `daos:` list. Bump the version:

```dart
  @override
  int get schemaVersion => 6;
```

Add a new branch to `onUpgrade`, after the `if (from < 5)` block:

```dart
      if (from < 6) {
        await m.createTable(breakRuleTiers);
      }
```

- [ ] **Step 4: Add the entity type constant**

Edit `lib/data/sync/entity_types.dart`:

```dart
  static const breakRuleTier = 'break_rule_tier';
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors; `lib/data/drift/daos/break_rule_tiers_dao.g.dart` is generated.

- [ ] **Step 6: Write the DAO test**

Create `test/data/drift/break_rule_tiers_dao_test.dart`:

```dart
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
    final stream = db.breakRuleTiersDao.watchAllTiers().map((tiers) => tiers.length);
    final expectation = expectLater(stream, emitsInOrder([0, 1]));

    await db.breakRuleTiersDao.createTier(deviceId: 'dev_a', afterMinutes: 360, requiredBreakMinutes: 30);

    await expectation;
  });
}
```

- [ ] **Step 7: Run the test**

Run: `flutter test test/data/drift/break_rule_tiers_dao_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/data/drift/tables/break_rule_tiers_table.dart lib/data/drift/daos/break_rule_tiers_dao.dart lib/data/drift/daos/break_rule_tiers_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/sync/entity_types.dart test/data/drift/break_rule_tiers_dao_test.dart
git commit -m "feat(db): add BreakRuleTiers table for tiered break-time rules"
```

---
### Task 3: `BreakRuleTiers` — cross-device sync wiring

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `BreakRuleTiersDao` (Task 2), `EntityTypes.breakRuleTier` (Task 2).
- Produces: `SyncedWrites.createBreakRuleTier({required deviceId, afterMinutes, requiredBreakMinutes})` and `SyncedWrites.deleteBreakRuleTier(String id)`.

- [ ] **Step 1: Add the write-through methods to `SyncedWrites`**

Edit `lib/data/sync/synced_writes.dart`, adding after `updateAppSettings`:

```dart
  /// Creates a break-rule tier and logs it, so it propagates to the user's
  /// other devices the same way every other entity does.
  Future<BreakRuleTier> createBreakRuleTier({
    required String deviceId,
    required int afterMinutes,
    required int requiredBreakMinutes,
  }) async {
    final tier = await db.breakRuleTiersDao.createTier(
      deviceId: deviceId,
      afterMinutes: afterMinutes,
      requiredBreakMinutes: requiredBreakMinutes,
    );
    await logWriter.appendEvent(
      entityType: EntityTypes.breakRuleTier,
      entityId: tier.id,
      op: EventOp.create,
      payload: tier.toJson(),
    );
    return tier;
  }

  Future<void> deleteBreakRuleTier(String id) async {
    await db.breakRuleTiersDao.deleteTier(id);
    await logWriter.appendEvent(
      entityType: EntityTypes.breakRuleTier,
      entityId: id,
      op: EventOp.delete,
      payload: null,
    );
  }
```

No new import is needed for `BreakRuleTier` — it's already visible via the
existing `import '../drift/database.dart';` at the top of the file (Drift
generates the `BreakRuleTier` data class into `database.g.dart`, a `part` of
that same library).

- [ ] **Step 2: Materialize `break_rule_tier` events in the ingestor**

Edit `lib/data/sync/sync_ingestor.dart`, adding a case to `_applyMaterializedEntity`'s switch, after the `EntityTypes.jiraWorklog` case and before `default`:

```dart
      case EntityTypes.breakRuleTier:
        if (entity.isDeleted) {
          await (db.delete(db.breakRuleTiers)..where((t) => t.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.breakRuleTiers)
              .insertOnConflictUpdate(BreakRuleTier.fromJson(entity.payload!).toCompanion(true));
        }
```

Also update `rebuildFromScratch` to clear `breakRuleTiers`:

```dart
  Future<void> rebuildFromScratch() async {
    await db.eventsDao.clearAll();
    await db.transaction(() async {
      await db.delete(db.timeEntries).go();
      await db.delete(db.projects).go();
      await db.delete(db.jiraWorklogs).go();
      await db.delete(db.breakRuleTiers).go();
    });
    await syncNow();
  }
```

- [ ] **Step 3: Write the round-trip test**

Edit `test/data/sync_round_trip_test.dart`, adding a new test at the end of `main()`, before the closing `}`:

```dart
  test(
    'a break rule tier syncs to a second device, including deletion',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final tier = await writerWrites.createBreakRuleTier(
        deviceId: 'dev_a',
        afterMinutes: 360,
        requiredBreakMinutes: 30,
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final tiers = await readerDb.breakRuleTiersDao.getAllTiers();
      expect(tiers, hasLength(1));
      expect(tiers.single.afterMinutes, 360);

      await writerWrites.deleteBreakRuleTier(tier.id);
      await ingestor.syncNow();

      expect(await readerDb.breakRuleTiersDao.getAllTiers(), isEmpty);
    },
  );
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS (all tests, including the new one)

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/synced_writes.dart lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): propagate break rule tiers across devices"
```

---

### Task 4: `DayExceptions` — table, DAO, migration

**Files:**
- Create: `lib/data/drift/tables/day_exceptions_table.dart`
- Create: `lib/data/drift/daos/day_exceptions_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/sync/entity_types.dart`
- Test: `test/data/drift/day_exceptions_dao_test.dart`

**Interfaces:**
- Produces: `DayExceptions` table with `@DataClassName('DayException')`, columns `id` (text, PK), `date` (datetime, unique), `type` (text: `holiday`/`vacation`/`sick`/`custom`), `note` (text, nullable), `deviceId`, `createdAt`/`updatedAt`. `DayExceptionTypes` constants. `DayExceptionsDao` with `watchExceptionsInRange(start, end)`, `getForDate(DateTime date)`, `upsertException({required deviceId, date, type, note})`, `deleteException(String id)`. `EntityTypes.dayException = 'day_exception'`. `AppDatabase.schemaVersion == 7`.

- [ ] **Step 1: Create the table**

Create `lib/data/drift/tables/day_exceptions_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Values used in [DayException.type].
abstract final class DayExceptionTypes {
  static const holiday = 'holiday';
  static const vacation = 'vacation';
  static const sick = 'sick';
  static const custom = 'custom';
}

/// Marks a single calendar day as non-working regardless of its weekday's
/// configured target — settable directly from the calendar's day-detail
/// view. A day with an exception has both the daily minimum/maximum rules
/// suspended and contributes 0 to a period's target-hours sum. The unique
/// index on [date] is a local safety net against duplicate rows on one
/// device; it doesn't guarantee cross-device dedupe if two devices mark the
/// same day offline at the same time — an accepted edge case, same
/// last-write-wins-per-entity-id model as every other synced entity here.
/// See docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md.
@DataClassName('DayException')
class DayExceptions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get type => text()();
  TextColumn get note => text().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {date},
      ];
}
```

- [ ] **Step 2: Create the DAO**

Create `lib/data/drift/daos/day_exceptions_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/day_exceptions_table.dart';

part 'day_exceptions_dao.g.dart';

@DriftAccessor(tables: [DayExceptions])
class DayExceptionsDao extends DatabaseAccessor<AppDatabase> with _$DayExceptionsDaoMixin {
  DayExceptionsDao(super.db);

  static const _uuid = Uuid();

  /// [start] inclusive, [end] exclusive — both local-day midnights, matching
  /// how [date] is stored.
  Stream<List<DayException>> watchExceptionsInRange(DateTime start, DateTime end) {
    return (select(dayExceptions)
          ..where((e) => e.date.isBiggerOrEqualValue(start) & e.date.isSmallerThanValue(end)))
        .watch();
  }

  Future<DayException?> getForDate(DateTime date) {
    return (select(dayExceptions)..where((e) => e.date.equals(date))).getSingleOrNull();
  }

  /// Creates or replaces the exception for [date] — at most one exception
  /// per date, so a re-mark of an already-marked day updates it in place.
  Future<DayException> upsertException({
    required String deviceId,
    required DateTime date,
    required String type,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final existing = await getForDate(date);
    final row = DayException(
      id: existing?.id ?? _uuid.v4(),
      date: date,
      type: type,
      note: note,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await into(dayExceptions).insertOnConflictUpdate(row);
    return row;
  }

  Future<void> deleteException(String id) {
    return (delete(dayExceptions)..where((e) => e.id.equals(id))).go();
  }
}
```

- [ ] **Step 3: Register the table/DAO and add the migration**

Edit `lib/data/drift/database.dart`. Add imports:

```dart
import 'daos/day_exceptions_dao.dart';
import 'tables/day_exceptions_table.dart';
```

Add `DayExceptions` to `tables:` and `DayExceptionsDao` to `daos:`. Bump the version:

```dart
  @override
  int get schemaVersion => 7;
```

Add to `onUpgrade`, after the `if (from < 6)` block:

```dart
      if (from < 7) {
        await m.createTable(dayExceptions);
      }
```

- [ ] **Step 4: Add the entity type constant**

Edit `lib/data/sync/entity_types.dart`:

```dart
  static const dayException = 'day_exception';
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors.

- [ ] **Step 6: Write the DAO test**

Create `test/data/drift/day_exceptions_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/day_exceptions_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertException creates a row, getForDate finds it', () async {
    final date = DateTime.utc(2026, 12, 25);
    await db.dayExceptionsDao.upsertException(
      deviceId: 'dev_a',
      date: date,
      type: DayExceptionTypes.holiday,
    );

    final found = await db.dayExceptionsDao.getForDate(date);
    expect(found, isNotNull);
    expect(found!.type, DayExceptionTypes.holiday);
  });

  test('upsertException on an already-marked date updates in place, not a second row', () async {
    final date = DateTime.utc(2026, 12, 25);
    await db.dayExceptionsDao.upsertException(deviceId: 'dev_a', date: date, type: DayExceptionTypes.holiday);
    await db.dayExceptionsDao.upsertException(
      deviceId: 'dev_a',
      date: date,
      type: DayExceptionTypes.vacation,
      note: 'changed my mind',
    );

    final all = await db.dayExceptionsDao.watchExceptionsInRange(date, date.add(const Duration(days: 1))).first;
    expect(all, hasLength(1));
    expect(all.single.type, DayExceptionTypes.vacation);
    expect(all.single.note, 'changed my mind');
  });

  test('watchExceptionsInRange only returns dates inside [start, end)', () async {
    await db.dayExceptionsDao.upsertException(
      deviceId: 'dev_a',
      date: DateTime.utc(2026, 12, 24),
      type: DayExceptionTypes.holiday,
    );
    await db.dayExceptionsDao.upsertException(
      deviceId: 'dev_a',
      date: DateTime.utc(2027, 1, 2),
      type: DayExceptionTypes.holiday,
    );

    final inRange = await db.dayExceptionsDao
        .watchExceptionsInRange(DateTime.utc(2026, 12, 1), DateTime.utc(2027, 1, 1))
        .first;
    expect(inRange, hasLength(1));
    expect(inRange.single.date, DateTime.utc(2026, 12, 24));
  });

  test('deleteException removes the row', () async {
    final date = DateTime.utc(2026, 12, 25);
    final created =
        await db.dayExceptionsDao.upsertException(deviceId: 'dev_a', date: date, type: DayExceptionTypes.holiday);
    await db.dayExceptionsDao.deleteException(created.id);

    expect(await db.dayExceptionsDao.getForDate(date), isNull);
  });
}
```

- [ ] **Step 7: Run the test**

Run: `flutter test test/data/drift/day_exceptions_dao_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/data/drift/tables/day_exceptions_table.dart lib/data/drift/daos/day_exceptions_dao.dart lib/data/drift/daos/day_exceptions_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/sync/entity_types.dart test/data/drift/day_exceptions_dao_test.dart
git commit -m "feat(db): add DayExceptions table for marking non-working days"
```

---

### Task 5: `DayExceptions` — cross-device sync wiring

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `DayExceptionsDao` (Task 4), `EntityTypes.dayException` (Task 4).
- Produces: `SyncedWrites.upsertDayException({required deviceId, date, type, note})` and `SyncedWrites.deleteDayException(String id)`.

- [ ] **Step 1: Add the write-through methods to `SyncedWrites`**

Edit `lib/data/sync/synced_writes.dart`, adding after `deleteBreakRuleTier`:

```dart
  /// Marks (or re-marks) [date] as a non-working day and logs it.
  Future<DayException> upsertDayException({
    required String deviceId,
    required DateTime date,
    required String type,
    String? note,
  }) async {
    final exception = await db.dayExceptionsDao.upsertException(
      deviceId: deviceId,
      date: date,
      type: type,
      note: note,
    );
    await logWriter.appendEvent(
      entityType: EntityTypes.dayException,
      entityId: exception.id,
      op: EventOp.update,
      payload: exception.toJson(),
    );
    return exception;
  }

  Future<void> deleteDayException(String id) async {
    await db.dayExceptionsDao.deleteException(id);
    await logWriter.appendEvent(
      entityType: EntityTypes.dayException,
      entityId: id,
      op: EventOp.delete,
      payload: null,
    );
  }
```

No new import is needed for `DayException` — same reasoning as `BreakRuleTier`
in Task 3: it comes from `database.dart`, already imported.

- [ ] **Step 2: Materialize `day_exception` events in the ingestor**

Edit `lib/data/sync/sync_ingestor.dart`, adding a case after `EntityTypes.breakRuleTier`:

```dart
      case EntityTypes.dayException:
        if (entity.isDeleted) {
          await (db.delete(db.dayExceptions)..where((e) => e.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.dayExceptions)
              .insertOnConflictUpdate(DayException.fromJson(entity.payload!).toCompanion(true));
        }
```

Update `rebuildFromScratch` to also clear `dayExceptions`:

```dart
      await db.delete(db.breakRuleTiers).go();
      await db.delete(db.dayExceptions).go();
```

- [ ] **Step 3: Write the round-trip test**

Edit `test/data/sync_round_trip_test.dart`, adding at the end of `main()`:

```dart
  test(
    'a day exception syncs to a second device, including deletion',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final exception = await writerWrites.upsertDayException(
        deviceId: 'dev_a',
        date: DateTime.utc(2026, 12, 25),
        type: DayExceptionTypes.holiday,
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final found = await readerDb.dayExceptionsDao.getForDate(DateTime.utc(2026, 12, 25));
      expect(found, isNotNull);
      expect(found!.type, DayExceptionTypes.holiday);

      await writerWrites.deleteDayException(exception.id);
      await ingestor.syncNow();

      expect(await readerDb.dayExceptionsDao.getForDate(DateTime.utc(2026, 12, 25)), isNull);
    },
  );
```

Add the import at the top of the file:

```dart
import 'package:hickory/data/drift/tables/day_exceptions_table.dart';
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS (all tests, including the new one)

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/synced_writes.dart lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): propagate day exceptions across devices"
```

---
### Task 6: `BalanceAdjustments` — table, DAO, migration

**Files:**
- Create: `lib/data/drift/tables/balance_adjustments_table.dart`
- Create: `lib/data/drift/daos/balance_adjustments_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/sync/entity_types.dart`
- Test: `test/data/drift/balance_adjustments_dao_test.dart`

**Interfaces:**
- Produces: `BalanceAdjustments` table with `@DataClassName('BalanceAdjustment')`, columns `id` (text, PK), `date` (datetime), `deltaMinutes` (int, signed), `note` (text, nullable), `deviceId`, `createdAt`/`updatedAt`. `BalanceAdjustmentsDao` with `watchAllAdjustments()`, `getAllAdjustments()`, `createAdjustment({required deviceId, date, deltaMinutes, note})`, `deleteAdjustment(String id)`. `EntityTypes.balanceAdjustment = 'balance_adjustment'`. `AppDatabase.schemaVersion == 8`.

- [ ] **Step 1: Create the table**

Create `lib/data/drift/tables/balance_adjustments_table.dart`:

```dart
import 'package:drift/drift.dart';

/// A manual correction to the running overtime/undertime balance (e.g. a
/// year-end reset to 0, or fixing a mistake) — [deltaMinutes] is added to
/// the balance as of [date]. Corrections are additive, never destructive:
/// a "reset" is just a new row with a delta that offsets the accumulated
/// total, so every past adjustment stays in the history. See
/// docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md.
@DataClassName('BalanceAdjustment')
class BalanceAdjustments extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get deltaMinutes => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Create the DAO**

Create `lib/data/drift/daos/balance_adjustments_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/balance_adjustments_table.dart';

part 'balance_adjustments_dao.g.dart';

@DriftAccessor(tables: [BalanceAdjustments])
class BalanceAdjustmentsDao extends DatabaseAccessor<AppDatabase> with _$BalanceAdjustmentsDaoMixin {
  BalanceAdjustmentsDao(super.db);

  static const _uuid = Uuid();

  Stream<List<BalanceAdjustment>> watchAllAdjustments() {
    return (select(balanceAdjustments)..orderBy([(a) => OrderingTerm.asc(a.date)])).watch();
  }

  Future<List<BalanceAdjustment>> getAllAdjustments() =>
      (select(balanceAdjustments)..orderBy([(a) => OrderingTerm.asc(a.date)])).get();

  Future<BalanceAdjustment> createAdjustment({
    required String deviceId,
    required DateTime date,
    required int deltaMinutes,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final adjustment = BalanceAdjustmentsCompanion.insert(
      id: _uuid.v4(),
      date: date,
      deltaMinutes: deltaMinutes,
      note: Value(note),
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(balanceAdjustments).insert(adjustment);
    return (select(balanceAdjustments)..where((a) => a.id.equals(adjustment.id.value))).getSingle();
  }

  Future<void> deleteAdjustment(String id) {
    return (delete(balanceAdjustments)..where((a) => a.id.equals(id))).go();
  }
}
```

- [ ] **Step 3: Register the table/DAO and add the migration**

Edit `lib/data/drift/database.dart`. Add imports:

```dart
import 'daos/balance_adjustments_dao.dart';
import 'tables/balance_adjustments_table.dart';
```

Add `BalanceAdjustments` to `tables:` and `BalanceAdjustmentsDao` to `daos:`. Bump the version:

```dart
  @override
  int get schemaVersion => 8;
```

Add to `onUpgrade`, after the `if (from < 7)` block:

```dart
      if (from < 8) {
        await m.createTable(balanceAdjustments);
      }
```

- [ ] **Step 4: Add the entity type constant**

Edit `lib/data/sync/entity_types.dart`:

```dart
  static const balanceAdjustment = 'balance_adjustment';
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors.

- [ ] **Step 6: Write the DAO test**

Create `test/data/drift/balance_adjustments_dao_test.dart`:

```dart
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

  test('createAdjustment inserts a signed delta with an optional note', () async {
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'dev_a',
      date: DateTime.utc(2026, 12, 31),
      deltaMinutes: -120,
      note: 'year-end reset',
    );

    final all = await db.balanceAdjustmentsDao.getAllAdjustments();
    expect(all, hasLength(1));
    expect(all.single.deltaMinutes, -120);
    expect(all.single.note, 'year-end reset');
  });

  test('getAllAdjustments orders by date ascending', () async {
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'dev_a',
      date: DateTime.utc(2026, 6, 1),
      deltaMinutes: 30,
    );
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'dev_a',
      date: DateTime.utc(2026, 1, 1),
      deltaMinutes: -30,
    );

    final all = await db.balanceAdjustmentsDao.getAllAdjustments();
    expect(all.map((a) => a.deltaMinutes), [-30, 30]);
  });

  test('deleteAdjustment removes the row', () async {
    final created = await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'dev_a',
      date: DateTime.utc(2026, 6, 1),
      deltaMinutes: 30,
    );
    await db.balanceAdjustmentsDao.deleteAdjustment(created.id);

    expect(await db.balanceAdjustmentsDao.getAllAdjustments(), isEmpty);
  });
}
```

- [ ] **Step 7: Run the test**

Run: `flutter test test/data/drift/balance_adjustments_dao_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/data/drift/tables/balance_adjustments_table.dart lib/data/drift/daos/balance_adjustments_dao.dart lib/data/drift/daos/balance_adjustments_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/sync/entity_types.dart test/data/drift/balance_adjustments_dao_test.dart
git commit -m "feat(db): add BalanceAdjustments table for manual balance corrections"
```

---

### Task 7: `BalanceAdjustments` — cross-device sync wiring

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `BalanceAdjustmentsDao` (Task 6), `EntityTypes.balanceAdjustment` (Task 6).
- Produces: `SyncedWrites.createBalanceAdjustment({required deviceId, date, deltaMinutes, note})` and `SyncedWrites.deleteBalanceAdjustment(String id)`.

- [ ] **Step 1: Add the write-through methods to `SyncedWrites`**

Edit `lib/data/sync/synced_writes.dart`, adding after `deleteDayException`:

```dart
  /// Records a manual balance correction and logs it.
  Future<BalanceAdjustment> createBalanceAdjustment({
    required String deviceId,
    required DateTime date,
    required int deltaMinutes,
    String? note,
  }) async {
    final adjustment = await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: deviceId,
      date: date,
      deltaMinutes: deltaMinutes,
      note: note,
    );
    await logWriter.appendEvent(
      entityType: EntityTypes.balanceAdjustment,
      entityId: adjustment.id,
      op: EventOp.create,
      payload: adjustment.toJson(),
    );
    return adjustment;
  }

  Future<void> deleteBalanceAdjustment(String id) async {
    await db.balanceAdjustmentsDao.deleteAdjustment(id);
    await logWriter.appendEvent(
      entityType: EntityTypes.balanceAdjustment,
      entityId: id,
      op: EventOp.delete,
      payload: null,
    );
  }
```

No new import is needed for `BalanceAdjustment` — same reasoning as
`BreakRuleTier` in Task 3: it comes from `database.dart`, already imported.

- [ ] **Step 2: Materialize `balance_adjustment` events in the ingestor**

Edit `lib/data/sync/sync_ingestor.dart`, adding a case after `EntityTypes.dayException`:

```dart
      case EntityTypes.balanceAdjustment:
        if (entity.isDeleted) {
          await (db.delete(db.balanceAdjustments)..where((a) => a.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.balanceAdjustments)
              .insertOnConflictUpdate(BalanceAdjustment.fromJson(entity.payload!).toCompanion(true));
        }
```

Update `rebuildFromScratch` to also clear `balanceAdjustments`:

```dart
      await db.delete(db.dayExceptions).go();
      await db.delete(db.balanceAdjustments).go();
```

- [ ] **Step 3: Write the round-trip test**

Edit `test/data/sync_round_trip_test.dart`, adding at the end of `main()`:

```dart
  test(
    'a balance adjustment syncs to a second device, including deletion',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final adjustment = await writerWrites.createBalanceAdjustment(
        deviceId: 'dev_a',
        date: DateTime.utc(2026, 12, 31),
        deltaMinutes: -120,
        note: 'year-end reset',
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final all = await readerDb.balanceAdjustmentsDao.getAllAdjustments();
      expect(all, hasLength(1));
      expect(all.single.deltaMinutes, -120);

      await writerWrites.deleteBalanceAdjustment(adjustment.id);
      await ingestor.syncNow();

      expect(await readerDb.balanceAdjustmentsDao.getAllAdjustments(), isEmpty);
    },
  );
```

No new import is needed — this test only calls DAO/`SyncedWrites` methods and
never names the `BalanceAdjustment` type directly, unlike Task 5's
`DayExceptionTypes.holiday` reference.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS (all tests, including the new one)

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/synced_writes.dart lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): propagate balance adjustments across devices"
```

---
### Task 8: Day-level compliance calculations (pure Dart)

**Files:**
- Create: `lib/features/calendar/day_compliance.dart`
- Test: `test/features/calendar/day_compliance_test.dart`

**Interfaces:**
- Consumes: `TimeEntry`, `TimeEntryDuration.workedDuration` (`lib/data/drift/time_entry_extensions.dart`), `AppSettingsRow` (Task 1), `BreakRuleTier` (Task 2), `DayException` (Task 4).
- Produces: `enum DayComplianceStatus { compliant, violation, exception, noRule }`; `class DayCompliance` with fields `date`, `workedMinutes`, `targetMinutes`, `maxMinutes`, `breakTakenMinutes`, `breakRequiredMinutes`, `isException`, and getter `status`; top-level functions `dailyWorkedMinutes(List<TimeEntry>)`, `dailyBreakMinutes(List<TimeEntry>)`, `requiredBreakMinutesFor(int workedMinutes, List<BreakRuleTier> tiers)`, `targetMinutesForWeekday(AppSettingsRow, int weekday)`, `dayCompliancesInRange({required start, end, entries, settings, breakTiers, exceptions})`. Used by Task 9 and Task 10.

- [ ] **Step 1: Write the failing tests**

Create `test/features/calendar/day_compliance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/calendar/day_compliance.dart';

TimeEntry _entry({required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: 'e_${startAt.toIso8601String()}',
    projectId: null,
    description: null,
    startAt: startAt,
    endAt: endAt,
    source: 'manual',
    deviceId: 'dev_a',
    createdAt: now,
    updatedAt: now,
    totalPausedSeconds: 0,
  );
}

AppSettingsRow _settings({
  int mon = 0,
  int tue = 0,
  int wed = 0,
  int thu = 0,
  int fri = 0,
  int sat = 0,
  int sun = 0,
  int? maxDailyMinutes,
}) {
  return AppSettingsRow(
    id: 'default',
    dateFormat: 'iso',
    timeFormat: '24h',
    targetMinutesMonday: mon,
    targetMinutesTuesday: tue,
    targetMinutesWednesday: wed,
    targetMinutesThursday: thu,
    targetMinutesFriday: fri,
    targetMinutesSaturday: sat,
    targetMinutesSunday: sun,
    maxDailyMinutes: maxDailyMinutes,
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('dailyWorkedMinutes', () {
    test('a same-day entry counts fully on its day', () {
      final entries = [
        _entry(startAt: DateTime.utc(2026, 7, 6, 9), endAt: DateTime.utc(2026, 7, 6, 17)),
      ];
      final totals = dailyWorkedMinutes(entries);
      expect(totals[DateTime(2026, 7, 6)], 8 * 60);
    });

    test('an entry crossing midnight splits proportionally across both days', () {
      final entries = [
        _entry(startAt: DateTime.utc(2026, 7, 6, 23), endAt: DateTime.utc(2026, 7, 7, 1)),
      ];
      final totals = dailyWorkedMinutes(entries);
      expect(totals[DateTime(2026, 7, 6)], 60);
      expect(totals[DateTime(2026, 7, 7)], 60);
    });
  });

  group('dailyBreakMinutes', () {
    test('a same-day gap between two entries counts as a break', () {
      final entries = [
        _entry(startAt: DateTime.utc(2026, 7, 6, 9), endAt: DateTime.utc(2026, 7, 6, 12)),
        _entry(startAt: DateTime.utc(2026, 7, 6, 12, 30), endAt: DateTime.utc(2026, 7, 6, 17)),
      ];
      expect(dailyBreakMinutes(entries)[DateTime(2026, 7, 6)], 30);
    });

    test('the overnight gap to the next day is not counted', () {
      final entries = [
        _entry(startAt: DateTime.utc(2026, 7, 6, 9), endAt: DateTime.utc(2026, 7, 6, 17)),
        _entry(startAt: DateTime.utc(2026, 7, 7, 9), endAt: DateTime.utc(2026, 7, 7, 17)),
      ];
      final totals = dailyBreakMinutes(entries);
      expect(totals[DateTime(2026, 7, 6)], isNull);
      expect(totals[DateTime(2026, 7, 7)], isNull);
    });
  });

  group('requiredBreakMinutesFor', () {
    test('returns 0 when no tier is reached', () {
      expect(requiredBreakMinutesFor(300, const []), 0);
    });

    test('picks the highest tier reached', () {
      final twoTiers = [
        BreakRuleTier(
          id: 't1',
          afterMinutes: 360,
          requiredBreakMinutes: 30,
          deviceId: 'dev_a',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        BreakRuleTier(
          id: 't2',
          afterMinutes: 540,
          requiredBreakMinutes: 45,
          deviceId: 'dev_a',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ];
      expect(requiredBreakMinutesFor(400, twoTiers), 30);
      expect(requiredBreakMinutesFor(600, twoTiers), 45);
    });
  });

  group('DayCompliance.status', () {
    test('compliant when worked meets target and break requirement', () {
      final day = DayCompliance(
        date: DateTime(2026, 7, 6),
        workedMinutes: 480,
        targetMinutes: 480,
        maxMinutes: null,
        breakTakenMinutes: 30,
        breakRequiredMinutes: 30,
        isException: false,
      );
      expect(day.status, DayComplianceStatus.compliant);
    });

    test('violation when worked is below target', () {
      final day = DayCompliance(
        date: DateTime(2026, 7, 6),
        workedMinutes: 300,
        targetMinutes: 480,
        maxMinutes: null,
        breakTakenMinutes: 0,
        breakRequiredMinutes: 0,
        isException: false,
      );
      expect(day.status, DayComplianceStatus.violation);
    });

    test('violation when worked exceeds the configured maximum', () {
      final day = DayCompliance(
        date: DateTime(2026, 7, 6),
        workedMinutes: 700,
        targetMinutes: 480,
        maxMinutes: 600,
        breakTakenMinutes: 30,
        breakRequiredMinutes: 30,
        isException: false,
      );
      expect(day.status, DayComplianceStatus.violation);
    });

    test('violation when the break taken is short of what is required', () {
      final day = DayCompliance(
        date: DateTime(2026, 7, 6),
        workedMinutes: 480,
        targetMinutes: 0,
        maxMinutes: null,
        breakTakenMinutes: 10,
        breakRequiredMinutes: 30,
        isException: false,
      );
      expect(day.status, DayComplianceStatus.violation);
    });

    test('exception day is never a violation, regardless of worked/break minutes', () {
      final day = DayCompliance(
        date: DateTime(2026, 7, 6),
        workedMinutes: 0,
        targetMinutes: 0,
        maxMinutes: 480,
        breakTakenMinutes: 0,
        breakRequiredMinutes: 0,
        isException: true,
      );
      expect(day.status, DayComplianceStatus.exception);
    });

    test('a day with no rules configured and no work is noRule, not violation', () {
      final day = DayCompliance(
        date: DateTime(2026, 7, 6),
        workedMinutes: 0,
        targetMinutes: 0,
        maxMinutes: null,
        breakTakenMinutes: 0,
        breakRequiredMinutes: 0,
        isException: false,
      );
      expect(day.status, DayComplianceStatus.noRule);
    });
  });

  group('dayCompliancesInRange', () {
    test('an exception day suspends the daily target and maximum', () {
      final results = dayCompliancesInRange(
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 7),
        entries: const [],
        settings: _settings(mon: 480, maxDailyMinutes: 600),
        breakTiers: const [],
        exceptions: [
          DayException(
            id: 'x1',
            date: DateTime(2026, 7, 6),
            type: 'holiday',
            note: null,
            deviceId: 'dev_a',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(results, hasLength(1));
      expect(results.single.targetMinutes, 0);
      expect(results.single.maxMinutes, isNull);
      expect(results.single.status, DayComplianceStatus.exception);
    });

    test('one entry produces correct per-day results across a 2-day range', () {
      final results = dayCompliancesInRange(
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 8),
        entries: [
          _entry(startAt: DateTime.utc(2026, 7, 6, 9), endAt: DateTime.utc(2026, 7, 6, 17)),
        ],
        settings: _settings(mon: 480),
        breakTiers: const [],
        exceptions: const [],
      );
      expect(results, hasLength(2));
      expect(results[0].workedMinutes, 480);
      expect(results[1].workedMinutes, 0);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/calendar/day_compliance_test.dart`
Expected: FAIL — `day_compliance.dart` doesn't exist yet.

- [ ] **Step 3: Implement the calculation module**

Create `lib/features/calendar/day_compliance.dart`:

```dart
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';

enum DayComplianceStatus { compliant, violation, exception, noRule }

/// One local calendar day's compliance inputs and evaluated status. Pure
/// data — no DB/Flutter dependency, straightforward to unit test.
class DayCompliance {
  const DayCompliance({
    required this.date,
    required this.workedMinutes,
    required this.targetMinutes,
    required this.maxMinutes,
    required this.breakTakenMinutes,
    required this.breakRequiredMinutes,
    required this.isException,
  });

  /// Local midnight for this day.
  final DateTime date;
  final int workedMinutes;
  /// 0 means "no minimum configured for this day" (free weekday or
  /// exception day) — never a violation on its own.
  final int targetMinutes;
  /// Null means "no maximum configured".
  final int? maxMinutes;
  final int breakTakenMinutes;
  /// 0 means "no break tier applies".
  final int breakRequiredMinutes;
  final bool isException;

  bool get meetsMinimum => isException || targetMinutes == 0 || workedMinutes >= targetMinutes;
  bool get exceedsMaximum => !isException && maxMinutes != null && workedMinutes > maxMinutes!;
  bool get meetsBreakRequirement =>
      isException || breakRequiredMinutes == 0 || breakTakenMinutes >= breakRequiredMinutes;

  DayComplianceStatus get status {
    if (isException) return DayComplianceStatus.exception;
    final noRulesConfigured = targetMinutes == 0 && maxMinutes == null && breakRequiredMinutes == 0;
    if (noRulesConfigured) return DayComplianceStatus.noRule;
    if (!meetsMinimum || exceedsMaximum || !meetsBreakRequirement) {
      return DayComplianceStatus.violation;
    }
    return DayComplianceStatus.compliant;
  }
}

/// Worked minutes per local calendar day. An entry crossing midnight is
/// split proportionally between the two days it touches (e.g. 23:00–01:00
/// contributes 60 minutes to each day) rather than being attributed
/// entirely to its start day.
Map<DateTime, int> dailyWorkedMinutes(List<TimeEntry> entries) {
  final totals = <DateTime, int>{};
  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final start = entry.startAt.toLocal();
    final end = start.add(entry.workedDuration);
    var cursor = start;
    while (cursor.isBefore(end)) {
      final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
      final nextDayStart = dayStart.add(const Duration(days: 1));
      final segmentEnd = end.isBefore(nextDayStart) ? end : nextDayStart;
      final minutes = segmentEnd.difference(cursor).inMinutes;
      totals.update(dayStart, (existing) => existing + minutes, ifAbsent: () => minutes);
      cursor = segmentEnd;
    }
  }
  return totals;
}

/// Sum of gaps between entries that both end and start within the same
/// local calendar day. The gap to the next day's first entry (an overnight
/// gap) is deliberately never counted here — see
/// docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md for
/// why, and how a future rest-time rule could reuse it.
Map<DateTime, int> dailyBreakMinutes(List<TimeEntry> entries) {
  final finished = entries.where((e) => e.endAt != null).toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  final totals = <DateTime, int>{};
  for (var i = 0; i < finished.length - 1; i++) {
    final currentEnd = finished[i].endAt!.toLocal();
    final nextStart = finished[i + 1].startAt.toLocal();
    final currentDay = DateTime(currentEnd.year, currentEnd.month, currentEnd.day);
    final nextDay = DateTime(nextStart.year, nextStart.month, nextStart.day);
    if (currentDay != nextDay) continue;
    final gapMinutes = nextStart.difference(currentEnd).inMinutes;
    if (gapMinutes <= 0) continue;
    totals.update(currentDay, (existing) => existing + gapMinutes, ifAbsent: () => gapMinutes);
  }
  return totals;
}

/// The break-minutes requirement for a day with [workedMinutes], per
/// [tiers]: the tier with the highest `afterMinutes` that `workedMinutes`
/// has reached. 0 if no tier applies.
int requiredBreakMinutesFor(int workedMinutes, List<BreakRuleTier> tiers) {
  BreakRuleTier? best;
  for (final tier in tiers) {
    if (workedMinutes < tier.afterMinutes) continue;
    if (best == null || tier.afterMinutes > best.afterMinutes) best = tier;
  }
  return best?.requiredBreakMinutes ?? 0;
}

/// [weekday] uses `DateTime.weekday` numbering (1 = Monday … 7 = Sunday).
int targetMinutesForWeekday(AppSettingsRow settings, int weekday) {
  return switch (weekday) {
    DateTime.monday => settings.targetMinutesMonday,
    DateTime.tuesday => settings.targetMinutesTuesday,
    DateTime.wednesday => settings.targetMinutesWednesday,
    DateTime.thursday => settings.targetMinutesThursday,
    DateTime.friday => settings.targetMinutesFriday,
    DateTime.saturday => settings.targetMinutesSaturday,
    DateTime.sunday => settings.targetMinutesSunday,
    _ => throw ArgumentError('Invalid weekday: $weekday'),
  };
}

/// Builds one [DayCompliance] per local day in `[start, end)`.
List<DayCompliance> dayCompliancesInRange({
  required DateTime start,
  required DateTime end,
  required List<TimeEntry> entries,
  required AppSettingsRow settings,
  required List<BreakRuleTier> breakTiers,
  required List<DayException> exceptions,
}) {
  final worked = dailyWorkedMinutes(entries);
  final breaks = dailyBreakMinutes(entries);
  final exceptionByDate = {
    for (final e in exceptions) DateTime(e.date.year, e.date.month, e.date.day): e,
  };

  final result = <DayCompliance>[];
  for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
    final isException = exceptionByDate.containsKey(day);
    final workedMinutes = worked[day] ?? 0;
    result.add(
      DayCompliance(
        date: day,
        workedMinutes: workedMinutes,
        targetMinutes: isException ? 0 : targetMinutesForWeekday(settings, day.weekday),
        maxMinutes: isException ? null : settings.maxDailyMinutes,
        breakTakenMinutes: breaks[day] ?? 0,
        breakRequiredMinutes: isException ? 0 : requiredBreakMinutesFor(workedMinutes, breakTiers),
        isException: isException,
      ),
    );
  }
  return result;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/calendar/day_compliance_test.dart`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/day_compliance.dart test/features/calendar/day_compliance_test.dart
git commit -m "feat(calendar): add day-level compliance calculation module"
```

---
### Task 9: Period totals and running balance calculations (pure Dart)

**Files:**
- Create: `lib/features/calendar/period_compliance.dart`
- Test: `test/features/calendar/period_compliance_test.dart`

**Interfaces:**
- Consumes: `DayCompliance` (Task 8), `BalanceAdjustment` (Task 6).
- Produces: `class PeriodTotals` with fields `workedMinutes`, `targetMinutes` and getter `differenceMinutes`; functions `periodTotals(List<DayCompliance>)` and `runningBalanceMinutes({required allDaysUpToDate, required adjustments})`. Used by Task 10.

- [ ] **Step 1: Write the failing tests**

Create `test/features/calendar/period_compliance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/calendar/day_compliance.dart';
import 'package:hickory/features/calendar/period_compliance.dart';

DayCompliance _day({required DateTime date, required int worked, required int target}) {
  return DayCompliance(
    date: date,
    workedMinutes: worked,
    targetMinutes: target,
    maxMinutes: null,
    breakTakenMinutes: 0,
    breakRequiredMinutes: 0,
    isException: false,
  );
}

BalanceAdjustment _adjustment({required DateTime date, required int deltaMinutes}) {
  return BalanceAdjustment(
    id: 'a_${date.toIso8601String()}',
    date: date,
    deltaMinutes: deltaMinutes,
    note: null,
    deviceId: 'dev_a',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  group('periodTotals', () {
    test('sums worked and target minutes across days', () {
      final days = [
        _day(date: DateTime(2026, 7, 6), worked: 480, target: 480),
        _day(date: DateTime(2026, 7, 7), worked: 300, target: 480),
      ];
      final totals = periodTotals(days);
      expect(totals.workedMinutes, 780);
      expect(totals.targetMinutes, 960);
      expect(totals.differenceMinutes, -180);
    });

    test('an empty list totals to zero', () {
      final totals = periodTotals(const []);
      expect(totals.workedMinutes, 0);
      expect(totals.targetMinutes, 0);
      expect(totals.differenceMinutes, 0);
    });
  });

  group('runningBalanceMinutes', () {
    test('is the sum of day differences plus adjustment deltas', () {
      final days = [
        _day(date: DateTime(2026, 7, 6), worked: 540, target: 480), // +60
        _day(date: DateTime(2026, 7, 7), worked: 420, target: 480), // -60
      ];
      final adjustments = [
        _adjustment(date: DateTime(2026, 7, 1), deltaMinutes: 30),
      ];
      expect(
        runningBalanceMinutes(allDaysUpToDate: days, adjustments: adjustments),
        30,
      );
    });

    test('a year-end reset adjustment brings a positive balance back to zero', () {
      final days = [
        _day(date: DateTime(2026, 12, 30), worked: 600, target: 480), // +120
      ];
      final adjustments = [
        _adjustment(date: DateTime(2026, 12, 31), deltaMinutes: -120),
      ];
      expect(
        runningBalanceMinutes(allDaysUpToDate: days, adjustments: adjustments),
        0,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/calendar/period_compliance_test.dart`
Expected: FAIL — `period_compliance.dart` doesn't exist yet.

- [ ] **Step 3: Implement the calculation module**

Create `lib/features/calendar/period_compliance.dart`:

```dart
import '../../data/drift/database.dart';
import 'day_compliance.dart';

/// Worked vs. target minutes summed across a set of days (a week, a month,
/// or any other range of [DayCompliance] values).
class PeriodTotals {
  const PeriodTotals({required this.workedMinutes, required this.targetMinutes});

  final int workedMinutes;
  final int targetMinutes;

  int get differenceMinutes => workedMinutes - targetMinutes;
}

/// Sums worked vs. target minutes across [days] — target is already 0 for
/// exception days, per [DayCompliance.targetMinutes], so no separate
/// exception handling is needed here.
PeriodTotals periodTotals(List<DayCompliance> days) {
  var worked = 0;
  var target = 0;
  for (final day in days) {
    worked += day.workedMinutes;
    target += day.targetMinutes;
  }
  return PeriodTotals(workedMinutes: worked, targetMinutes: target);
}

/// The running overtime/undertime balance, in minutes, as of the end of
/// [allDaysUpToDate]'s range: the cumulative (worked - target) across every
/// one of those days, plus every adjustment in [adjustments] (the caller is
/// responsible for only passing adjustments dated on or before that date).
///
/// [allDaysUpToDate] is expected to span from account start to the target
/// date, not just the visible period — the caller building that list (see
/// `currentBalanceMinutesProvider`) iterates one [DayCompliance] per
/// calendar day in that whole span, which is cheap per-day but still grows
/// with how far back the range starts. Acceptable at personal-time-tracking
/// scale (a "since 2000" fixed floor is a few thousand cheap iterations,
/// not millions); revisit if that stops being true.
int runningBalanceMinutes({
  required List<DayCompliance> allDaysUpToDate,
  required List<BalanceAdjustment> adjustments,
}) {
  final dayTotal = periodTotals(allDaysUpToDate).differenceMinutes;
  final adjustmentTotal = adjustments.fold<int>(0, (sum, a) => sum + a.deltaMinutes);
  return dayTotal + adjustmentTotal;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/calendar/period_compliance_test.dart`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/period_compliance.dart test/features/calendar/period_compliance_test.dart
git commit -m "feat(calendar): add period totals and running balance calculation"
```

---
### Task 10: Calendar Riverpod providers

**Files:**
- Create: `lib/features/calendar/calendar_providers.dart`
- Test: `test/features/calendar/calendar_providers_test.dart`

**Interfaces:**
- Consumes: `appDatabaseProvider` (`lib/core/di/database_provider.dart`), `dayCompliancesInRange`/`DayCompliance` (Task 8), `periodTotals`/`runningBalanceMinutes`/`PeriodTotals` (Task 9), `BreakRuleTiersDao`/`DayExceptionsDao`/`BalanceAdjustmentsDao`/`TimeEntriesDao`/`AppSettingsDao` (Tasks 1–6).
- Produces: `breakRuleTiersProvider` (`StreamProvider<List<BreakRuleTier>>`), `dayExceptionsProvider` (`StreamProvider.family<List<DayException>, DateTimeRange>`), `dayExceptionForDateProvider` (`FutureProvider.family<DayException?, DateTime>`), `balanceAdjustmentsProvider` (`StreamProvider<List<BalanceAdjustment>>`), `monthDayCompliancesProvider` (`FutureProvider.family<List<DayCompliance>, DateTime>`, keyed by any date within the target month), `currentBalanceMinutesProvider` (`FutureProvider.family<int, DateTime>`, keyed by the "as of" date). Used by Tasks 12–16.

- [ ] **Step 1: Write the providers**

Create `lib/features/calendar/calendar_providers.dart`:

```dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';
import 'day_compliance.dart';
import 'period_compliance.dart';

// Plain (non-generated) providers — see reports_providers.dart / timer_providers.dart
// for why @riverpod codegen is avoided for providers whose type touches
// drift's generated classes in this codebase (rrousselGit/riverpod#4323).

final breakRuleTiersProvider = StreamProvider<List<BreakRuleTier>>((ref) {
  return ref.watch(appDatabaseProvider).breakRuleTiersDao.watchAllTiers();
});

final dayExceptionsProvider = StreamProvider.family<List<DayException>, DateTimeRange>((ref, range) {
  return ref
      .watch(appDatabaseProvider)
      .dayExceptionsDao
      .watchExceptionsInRange(range.start, range.end);
});

final dayExceptionForDateProvider = FutureProvider.family<DayException?, DateTime>((ref, date) {
  return ref.watch(appDatabaseProvider).dayExceptionsDao.getForDate(date);
});

final balanceAdjustmentsProvider = StreamProvider<List<BalanceAdjustment>>((ref) {
  return ref.watch(appDatabaseProvider).balanceAdjustmentsDao.watchAllAdjustments();
});

/// [month] may be any date within the target month — only its year/month
/// are used, so callers can pass e.g. the first day of the month without
/// worrying about matching exactly.
final monthDayCompliancesProvider = FutureProvider.family<List<DayCompliance>, DateTime>((
  ref,
  month,
) async {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);
  final db = ref.watch(appDatabaseProvider);

  final entries = await db.timeEntriesDao.watchEntriesInRange(start.toUtc(), end.toUtc()).first;
  final settings = await db.appSettingsDao.watchSettings().first;
  final tiers = await ref.watch(breakRuleTiersProvider.future);
  final exceptions = await ref.watch(
    dayExceptionsProvider(DateTimeRange(start: start, end: end)).future,
  );

  return dayCompliancesInRange(
    start: start,
    end: end,
    entries: entries,
    settings: settings,
    breakTiers: tiers,
    exceptions: exceptions,
  );
});

/// The running balance as of the end of [asOf]'s day. Scans every entry the
/// account has ever recorded (see [runningBalanceMinutes]'s doc comment for
/// why that's an accepted tradeoff here) — `DateTime(2000)` as the range
/// floor matches the existing "beginning of time" sentinel already used by
/// `ReportRangePreset.all` in reports_providers.dart.
final currentBalanceMinutesProvider = FutureProvider.family<int, DateTime>((ref, asOf) async {
  final end = DateTime(asOf.year, asOf.month, asOf.day).add(const Duration(days: 1));
  final db = ref.watch(appDatabaseProvider);

  final entries = await db.timeEntriesDao.getAllEntries();
  final settings = await db.appSettingsDao.watchSettings().first;
  final tiers = await ref.watch(breakRuleTiersProvider.future);
  final exceptions = await db.dayExceptionsDao.watchExceptionsInRange(DateTime(2000), end).first;

  final days = dayCompliancesInRange(
    start: DateTime(2000),
    end: end,
    entries: entries.where((e) => e.startAt.isBefore(end.toUtc())).toList(),
    settings: settings,
    breakTiers: tiers,
    exceptions: exceptions,
  );
  final adjustments = await ref.watch(balanceAdjustmentsProvider.future);

  return runningBalanceMinutes(
    allDaysUpToDate: days,
    adjustments: adjustments.where((a) => !a.date.isAfter(end)).toList(),
  );
});
```

- [ ] **Step 2: Write a provider-wiring test**

Create `test/features/calendar/calendar_providers_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/calendar/calendar_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('monthDayCompliancesProvider reflects a manual entry and a configured target', () async {
    await db.appSettingsDao.updateSettings(targetMinutesMonday: 480);
    await db.timeEntriesDao.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 6, 9), // a Monday
      endAt: DateTime.utc(2026, 7, 6, 17),
    );

    final days = await container.read(monthDayCompliancesProvider(DateTime(2026, 7, 1)).future);

    final monday = days.singleWhere((d) => d.date == DateTime(2026, 7, 6));
    expect(monday.workedMinutes, 480);
    expect(monday.targetMinutes, 480);
    expect(monday.status.name, 'compliant');
  });

  test('currentBalanceMinutesProvider includes both worked-vs-target and manual adjustments', () async {
    await db.appSettingsDao.updateSettings(targetMinutesMonday: 480);
    await db.timeEntriesDao.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 6, 9),
      endAt: DateTime.utc(2026, 7, 6, 18), // 9h worked vs. 8h target: +60
    );
    await db.balanceAdjustmentsDao.createAdjustment(
      deviceId: 'dev_a',
      date: DateTime.utc(2026, 7, 6),
      deltaMinutes: -30,
    );

    final balance = await container.read(currentBalanceMinutesProvider(DateTime(2026, 7, 6)).future);
    expect(balance, 30);
  });
}
```

- [ ] **Step 3: Run the test**

Run: `flutter test test/features/calendar/calendar_providers_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/features/calendar/calendar_providers.dart test/features/calendar/calendar_providers_test.dart
git commit -m "feat(calendar): wire compliance calculations into Riverpod providers"
```

---

### Task 11: Free window resizing with local-only geometry persistence

**Files:**
- Create: `lib/core/window/window_geometry_store.dart`
- Modify: `lib/core/window/window_tray_controller.dart`
- Test: `test/core/window/window_geometry_store_test.dart`

**Interfaces:**
- Produces: `WindowGeometryStore` with `read()` (`Future<Rect?>`) and `write(Rect bounds)` (`Future<void>`), same constructor-injected-directory pattern as `BackgroundNoticeStore`/`LocaleStore`. `WindowTrayController` becomes resizable with no maximum size, restores/persists its bounds across launches.

- [ ] **Step 1: Write the failing store tests**

Create `test/core/window/window_geometry_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_geometry_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_geometry_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('read returns null when nothing has been written', () async {
    final store = WindowGeometryStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });

  test('write then read round-trips the bounds, including across instances', () async {
    final store = WindowGeometryStore(supportDirectory: tempDir);
    const bounds = Rect.fromLTWH(100, 50, 900, 700);
    await store.write(bounds);

    expect(await store.read(), bounds);
    final freshStore = WindowGeometryStore(supportDirectory: tempDir);
    expect(await freshStore.read(), bounds);
  });

  test('read returns null for a corrupt file instead of throwing', () async {
    final file = File('${tempDir.path}/window_geometry.json');
    await file.create(recursive: true);
    await file.writeAsString('not json');

    final store = WindowGeometryStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/window/window_geometry_store_test.dart`
Expected: FAIL — `window_geometry_store.dart` doesn't exist yet.

- [ ] **Step 3: Implement `WindowGeometryStore`**

Create `lib/core/window/window_geometry_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Rect;
import 'package:path/path.dart' as p;

/// Persists the window's last size/position as a small local JSON file
/// (same pattern as [LocaleStore]/[BackgroundNoticeStore]) so it can be
/// restored on the next launch. Deliberately local-only — window geometry
/// is a per-device UI preference, never written to the synced event log.
/// Takes the directory as a constructor parameter so tests can point it at
/// a temp dir — the real caller passes
/// `await getApplicationSupportDirectory()`.
class WindowGeometryStore {
  WindowGeometryStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _file => File(p.join(supportDirectory.path, 'window_geometry.json'));

  /// Returns the stored bounds, or null if absent, unreadable, or corrupt
  /// (falls back to the default window placement rather than crash).
  Future<Rect?> read() async {
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final x = decoded['x'];
    final y = decoded['y'];
    final width = decoded['width'];
    final height = decoded['height'];
    if (x is! num || y is! num || width is! num || height is! num) return null;
    return Rect.fromLTWH(x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble());
  }

  Future<void> write(Rect bounds) async {
    await _file.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      }),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/window/window_geometry_store_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Wire geometry restore/persist into `WindowTrayController`**

Edit `lib/core/window/window_tray_controller.dart`. Add the import:

```dart
import 'window_geometry_store.dart';
```

Rename `_windowSize` to `_minimumSize` (it's now only a floor, not a fixed size) and update `initialize()`:

```dart
  static const _minimumSize = Size(400, 800);
```

Replace the body of `initialize()` from the start through the end of the `waitUntilReadyToShow` call:

```dart
  Future<void> initialize() async {
    windowManager.addListener(this);
    trayManager.addListener(this);

    await windowManager.ensureInitialized();

    final savedBounds = await (await _geometryStore()).read();

    // Deliberately not awaited: per window_manager's documented pattern,
    // this runs concurrently with Flutter building its first frame (which
    // only starts once `runApp` is called back in `main()`, after this
    // whole `initialize()` future completes). Awaiting it here would show
    // the native window before Flutter has anything to render into it,
    // producing a blank white window until the next paint is triggered.
    unawaited(
      windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: savedBounds?.size ?? _minimumSize,
          center: savedBounds == null,
          title: 'Hickory',
        ),
        () async {
          await windowManager.setResizable(true);
          await windowManager.setMinimumSize(_minimumSize);
          await windowManager.setPreventClose(true);
          await windowManager.show();
          if (savedBounds != null) {
            await windowManager.setPosition(savedBounds.topLeft);
          }
          await windowManager.focus();
        },
      ),
    );

    await trayManager.setIcon(
      defaultTargetPlatform == TargetPlatform.windows
          ? 'windows/runner/resources/app_icon.ico'
          : 'assets/tray_icon.png',
    );
    await trayManager.setToolTip('Hickory');
    await updateContextMenu();
  }

  Future<WindowGeometryStore> _geometryStore() async {
    return WindowGeometryStore(supportDirectory: await getApplicationSupportDirectory());
  }

  Future<void> _persistGeometry() async {
    final bounds = await windowManager.getBounds();
    await (await _geometryStore()).write(bounds);
  }
```

Add two new `WindowListener` overrides, next to the existing `onWindowClose`/`onWindowMinimize` overrides:

```dart
  @override
  void onWindowResized() {
    _persistGeometry();
  }

  @override
  void onWindowMoved() {
    _persistGeometry();
  }
```

Note `WindowOptions(size: ..., center: ..., title: 'Hickory')` above drops the old fixed `size: _windowSize` literal and the `setMaximumSize` call entirely — there is no maximum anymore.

- [ ] **Step 6: Manually verify on the target platform**

Run: `flutter run -d windows` (or `-d macos`)
Expected: the window opens at its default (or last-saved) size, can be freely dragged by any edge to resize (down to the 400×800 floor, no upper limit), and reopening the app after resizing/moving it restores the same size and position.

- [ ] **Step 7: Commit**

```bash
git add lib/core/window/window_geometry_store.dart lib/core/window/window_tray_controller.dart test/core/window/window_geometry_store_test.dart
git commit -m "feat(window): allow free resizing with locally persisted geometry"
```

---
### Task 12: Settings UI — "Work-Time Rules" section

**Files:**
- Create: `lib/features/settings/work_rules_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/features/settings/work_rules_section_test.dart`

**Interfaces:**
- Consumes: `appSettingsProvider` (`lib/core/di/app_settings_provider.dart`), `breakRuleTiersProvider` (Task 10), `syncedWritesProvider`/`deviceIdProvider` (`lib/core/di/`).
- Produces: `WorkRulesSection` widget, embedded into `SettingsScreen`.

- [ ] **Step 1: Add the ARB keys**

Edit `lib/l10n/app_de.arb`, adding these entries (anywhere among the existing keys, e.g. after `settingsTimeFormat`):

```json
  "settingsWorkRulesTitle": "Arbeitszeitregeln",
  "settingsWorkRulesTargetHoursLabel": "Sollstunden",
  "settingsWorkRulesMaxDailyLabel": "Höchstarbeitszeit pro Tag (Stunden)",
  "settingsWorkRulesMaxDailyNone": "Keine Begrenzung",
  "settingsWorkRulesBreakTiersTitle": "Pausenregeln",
  "settingsWorkRulesBreakTierAfterLabel": "Ab (Stunden)",
  "settingsWorkRulesBreakTierRequiredLabel": "Pflichtpause (Minuten)",
  "settingsWorkRulesAddBreakTierButton": "Pausenstufe hinzufügen",
  "settingsWorkRulesRemoveBreakTierTooltip": "Entfernen",
```

Edit `lib/l10n/app_en.arb`:

```json
  "settingsWorkRulesTitle": "Work-time rules",
  "settingsWorkRulesTargetHoursLabel": "Target hours",
  "settingsWorkRulesMaxDailyLabel": "Maximum work time per day (hours)",
  "settingsWorkRulesMaxDailyNone": "No limit",
  "settingsWorkRulesBreakTiersTitle": "Break rules",
  "settingsWorkRulesBreakTierAfterLabel": "After (hours)",
  "settingsWorkRulesBreakTierRequiredLabel": "Required break (minutes)",
  "settingsWorkRulesAddBreakTierButton": "Add break tier",
  "settingsWorkRulesRemoveBreakTierTooltip": "Remove",
```

Edit `lib/l10n/app_es.arb`:

```json
  "settingsWorkRulesTitle": "Reglas de horario laboral",
  "settingsWorkRulesTargetHoursLabel": "Horas objetivo",
  "settingsWorkRulesMaxDailyLabel": "Tiempo máximo de trabajo por día (horas)",
  "settingsWorkRulesMaxDailyNone": "Sin límite",
  "settingsWorkRulesBreakTiersTitle": "Reglas de descanso",
  "settingsWorkRulesBreakTierAfterLabel": "A partir de (horas)",
  "settingsWorkRulesBreakTierRequiredLabel": "Descanso obligatorio (minutos)",
  "settingsWorkRulesAddBreakTierButton": "Añadir nivel de descanso",
  "settingsWorkRulesRemoveBreakTierTooltip": "Quitar",
```

Edit `lib/l10n/app_fr.arb`:

```json
  "settingsWorkRulesTitle": "Règles de temps de travail",
  "settingsWorkRulesTargetHoursLabel": "Heures cibles",
  "settingsWorkRulesMaxDailyLabel": "Temps de travail maximal par jour (heures)",
  "settingsWorkRulesMaxDailyNone": "Aucune limite",
  "settingsWorkRulesBreakTiersTitle": "Règles de pause",
  "settingsWorkRulesBreakTierAfterLabel": "À partir de (heures)",
  "settingsWorkRulesBreakTierRequiredLabel": "Pause obligatoire (minutes)",
  "settingsWorkRulesAddBreakTierButton": "Ajouter un palier de pause",
  "settingsWorkRulesRemoveBreakTierTooltip": "Supprimer",
```

Edit `lib/l10n/app_it.arb`:

```json
  "settingsWorkRulesTitle": "Regole orario di lavoro",
  "settingsWorkRulesTargetHoursLabel": "Ore obiettivo",
  "settingsWorkRulesMaxDailyLabel": "Tempo massimo di lavoro al giorno (ore)",
  "settingsWorkRulesMaxDailyNone": "Nessun limite",
  "settingsWorkRulesBreakTiersTitle": "Regole delle pause",
  "settingsWorkRulesBreakTierAfterLabel": "Dopo (ore)",
  "settingsWorkRulesBreakTierRequiredLabel": "Pausa obbligatoria (minuti)",
  "settingsWorkRulesAddBreakTierButton": "Aggiungi livello di pausa",
  "settingsWorkRulesRemoveBreakTierTooltip": "Rimuovi",
```

Edit `lib/l10n/app_nl.arb`:

```json
  "settingsWorkRulesTitle": "Werktijdregels",
  "settingsWorkRulesTargetHoursLabel": "Doeluren",
  "settingsWorkRulesMaxDailyLabel": "Maximale werktijd per dag (uren)",
  "settingsWorkRulesMaxDailyNone": "Geen limiet",
  "settingsWorkRulesBreakTiersTitle": "Pauzeregels",
  "settingsWorkRulesBreakTierAfterLabel": "Vanaf (uur)",
  "settingsWorkRulesBreakTierRequiredLabel": "Verplichte pauze (minuten)",
  "settingsWorkRulesAddBreakTierButton": "Pauzeniveau toevoegen",
  "settingsWorkRulesRemoveBreakTierTooltip": "Verwijderen",
```

- [ ] **Step 2: Run the ARB completeness test**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes with no errors; `lib/l10n/app_localizations*.dart` are regenerated with the new getters.

- [ ] **Step 4: Implement `WorkRulesSection`**

Create `lib/features/settings/work_rules_section.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import '../calendar/calendar_providers.dart';

const _weekdays = [
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
  DateTime.sunday,
];

/// A Card, matching the other sections on SettingsScreen, for configuring
/// the international-and-user-defined work-time rules the Calendar tab
/// evaluates: a target-hours field per weekday (0/empty = not a work day),
/// an optional daily maximum, and an editable list of tiered break-time
/// requirements. Saves immediately per field (no separate Save button),
/// matching this screen's existing date/time format dropdowns.
class WorkRulesSection extends ConsumerStatefulWidget {
  const WorkRulesSection({super.key});

  @override
  ConsumerState<WorkRulesSection> createState() => _WorkRulesSectionState();
}

class _WorkRulesSectionState extends ConsumerState<WorkRulesSection> {
  final _weekdayControllers = {for (final w in _weekdays) w: TextEditingController()};
  final _maxDailyController = TextEditingController();
  final _tierAfterController = TextEditingController();
  final _tierRequiredController = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    for (final c in _weekdayControllers.values) {
      c.dispose();
    }
    _maxDailyController.dispose();
    _tierAfterController.dispose();
    _tierRequiredController.dispose();
    super.dispose();
  }

  /// Fills the text fields from the current settings row exactly once —
  /// after that, the fields are the source of truth for what the user is
  /// typing, and must not be clobbered by the settings stream re-emitting
  /// the value this same widget just wrote.
  void _seedFromSettings(AppSettingsRow settings) {
    if (_seeded) return;
    _seeded = true;
    _weekdayControllers[DateTime.monday]!.text = _hoursText(settings.targetMinutesMonday);
    _weekdayControllers[DateTime.tuesday]!.text = _hoursText(settings.targetMinutesTuesday);
    _weekdayControllers[DateTime.wednesday]!.text = _hoursText(settings.targetMinutesWednesday);
    _weekdayControllers[DateTime.thursday]!.text = _hoursText(settings.targetMinutesThursday);
    _weekdayControllers[DateTime.friday]!.text = _hoursText(settings.targetMinutesFriday);
    _weekdayControllers[DateTime.saturday]!.text = _hoursText(settings.targetMinutesSaturday);
    _weekdayControllers[DateTime.sunday]!.text = _hoursText(settings.targetMinutesSunday);
    _maxDailyController.text =
        settings.maxDailyMinutes == null ? '' : _hoursText(settings.maxDailyMinutes!);
  }

  String _hoursText(int minutes) => minutes == 0 ? '' : _formatHours(minutes / 60);

  String _formatHours(double hours) => hours == hours.roundToDouble()
      ? hours.toInt().toString()
      : hours.toString();

  int? _parseMinutes(String text) {
    if (text.trim().isEmpty) return 0;
    final hours = double.tryParse(text.trim().replaceAll(',', '.'));
    if (hours == null) return null;
    return (hours * 60).round();
  }

  Future<void> _saveWeekday(int weekday, String text) async {
    final minutes = _parseMinutes(text);
    if (minutes == null) return;
    final writes = await ref.read(syncedWritesProvider.future);
    switch (weekday) {
      case DateTime.monday:
        await writes.updateAppSettings(targetMinutesMonday: minutes);
      case DateTime.tuesday:
        await writes.updateAppSettings(targetMinutesTuesday: minutes);
      case DateTime.wednesday:
        await writes.updateAppSettings(targetMinutesWednesday: minutes);
      case DateTime.thursday:
        await writes.updateAppSettings(targetMinutesThursday: minutes);
      case DateTime.friday:
        await writes.updateAppSettings(targetMinutesFriday: minutes);
      case DateTime.saturday:
        await writes.updateAppSettings(targetMinutesSaturday: minutes);
      case DateTime.sunday:
        await writes.updateAppSettings(targetMinutesSunday: minutes);
    }
  }

  Future<void> _saveMaxDaily(String text) async {
    final writes = await ref.read(syncedWritesProvider.future);
    if (text.trim().isEmpty) {
      await writes.updateAppSettings(maxDailyMinutes: const Value(null));
      return;
    }
    final minutes = _parseMinutes(text);
    if (minutes == null) return;
    await writes.updateAppSettings(maxDailyMinutes: Value(minutes));
  }

  Future<void> _addBreakTier() async {
    final afterMinutes = _parseMinutes(_tierAfterController.text);
    final requiredMinutes = int.tryParse(_tierRequiredController.text.trim());
    if (afterMinutes == null || afterMinutes == 0 || requiredMinutes == null) return;

    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.createBreakRuleTier(
      deviceId: deviceId,
      afterMinutes: afterMinutes,
      requiredBreakMinutes: requiredMinutes,
    );
    _tierAfterController.clear();
    _tierRequiredController.clear();
  }

  Future<void> _removeBreakTier(String id) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.deleteBreakRuleTier(id);
  }

  /// `DateTime(1970, 1, 1)` was a Thursday (`DateTime.weekday == 4`);
  /// offsetting from there lands on the requested weekday regardless of
  /// year — `DateFormat.EEEE` only reads the day-of-week, so the specific
  /// date otherwise doesn't matter.
  String _weekdayLabel(int weekday, String localeName) {
    final reference = DateTime(1970, 1, 1).add(Duration(days: weekday - DateTime.thursday));
    return DateFormat.EEEE(localeName).format(reference);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).languageCode;
    final settingsAsync = ref.watch(appSettingsProvider);
    final tiersAsync = ref.watch(breakRuleTiersProvider);

    return settingsAsync.when(
      loading: () => const Card(
        child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      ),
      error: (error, _) =>
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$error'))),
      data: (settings) {
        _seedFromSettings(settings);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsWorkRulesTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final weekday in _weekdays)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 100, child: Text(_weekdayLabel(weekday, localeName))),
                        Expanded(
                          child: TextField(
                            controller: _weekdayControllers[weekday],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration:
                                InputDecoration(labelText: l10n.settingsWorkRulesTargetHoursLabel),
                            onSubmitted: (text) => _saveWeekday(weekday, text),
                            onTapOutside: (_) => _saveWeekday(weekday, _weekdayControllers[weekday]!.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _maxDailyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.settingsWorkRulesMaxDailyLabel,
                    hintText: l10n.settingsWorkRulesMaxDailyNone,
                  ),
                  onSubmitted: _saveMaxDaily,
                  onTapOutside: (_) => _saveMaxDaily(_maxDailyController.text),
                ),
                const SizedBox(height: 16),
                Text(l10n.settingsWorkRulesBreakTiersTitle, style: Theme.of(context).textTheme.titleSmall),
                tiersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('$error'),
                  data: (tiers) => Column(
                    children: [
                      for (final tier in tiers)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${tier.afterMinutes ~/ 60}h → ${tier.requiredBreakMinutes} min'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: l10n.settingsWorkRulesRemoveBreakTierTooltip,
                            onPressed: () => _removeBreakTier(tier.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tierAfterController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            InputDecoration(labelText: l10n.settingsWorkRulesBreakTierAfterLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _tierRequiredController,
                        keyboardType: TextInputType.number,
                        decoration:
                            InputDecoration(labelText: l10n.settingsWorkRulesBreakTierRequiredLabel),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: l10n.settingsWorkRulesAddBreakTierButton,
                      onPressed: _addBreakTier,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Embed the section in `SettingsScreen`**

Edit `lib/features/settings/settings_screen.dart`. Add the import:

```dart
import 'work_rules_section.dart';
```

Add `const SizedBox(height: 16)` and `const WorkRulesSection()` at the end of the `Column`'s `children:` list (after the existing date/time-format `Card`, before its closing `],`):

```dart
          ),
          const SizedBox(height: 16),
          const WorkRulesSection(),
        ],
      ),
    );
```

- [ ] **Step 6: Write the widget test**

Create `test/features/settings/work_rules_section_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/work_rules_section.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_work_rules_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'dev_a'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SingleChildScrollView(child: WorkRulesSection())),
        ),
      );

  testWidgets('shows the section title and Monday field starting empty', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Work-time rules'), findsOneWidget);
    final mondayField =
        tester.widget<TextField>(find.byType(TextField).first);
    expect(mondayField.controller!.text, '');
  });

  testWidgets('submitting an hours value for Monday persists it to AppSettings', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.targetMinutesMonday, 480);
  });
}
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/settings/work_rules_section_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/settings/work_rules_section.dart lib/features/settings/settings_screen.dart test/features/settings/work_rules_section_test.dart
git commit -m "feat(settings): add work-time rules section (targets, maximum, break tiers)"
```

---
### Task 13: Calendar month view and navigation entry

**Files:**
- Create: `lib/features/calendar/calendar_screen.dart`
- Create: `lib/features/calendar/month_view.dart`
- Modify: `lib/features/shell/app_shell.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/features/calendar/month_view_test.dart`

**Interfaces:**
- Consumes: `monthDayCompliancesProvider` (Task 10), `DayCompliance`/`DayComplianceStatus` (Task 8).
- Produces: `CalendarScreen` widget (wired into `AppShell` as a new tab), `MonthView({required DateTime month})` widget. Accessibility: every status is conveyed by icon *and* color together, never color alone.

- [ ] **Step 1: Add the ARB keys**

Edit `lib/l10n/app_de.arb`:

```json
  "navCalendar": "Kalender",
  "calendarTitle": "Kalender",
  "calendarPreviousPeriodTooltip": "Vorheriger Zeitraum",
  "calendarNextPeriodTooltip": "Nächster Zeitraum",
  "calendarStatusCompliantTooltip": "Regeln eingehalten",
  "calendarStatusViolationTooltip": "Regelverstoß",
  "calendarStatusExceptionTooltip": "Arbeitsfreier Tag",
```

Edit `lib/l10n/app_en.arb`:

```json
  "navCalendar": "Calendar",
  "calendarTitle": "Calendar",
  "calendarPreviousPeriodTooltip": "Previous period",
  "calendarNextPeriodTooltip": "Next period",
  "calendarStatusCompliantTooltip": "Rules met",
  "calendarStatusViolationTooltip": "Rule violation",
  "calendarStatusExceptionTooltip": "Day off",
```

Edit `lib/l10n/app_es.arb`:

```json
  "navCalendar": "Calendario",
  "calendarTitle": "Calendario",
  "calendarPreviousPeriodTooltip": "Periodo anterior",
  "calendarNextPeriodTooltip": "Periodo siguiente",
  "calendarStatusCompliantTooltip": "Reglas cumplidas",
  "calendarStatusViolationTooltip": "Infracción de regla",
  "calendarStatusExceptionTooltip": "Día libre",
```

Edit `lib/l10n/app_fr.arb`:

```json
  "navCalendar": "Calendrier",
  "calendarTitle": "Calendrier",
  "calendarPreviousPeriodTooltip": "Période précédente",
  "calendarNextPeriodTooltip": "Période suivante",
  "calendarStatusCompliantTooltip": "Règles respectées",
  "calendarStatusViolationTooltip": "Non-respect d'une règle",
  "calendarStatusExceptionTooltip": "Jour non travaillé",
```

Edit `lib/l10n/app_it.arb`:

```json
  "navCalendar": "Calendario",
  "calendarTitle": "Calendario",
  "calendarPreviousPeriodTooltip": "Periodo precedente",
  "calendarNextPeriodTooltip": "Periodo successivo",
  "calendarStatusCompliantTooltip": "Regole rispettate",
  "calendarStatusViolationTooltip": "Violazione della regola",
  "calendarStatusExceptionTooltip": "Giorno libero",
```

Edit `lib/l10n/app_nl.arb`:

```json
  "navCalendar": "Kalender",
  "calendarTitle": "Kalender",
  "calendarPreviousPeriodTooltip": "Vorige periode",
  "calendarNextPeriodTooltip": "Volgende periode",
  "calendarStatusCompliantTooltip": "Regels nageleefd",
  "calendarStatusViolationTooltip": "Regelovertreding",
  "calendarStatusExceptionTooltip": "Vrije dag",
```

- [ ] **Step 2: Run the ARB completeness test, then regenerate localizations**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

Run: `flutter gen-l10n`
Expected: completes with no errors.

- [ ] **Step 3: Implement `MonthView`**

Create `lib/features/calendar/month_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'calendar_providers.dart';
import 'day_compliance.dart';

/// A Monday-first month grid (matches this codebase's existing "this week"
/// convention in reports_providers.dart). Each day cell shows the date,
/// worked hours if any, and a status icon+color together — never color
/// alone, per the project's accessibility rules.
class MonthView extends ConsumerWidget {
  const MonthView({super.key, required this.month, this.onDayTap});

  final DateTime month;
  final void Function(DateTime date)? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compliancesAsync = ref.watch(monthDayCompliancesProvider(month));
    final localeName = Localizations.localeOf(context).languageCode;

    return compliancesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (compliances) {
        final byDay = {for (final c in compliances) c.date.day: c};
        final firstOfMonth = DateTime(month.year, month.month, 1);
        final leadingBlanks = firstOfMonth.weekday - DateTime.monday;
        final daysInMonth = compliances.length;

        return Column(
          children: [
            Row(
              children: [
                for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
                  Expanded(
                    child: Center(
                      child: Text(
                        _weekdayHeader(weekday, localeName),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
                itemCount: leadingBlanks + daysInMonth,
                itemBuilder: (context, index) {
                  final dayNumber = index - leadingBlanks + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox.shrink();
                  final compliance = byDay[dayNumber]!;
                  return _DayCell(compliance: compliance, onTap: onDayTap);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// See `WorkRulesSection._weekdayLabel` for why the reference date is
  /// arbitrary — only the day-of-week matters to `DateFormat`.
  String _weekdayHeader(int weekday, String localeName) {
    final reference = DateTime(1970, 1, 1).add(Duration(days: weekday - DateTime.thursday));
    return DateFormat.E(localeName).format(reference);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.compliance, required this.onTap});

  final DayCompliance compliance;
  final void Function(DateTime date)? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, tooltip) = switch (compliance.status) {
      DayComplianceStatus.compliant => (
          Icons.check_circle,
          colorScheme.tertiary,
          l10n.calendarStatusCompliantTooltip,
        ),
      DayComplianceStatus.violation => (
          Icons.error,
          colorScheme.error,
          l10n.calendarStatusViolationTooltip,
        ),
      DayComplianceStatus.exception => (
          Icons.beach_access,
          colorScheme.outline,
          l10n.calendarStatusExceptionTooltip,
        ),
      DayComplianceStatus.noRule => (null, null, null),
    };

    return InkWell(
      onTap: onTap == null ? null : () => onTap!(compliance.date),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${compliance.date.day}'),
                if (icon != null) Tooltip(message: tooltip!, child: Icon(icon, size: 14, color: color)),
              ],
            ),
            if (compliance.workedMinutes > 0)
              Text(
                '${(compliance.workedMinutes / 60).toStringAsFixed(1)}h',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `CalendarScreen`**

Create `lib/features/calendar/calendar_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'month_view.dart';

/// Hickory's Calendar tab: month navigation header plus the month grid.
/// (Task 15 adds a week-view toggle here; Task 16 adds the balance header.)
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _goToPreviousMonth() {
    setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1));
  }

  void _goToNextMonth() {
    setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).languageCode;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.calendarTitle, style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.calendarPreviousPeriodTooltip,
                onPressed: _goToPreviousMonth,
              ),
              Text(DateFormat.yMMMM(localeName).format(_focusedMonth)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.calendarNextPeriodTooltip,
                onPressed: _goToNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: MonthView(month: _focusedMonth)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the Calendar tab into `AppShell`**

Edit `lib/features/shell/app_shell.dart`. Add the import:

```dart
import '../calendar/calendar_screen.dart';
```

Insert a new `NavigationDestination` in `_destinations` between `navReports` and `navSync`:

```dart
    NavigationDestination(
      icon: const Icon(Icons.bar_chart_outlined),
      selectedIcon: const Icon(Icons.bar_chart),
      label: l10n.navReports,
    ),
    NavigationDestination(
      icon: const Icon(Icons.calendar_month_outlined),
      selectedIcon: const Icon(Icons.calendar_month),
      label: l10n.navCalendar,
    ),
    NavigationDestination(
      icon: const Icon(Icons.sync_outlined),
      selectedIcon: const Icon(Icons.sync),
      label: l10n.navSync,
    ),
```

Insert `const CalendarScreen()` into the `children:` list at the same position (between `ReportsScreen()` and `SyncScreen()`):

```dart
      children: const [TimerScreen(), ReportsScreen(), CalendarScreen(), SyncScreen(), SettingsScreen()],
```

The `fabBuilder`'s `selectedIndex == 0` check still targets Timer correctly — Timer stays index 0, only later tabs shift.

- [ ] **Step 6: Write the widget test**

Create `test/features/calendar/month_view_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/calendar/month_view.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget makeApp() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MonthView(month: DateTime(2026, 7, 1))),
        ),
      );

  testWidgets('renders 31 day cells for July 2026', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('31'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping a day cell invokes onDayTap with that date', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MonthView(month: DateTime(2026, 7, 1), onDayTap: (date) => tapped = date),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('15'));
    expect(tapped, DateTime(2026, 7, 15));
  });
}
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/calendar/month_view_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/calendar/calendar_screen.dart lib/features/calendar/month_view.dart lib/features/shell/app_shell.dart test/features/calendar/month_view_test.dart
git commit -m "feat(calendar): add month view and wire the Calendar tab into navigation"
```

---
### Task 14: Day detail dialog — breakdown and exception marking

**Files:**
- Modify: `lib/features/calendar/calendar_providers.dart`
- Create: `lib/features/calendar/day_detail_dialog.dart`
- Modify: `lib/features/calendar/calendar_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/features/calendar/day_detail_dialog_test.dart`

**Interfaces:**
- Consumes: `monthDayCompliancesProvider`, `dayExceptionForDateProvider` (Task 10), `DayExceptionTypes` (Task 4), `syncedWritesProvider`/`deviceIdProvider`.
- Produces: `dayEntriesProvider` (`StreamProvider.family<List<TimeEntry>, DateTime>`, added to `calendar_providers.dart`), `showDayDetailDialog(BuildContext context, DateTime date)`. `MonthView.onDayTap` (Task 13) is wired up in `CalendarScreen`.

- [ ] **Step 1: Add the ARB keys**

Edit `lib/l10n/app_de.arb`:

```json
  "commonClose": "Schließen",
  "calendarDayWorkedLabel": "Gearbeitet",
  "calendarDayTargetLabel": "Soll",
  "calendarDayBreakStatus": "{taken} von {required} Min. Pflichtpause",
  "@calendarDayBreakStatus": {
    "placeholders": { "taken": { "type": "int" }, "required": { "type": "int" } }
  },
  "calendarNoEntriesForDay": "Keine Einträge an diesem Tag",
  "calendarMarkExceptionButton": "Als arbeitsfrei markieren",
  "calendarRemoveExceptionButton": "Markierung entfernen",
  "calendarExceptionDialogTitle": "Tag als arbeitsfrei markieren",
  "calendarExceptionTypeHoliday": "Feiertag",
  "calendarExceptionTypeVacation": "Urlaub",
  "calendarExceptionTypeSick": "Krankheit",
  "calendarExceptionTypeCustom": "Sonstiges",
  "calendarExceptionNoteLabel": "Notiz (optional)",
```

Edit `lib/l10n/app_en.arb`:

```json
  "commonClose": "Close",
  "calendarDayWorkedLabel": "Worked",
  "calendarDayTargetLabel": "Target",
  "calendarDayBreakStatus": "{taken} of {required} min required break",
  "@calendarDayBreakStatus": {
    "placeholders": { "taken": { "type": "int" }, "required": { "type": "int" } }
  },
  "calendarNoEntriesForDay": "No entries on this day",
  "calendarMarkExceptionButton": "Mark as day off",
  "calendarRemoveExceptionButton": "Remove marking",
  "calendarExceptionDialogTitle": "Mark day as off",
  "calendarExceptionTypeHoliday": "Holiday",
  "calendarExceptionTypeVacation": "Vacation",
  "calendarExceptionTypeSick": "Sick leave",
  "calendarExceptionTypeCustom": "Other",
  "calendarExceptionNoteLabel": "Note (optional)",
```

Edit `lib/l10n/app_es.arb`:

```json
  "commonClose": "Cerrar",
  "calendarDayWorkedLabel": "Trabajado",
  "calendarDayTargetLabel": "Objetivo",
  "calendarDayBreakStatus": "{taken} de {required} min de descanso obligatorio",
  "@calendarDayBreakStatus": {
    "placeholders": { "taken": { "type": "int" }, "required": { "type": "int" } }
  },
  "calendarNoEntriesForDay": "Sin registros este día",
  "calendarMarkExceptionButton": "Marcar como día libre",
  "calendarRemoveExceptionButton": "Quitar marca",
  "calendarExceptionDialogTitle": "Marcar día como libre",
  "calendarExceptionTypeHoliday": "Festivo",
  "calendarExceptionTypeVacation": "Vacaciones",
  "calendarExceptionTypeSick": "Baja por enfermedad",
  "calendarExceptionTypeCustom": "Otro",
  "calendarExceptionNoteLabel": "Nota (opcional)",
```

Edit `lib/l10n/app_fr.arb`:

```json
  "commonClose": "Fermer",
  "calendarDayWorkedLabel": "Travaillé",
  "calendarDayTargetLabel": "Objectif",
  "calendarDayBreakStatus": "{taken} sur {required} min de pause obligatoire",
  "@calendarDayBreakStatus": {
    "placeholders": { "taken": { "type": "int" }, "required": { "type": "int" } }
  },
  "calendarNoEntriesForDay": "Aucune entrée ce jour-là",
  "calendarMarkExceptionButton": "Marquer comme jour non travaillé",
  "calendarRemoveExceptionButton": "Supprimer le marquage",
  "calendarExceptionDialogTitle": "Marquer le jour comme non travaillé",
  "calendarExceptionTypeHoliday": "Jour férié",
  "calendarExceptionTypeVacation": "Congés",
  "calendarExceptionTypeSick": "Congé maladie",
  "calendarExceptionTypeCustom": "Autre",
  "calendarExceptionNoteLabel": "Note (facultatif)",
```

Edit `lib/l10n/app_it.arb`:

```json
  "commonClose": "Chiudi",
  "calendarDayWorkedLabel": "Lavorato",
  "calendarDayTargetLabel": "Obiettivo",
  "calendarDayBreakStatus": "{taken} di {required} min di pausa obbligatoria",
  "@calendarDayBreakStatus": {
    "placeholders": { "taken": { "type": "int" }, "required": { "type": "int" } }
  },
  "calendarNoEntriesForDay": "Nessuna voce in questo giorno",
  "calendarMarkExceptionButton": "Segna come giorno libero",
  "calendarRemoveExceptionButton": "Rimuovi contrassegno",
  "calendarExceptionDialogTitle": "Segna il giorno come libero",
  "calendarExceptionTypeHoliday": "Festività",
  "calendarExceptionTypeVacation": "Ferie",
  "calendarExceptionTypeSick": "Malattia",
  "calendarExceptionTypeCustom": "Altro",
  "calendarExceptionNoteLabel": "Nota (facoltativa)",
```

Edit `lib/l10n/app_nl.arb`:

```json
  "commonClose": "Sluiten",
  "calendarDayWorkedLabel": "Gewerkt",
  "calendarDayTargetLabel": "Doel",
  "calendarDayBreakStatus": "{taken} van {required} min verplichte pauze",
  "@calendarDayBreakStatus": {
    "placeholders": { "taken": { "type": "int" }, "required": { "type": "int" } }
  },
  "calendarNoEntriesForDay": "Geen items op deze dag",
  "calendarMarkExceptionButton": "Markeren als vrije dag",
  "calendarRemoveExceptionButton": "Markering verwijderen",
  "calendarExceptionDialogTitle": "Dag markeren als vrij",
  "calendarExceptionTypeHoliday": "Feestdag",
  "calendarExceptionTypeVacation": "Vakantie",
  "calendarExceptionTypeSick": "Ziekte",
  "calendarExceptionTypeCustom": "Overig",
  "calendarExceptionNoteLabel": "Notitie (optioneel)",
```

- [ ] **Step 2: Run the ARB completeness test, then regenerate localizations**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

Run: `flutter gen-l10n`
Expected: completes with no errors.

- [ ] **Step 3: Add `dayEntriesProvider`**

Edit `lib/features/calendar/calendar_providers.dart`, adding at the end of the file:

```dart

/// Entries whose *start* falls within `[date, date + 1 day)`. An entry that
/// starts the previous evening and crosses midnight into [date] is
/// attributed to the previous day's list, not this one — the same
/// start-day-only simplification `reportEntriesProvider` already makes
/// elsewhere in this codebase; only [dailyWorkedMinutes] (Task 8) does the
/// full midnight split, and only for the totals, not the entry list shown
/// here.
final dayEntriesProvider = StreamProvider.family<List<TimeEntry>, DateTime>((ref, date) {
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  return ref.watch(appDatabaseProvider).timeEntriesDao.watchEntriesInRange(start.toUtc(), end.toUtc());
});
```

- [ ] **Step 4: Implement the day detail dialog**

Create `lib/features/calendar/day_detail_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../data/drift/tables/day_exceptions_table.dart';
import '../../l10n/app_localizations.dart';
import 'calendar_providers.dart';

Future<void> showDayDetailDialog(BuildContext context, DateTime date) {
  return showDialog<void>(context: context, builder: (context) => _DayDetailDialog(date: date));
}

class _DayDetailDialog extends ConsumerWidget {
  const _DayDetailDialog({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).languageCode;
    final monthCompliances = ref.watch(monthDayCompliancesProvider(date));
    final exceptionAsync = ref.watch(dayExceptionForDateProvider(date));
    final entriesAsync = ref.watch(dayEntriesProvider(date));

    return AlertDialog(
      title: Text(DateFormat.yMMMMEEEEd(localeName).format(date)),
      content: SizedBox(
        width: 360,
        child: monthCompliances.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (days) {
            final targetDate = DateTime(date.year, date.month, date.day);
            final compliance = days.firstWhere((d) => d.date == targetDate);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.calendarDayWorkedLabel}: '
                    '${(compliance.workedMinutes / 60).toStringAsFixed(1)}h',
                  ),
                  Text(
                    '${l10n.calendarDayTargetLabel}: '
                    '${(compliance.targetMinutes / 60).toStringAsFixed(1)}h',
                  ),
                  Text(
                    l10n.calendarDayBreakStatus(
                      compliance.breakTakenMinutes,
                      compliance.breakRequiredMinutes,
                    ),
                  ),
                  const SizedBox(height: 12),
                  entriesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) => Text('$error'),
                    data: (entries) => entries.isEmpty
                        ? Text(l10n.calendarNoEntriesForDay)
                        : Column(
                            children: [
                              for (final entry in entries)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    entry.description?.isNotEmpty == true
                                        ? entry.description!
                                        : l10n.entriesNoDescription,
                                  ),
                                  subtitle: Text(
                                    entry.endAt == null
                                        ? formatTime(entry.startAt)
                                        : '${formatTime(entry.startAt)} – ${formatTime(entry.endAt!)}',
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  exceptionAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, _) => const SizedBox.shrink(),
                    data: (exception) => exception == null
                        ? OutlinedButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => _MarkExceptionDialog(date: targetDate),
                            ),
                            child: Text(l10n.calendarMarkExceptionButton),
                          )
                        : OutlinedButton(
                            onPressed: () async {
                              final writes = await ref.read(syncedWritesProvider.future);
                              await writes.deleteDayException(exception.id);
                            },
                            child: Text(l10n.calendarRemoveExceptionButton),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonClose)),
      ],
    );
  }
}

class _MarkExceptionDialog extends ConsumerStatefulWidget {
  const _MarkExceptionDialog({required this.date});

  final DateTime date;

  @override
  ConsumerState<_MarkExceptionDialog> createState() => _MarkExceptionDialogState();
}

class _MarkExceptionDialogState extends ConsumerState<_MarkExceptionDialog> {
  String _type = DayExceptionTypes.vacation;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.upsertDayException(
      deviceId: deviceId,
      date: widget.date,
      type: _type,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.calendarExceptionDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: [
              DropdownMenuItem(
                value: DayExceptionTypes.holiday,
                child: Text(l10n.calendarExceptionTypeHoliday),
              ),
              DropdownMenuItem(
                value: DayExceptionTypes.vacation,
                child: Text(l10n.calendarExceptionTypeVacation),
              ),
              DropdownMenuItem(
                value: DayExceptionTypes.sick,
                child: Text(l10n.calendarExceptionTypeSick),
              ),
              DropdownMenuItem(
                value: DayExceptionTypes.custom,
                child: Text(l10n.calendarExceptionTypeCustom),
              ),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(labelText: l10n.calendarExceptionNoteLabel),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
    );
  }
}
```

- [ ] **Step 5: Wire `onDayTap` in `CalendarScreen`**

Edit `lib/features/calendar/calendar_screen.dart`. Add the import:

```dart
import 'day_detail_dialog.dart';
```

Change the `MonthView` usage:

```dart
          Expanded(
            child: MonthView(
              month: _focusedMonth,
              onDayTap: (date) => showDayDetailDialog(context, date),
            ),
          ),
```

- [ ] **Step 6: Write the dialog test**

Create `test/features/calendar/day_detail_dialog_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/calendar/day_detail_dialog.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_day_detail_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'dev_a'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDayDetailDialog(context, DateTime(2026, 7, 15)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('shows "no entries" and a mark-as-off button for an empty day', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No entries on this day'), findsOneWidget);
    expect(find.text('Mark as day off'), findsOneWidget);
  });

  testWidgets('marking a day as vacation persists a DayException', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as day off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final exception = await db.dayExceptionsDao.getForDate(DateTime(2026, 7, 15));
    expect(exception, isNotNull);
    expect(exception!.type, 'vacation');
  });
}
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/calendar/day_detail_dialog_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/calendar/calendar_providers.dart lib/features/calendar/day_detail_dialog.dart lib/features/calendar/calendar_screen.dart test/features/calendar/day_detail_dialog_test.dart
git commit -m "feat(calendar): add day detail dialog with exception marking"
```

---
### Task 15: Week view and month/week toggle

**Files:**
- Modify: `lib/features/calendar/calendar_providers.dart`
- Create: `lib/features/calendar/week_view.dart`
- Modify: `lib/features/calendar/calendar_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/features/calendar/week_view_test.dart`

**Interfaces:**
- Consumes: `dayCompliancesInRange` (Task 8), `dayEntriesProvider` (Task 14), `breakRuleTiersProvider`/`dayExceptionsProvider` (Task 10).
- Produces: `weekDayCompliancesProvider` (`FutureProvider.family<List<DayCompliance>, DateTime>`, keyed by that week's Monday), `WeekView({required DateTime weekStart, void Function(DateTime)? onDayTap})`. `CalendarScreen` gains a month/week `SegmentedButton` toggle.

- [ ] **Step 1: Add the ARB keys**

Edit `lib/l10n/app_de.arb`:

```json
  "calendarMonthViewLabel": "Monat",
  "calendarWeekViewLabel": "Woche",
```

Edit `lib/l10n/app_en.arb`:

```json
  "calendarMonthViewLabel": "Month",
  "calendarWeekViewLabel": "Week",
```

Edit `lib/l10n/app_es.arb`:

```json
  "calendarMonthViewLabel": "Mes",
  "calendarWeekViewLabel": "Semana",
```

Edit `lib/l10n/app_fr.arb`:

```json
  "calendarMonthViewLabel": "Mois",
  "calendarWeekViewLabel": "Semaine",
```

Edit `lib/l10n/app_it.arb`:

```json
  "calendarMonthViewLabel": "Mese",
  "calendarWeekViewLabel": "Settimana",
```

Edit `lib/l10n/app_nl.arb`:

```json
  "calendarMonthViewLabel": "Maand",
  "calendarWeekViewLabel": "Week",
```

- [ ] **Step 2: Run the ARB completeness test, then regenerate localizations**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

Run: `flutter gen-l10n`
Expected: completes with no errors.

- [ ] **Step 3: Add `weekDayCompliancesProvider`**

Edit `lib/features/calendar/calendar_providers.dart`, adding at the end of the file:

```dart

/// [weekStart] must be a local midnight that is itself a Monday (callers
/// compute this — see `CalendarScreen._mondayOf`); covers `[weekStart,
/// weekStart + 7 days)`, independent of `monthDayCompliancesProvider` so a
/// week spanning two months isn't clipped at a month boundary.
final weekDayCompliancesProvider = FutureProvider.family<List<DayCompliance>, DateTime>((
  ref,
  weekStart,
) async {
  final end = weekStart.add(const Duration(days: 7));
  final db = ref.watch(appDatabaseProvider);

  final entries = await db.timeEntriesDao.watchEntriesInRange(weekStart.toUtc(), end.toUtc()).first;
  final settings = await db.appSettingsDao.watchSettings().first;
  final tiers = await ref.watch(breakRuleTiersProvider.future);
  final exceptions = await ref.watch(
    dayExceptionsProvider(DateTimeRange(start: weekStart, end: end)).future,
  );

  return dayCompliancesInRange(
    start: weekStart,
    end: end,
    entries: entries,
    settings: settings,
    breakTiers: tiers,
    exceptions: exceptions,
  );
});
```

- [ ] **Step 4: Implement `WeekView`**

Create `lib/features/calendar/week_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import 'calendar_providers.dart';
import 'day_compliance.dart';

/// Seven day-columns for the week starting [weekStart] (a Monday), each
/// showing the day's status, worked hours, and its entries as simple
/// time-range lines.
class WeekView extends ConsumerWidget {
  const WeekView({super.key, required this.weekStart, this.onDayTap});

  final DateTime weekStart;
  final void Function(DateTime date)? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compliancesAsync = ref.watch(weekDayCompliancesProvider(weekStart));

    return compliancesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (days) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final day in days) Expanded(child: _WeekDayColumn(compliance: day, onTap: onDayTap)),
        ],
      ),
    );
  }
}

class _WeekDayColumn extends ConsumerWidget {
  const _WeekDayColumn({required this.compliance, required this.onTap});

  final DayCompliance compliance;
  final void Function(DateTime date)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).languageCode;
    final entriesAsync = ref.watch(dayEntriesProvider(compliance.date));
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, tooltip) = switch (compliance.status) {
      DayComplianceStatus.compliant => (
          Icons.check_circle,
          colorScheme.tertiary,
          l10n.calendarStatusCompliantTooltip,
        ),
      DayComplianceStatus.violation => (
          Icons.error,
          colorScheme.error,
          l10n.calendarStatusViolationTooltip,
        ),
      DayComplianceStatus.exception => (
          Icons.beach_access,
          colorScheme.outline,
          l10n.calendarStatusExceptionTooltip,
        ),
      DayComplianceStatus.noRule => (null, null, null),
    };

    return InkWell(
      onTap: onTap == null ? null : () => onTap!(compliance.date),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat.MMMd(localeName).format(compliance.date),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (icon != null) Tooltip(message: tooltip!, child: Icon(icon, size: 14, color: color)),
              ],
            ),
            Text(
              '${(compliance.workedMinutes / 60).toStringAsFixed(1)}h',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const Divider(height: 8),
            entriesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) => const SizedBox.shrink(),
              data: (entries) => Column(
                children: [
                  for (final entry in entries)
                    Text(
                      entry.endAt == null
                          ? formatTime(entry.startAt)
                          : '${formatTime(entry.startAt)}–${formatTime(entry.endAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add the month/week toggle to `CalendarScreen`**

Edit `lib/features/calendar/calendar_screen.dart`, replacing the whole file:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'day_detail_dialog.dart';
import 'month_view.dart';
import 'week_view.dart';

enum _CalendarViewMode { month, week }

/// Hickory's Calendar tab: a month/week toggle, period navigation, and the
/// active view. (Task 16 adds the overtime/undertime balance header here.)
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _focusedWeekStart = _mondayOf(DateTime.now());
  _CalendarViewMode _viewMode = _CalendarViewMode.month;

  static DateTime _mondayOf(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    return start.subtract(Duration(days: start.weekday - DateTime.monday));
  }

  void _goToPrevious() {
    setState(() {
      if (_viewMode == _CalendarViewMode.month) {
        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
      } else {
        _focusedWeekStart = _focusedWeekStart.subtract(const Duration(days: 7));
      }
    });
  }

  void _goToNext() {
    setState(() {
      if (_viewMode == _CalendarViewMode.month) {
        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
      } else {
        _focusedWeekStart = _focusedWeekStart.add(const Duration(days: 7));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).languageCode;
    final periodLabel = _viewMode == _CalendarViewMode.month
        ? DateFormat.yMMMM(localeName).format(_focusedMonth)
        : '${DateFormat.MMMd(localeName).format(_focusedWeekStart)} – '
            '${DateFormat.MMMd(localeName).format(_focusedWeekStart.add(const Duration(days: 6)))}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.calendarTitle, style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              SegmentedButton<_CalendarViewMode>(
                segments: [
                  ButtonSegment(
                    value: _CalendarViewMode.month,
                    label: Text(l10n.calendarMonthViewLabel),
                  ),
                  ButtonSegment(
                    value: _CalendarViewMode.week,
                    label: Text(l10n.calendarWeekViewLabel),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) => setState(() => _viewMode = selection.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.calendarPreviousPeriodTooltip,
                onPressed: _goToPrevious,
              ),
              Text(periodLabel),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.calendarNextPeriodTooltip,
                onPressed: _goToNext,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _viewMode == _CalendarViewMode.month
                ? MonthView(
                    month: _focusedMonth,
                    onDayTap: (date) => showDayDetailDialog(context, date),
                  )
                : WeekView(
                    weekStart: _focusedWeekStart,
                    onDayTap: (date) => showDayDetailDialog(context, date),
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Write the widget test**

Create `test/features/calendar/week_view_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/calendar/week_view.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('renders one column per weekday and shows an entry time range', (tester) async {
    await db.timeEntriesDao.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 6, 9), // Monday
      endAt: DateTime.utc(2026, 7, 6, 17),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: WeekView(weekStart: DateTime(2026, 7, 6))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('9:00 AM'), findsOneWidget);
  });
}
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/calendar/week_view_test.dart`
Expected: PASS (1 test)

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/calendar/calendar_providers.dart lib/features/calendar/week_view.dart lib/features/calendar/calendar_screen.dart test/features/calendar/week_view_test.dart
git commit -m "feat(calendar): add week view with a month/week toggle"
```

---
### Task 16: Overtime/undertime balance display and manual adjustment

**Files:**
- Modify: `lib/core/format/duration_format.dart`
- Create: `lib/features/calendar/balance_header.dart`
- Modify: `lib/features/calendar/calendar_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/core/format/duration_format_test.dart`
- Test: `test/features/calendar/balance_header_test.dart`

**Interfaces:**
- Consumes: `currentBalanceMinutesProvider` (Task 10), `syncedWritesProvider`/`deviceIdProvider`.
- Produces: `formatSignedDuration(Duration)` (added to `duration_format.dart`), `CalendarBalanceHeader` widget and `showBalanceAdjustmentDialog(BuildContext context)`, both wired into `CalendarScreen`.

- [ ] **Step 1: Add the ARB keys**

Edit `lib/l10n/app_de.arb`:

```json
  "calendarBalanceLabel": "Saldo",
  "calendarAddAdjustmentButton": "Anpassung hinzufügen",
  "calendarAdjustmentDialogTitle": "Saldo-Anpassung",
  "calendarAdjustmentDeltaLabel": "Anpassung (Stunden)",
  "calendarAdjustmentDateLabel": "Datum",
```

Edit `lib/l10n/app_en.arb`:

```json
  "calendarBalanceLabel": "Balance",
  "calendarAddAdjustmentButton": "Add adjustment",
  "calendarAdjustmentDialogTitle": "Balance adjustment",
  "calendarAdjustmentDeltaLabel": "Adjustment (hours)",
  "calendarAdjustmentDateLabel": "Date",
```

Edit `lib/l10n/app_es.arb`:

```json
  "calendarBalanceLabel": "Saldo",
  "calendarAddAdjustmentButton": "Añadir ajuste",
  "calendarAdjustmentDialogTitle": "Ajuste de saldo",
  "calendarAdjustmentDeltaLabel": "Ajuste (horas)",
  "calendarAdjustmentDateLabel": "Fecha",
```

Edit `lib/l10n/app_fr.arb`:

```json
  "calendarBalanceLabel": "Solde",
  "calendarAddAdjustmentButton": "Ajouter un ajustement",
  "calendarAdjustmentDialogTitle": "Ajustement du solde",
  "calendarAdjustmentDeltaLabel": "Ajustement (heures)",
  "calendarAdjustmentDateLabel": "Date",
```

Edit `lib/l10n/app_it.arb`:

```json
  "calendarBalanceLabel": "Saldo",
  "calendarAddAdjustmentButton": "Aggiungi rettifica",
  "calendarAdjustmentDialogTitle": "Rettifica del saldo",
  "calendarAdjustmentDeltaLabel": "Rettifica (ore)",
  "calendarAdjustmentDateLabel": "Data",
```

Edit `lib/l10n/app_nl.arb`:

```json
  "calendarBalanceLabel": "Saldo",
  "calendarAddAdjustmentButton": "Aanpassing toevoegen",
  "calendarAdjustmentDialogTitle": "Saldoaanpassing",
  "calendarAdjustmentDeltaLabel": "Aanpassing (uren)",
  "calendarAdjustmentDateLabel": "Datum",
```

(The adjustment note field reuses `calendarExceptionNoteLabel`, added in Task 14 — no new key needed.)

- [ ] **Step 2: Run the ARB completeness test, then regenerate localizations**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

Run: `flutter gen-l10n`
Expected: completes with no errors.

- [ ] **Step 3: Add `formatSignedDuration`**

Edit `lib/core/format/duration_format.dart`, adding at the end of the file:

```dart

/// Formats a possibly-negative duration as a signed "H:MM" string (e.g.
/// "+7:30", "-2:15"), for balances where the sign matters. Unlike
/// [formatDuration], seconds are omitted and the sign is always shown,
/// including for a zero balance.
String formatSignedDuration(Duration d) {
  final sign = d.isNegative ? '-' : '+';
  final absolute = d.abs();
  final hours = absolute.inHours;
  final minutes = absolute.inMinutes.remainder(60);
  return '$sign$hours:${minutes.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: Write the formatter test**

Create `test/core/format/duration_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/duration_format.dart';

void main() {
  group('formatSignedDuration', () {
    test('formats a positive duration with a leading +', () {
      expect(formatSignedDuration(const Duration(hours: 7, minutes: 30)), '+7:30');
    });

    test('formats a negative duration with a leading -, magnitude only', () {
      expect(formatSignedDuration(const Duration(hours: -2, minutes: -15)), '-2:15');
    });

    test('formats zero with a leading +', () {
      expect(formatSignedDuration(Duration.zero), '+0:00');
    });
  });
}
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/core/format/duration_format_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Implement the balance header and adjustment dialog**

Create `lib/features/calendar/balance_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/duration_format.dart';
import '../../l10n/app_localizations.dart';
import 'calendar_providers.dart';

/// The running overtime/undertime balance as of today, plus a button to
/// record a manual correction — see [showBalanceAdjustmentDialog].
class CalendarBalanceHeader extends ConsumerWidget {
  const CalendarBalanceHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final balanceAsync = ref.watch(currentBalanceMinutesProvider(DateTime.now()));

    return Row(
      children: [
        Text(l10n.calendarBalanceLabel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        balanceAsync.when(
          loading: () =>
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          error: (error, _) => Text('$error'),
          data: (minutes) => Text(
            formatSignedDuration(Duration(minutes: minutes)),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => showBalanceAdjustmentDialog(context),
          child: Text(l10n.calendarAddAdjustmentButton),
        ),
      ],
    );
  }
}

Future<void> showBalanceAdjustmentDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const _BalanceAdjustmentDialog());
}

class _BalanceAdjustmentDialog extends ConsumerStatefulWidget {
  const _BalanceAdjustmentDialog();

  @override
  ConsumerState<_BalanceAdjustmentDialog> createState() => _BalanceAdjustmentDialogState();
}

class _BalanceAdjustmentDialogState extends ConsumerState<_BalanceAdjustmentDialog> {
  DateTime _date = DateTime.now();
  final _deltaController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _deltaController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final hours = double.tryParse(_deltaController.text.trim().replaceAll(',', '.'));
    if (hours == null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.createBalanceAdjustment(
      deviceId: deviceId,
      date: _date,
      deltaMinutes: (hours * 60).round(),
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.calendarAdjustmentDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _deltaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: l10n.calendarAdjustmentDeltaLabel),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.calendarAdjustmentDateLabel),
            subtitle: Text(
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
              '${_date.day.toString().padLeft(2, '0')}',
            ),
            onTap: _pickDate,
          ),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(labelText: l10n.calendarExceptionNoteLabel),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
    );
  }
}
```

- [ ] **Step 7: Wire the balance header into `CalendarScreen`**

Edit `lib/features/calendar/calendar_screen.dart`. Add the import:

```dart
import 'balance_header.dart';
```

Insert `const CalendarBalanceHeader()` right after the title/toggle `Row` and its `SizedBox(height: 8)`, before the period-navigation `Row`:

```dart
          const SizedBox(height: 8),
          const CalendarBalanceHeader(),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
```

- [ ] **Step 8: Write the widget test**

Create `test/features/calendar/balance_header_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/calendar/balance_header.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_balance_header_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'dev_a'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CalendarBalanceHeader()),
        ),
      );

  testWidgets('shows a zero balance when nothing has been tracked or adjusted', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('+0:00'), findsOneWidget);
  });

  testWidgets('adding an adjustment updates the displayed balance', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add adjustment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('+2:00'), findsOneWidget);
  });
}
```

- [ ] **Step 9: Run the tests**

Run: `flutter test test/features/calendar/balance_header_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 10: Run the full test suite**

Run: `flutter test`
Expected: PASS (every test in the project, including all tasks in this plan)

- [ ] **Step 11: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/core/format/duration_format.dart lib/features/calendar/balance_header.dart lib/features/calendar/calendar_screen.dart test/core/format/duration_format_test.dart test/features/calendar/balance_header_test.dart
git commit -m "feat(calendar): show running overtime/undertime balance with manual adjustments"
```

---
