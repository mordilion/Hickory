# Work-Time Targets & Balance (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Hickory a configurable target work time and a flex-time balance, and show that balance as a first tile in the Reports tab.

**Architecture:** Nine new columns on the already-synced `AppSettings` singleton row carry the per-weekday targets and the balance reset rule. A pure Dart module (`balance_calculations.dart`, no Riverpod/Flutter/DB dependency beyond drift's row types — the same shape as the neighbouring `report_calculations.dart`) turns entries plus that row into per-day balances and a running total, applying the yearly cutoff in a single forward pass. A new Settings sub-page edits the values; the Reports tab reads them through plain Riverpod providers. Nothing is materialized in the database: a cached balance would need recomputation after every cross-device event-log merge, and those merges happen at arbitrary times.

**Tech Stack:** Flutter, Riverpod (plain providers — see Global Constraints), Drift, `intl`.

**Spec:** `docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md`

## Global Constraints

- English only in code, comments, and commit messages (repo convention).
- Conventional Commits: `<type>(scope): <description>`, imperative, lowercase, no trailing period, under 72 characters. Body, when present, is prose — no bullets, no section headers.
- ARB template locale is **German** (`lib/l10n/app_de.arb`, `template-arb-file: app_de.arb` in `l10n.yaml`). Write the German string first, then add the same key with a real translation to `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`. `test/l10n/arb_completeness_test.dart` fails the build if any locale's key set diverges. Run `flutter gen-l10n` after editing ARB files.
- Providers whose type touches drift-generated row classes (`TimeEntry`, `AppSettingsRow`, …) must be **plain** `Provider`/`FutureProvider`/`StreamProvider`, never `@riverpod` codegen — mixing riverpod_generator with drift's generator on the same type trips `rrousselGit/riverpod#4323`. Precedent: `lib/features/reports/reports_providers.dart`, `lib/core/di/app_settings_provider.dart`.
- After any Drift table/column change run `dart run build_runner build --delete-conflicting-outputs` before running tests.
- Weekday names in the UI come from `DateFormat.EEEE(localeName)`, never from ARB keys — `intl` already localizes them for all six locales.
- Status and sign indicators combine an icon **with** colour, never colour alone (repo accessibility rule).
- Do not run `dart format` on files you touch: the repository is not format-clean (99 of 210 files would change) and CI does not enforce it. Match the surrounding style by hand.
- Run tests as `flutter test --reporter expanded > /tmp/test.log 2>&1` and then grep the log for `[E]`. Piping `flutter test` to `tail` buffers until completion and has silently swallowed failures in this repo before.

---

### Task 1: Shared `AppSettingsRow` test fixture

Task 2 adds fourteen non-nullable columns to the generated `AppSettingsRow`. Drift's generated constructor requires every non-nullable field, so all eleven test files that hand-write an `AppSettingsRow(...)` literal today would stop compiling the moment that lands. Routing them through one factory first keeps every commit green and makes this phase — and phases 2 and 3, which add more columns — a one-file change instead of an eleven-file one. This task is a pure refactor: no behaviour changes, and the suite must be green before and after.

**Files:**
- Create: `test/support/app_settings_fixture.dart`
- Modify: every test file that constructs an `AppSettingsRow` literal (eleven at the time of writing — enumerate them with the command in Step 2 rather than trusting this list)

**Interfaces:**
- Consumes: nothing.
- Produces: `AppSettingsRow appSettingsFixture({String id, String dateFormat, String timeFormat, String quickAddDurationsMinutes, bool countPausedTimeAsBreak, DateTime? updatedAt})` in `test/support/app_settings_fixture.dart`.

- [ ] **Step 1: Write the fixture**

Create `test/support/app_settings_fixture.dart`:

```dart
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/app_settings_table.dart' show appSettingsRowId;

/// Builds an [AppSettingsRow] for tests, every field defaulting to what a
/// fresh install holds.
///
/// Tests go through this instead of drift's generated constructor so that
/// adding a non-nullable settings column stays a one-file change: the
/// generated constructor requires every non-nullable field, so each new
/// column would otherwise break every literal in the suite at once.
AppSettingsRow appSettingsFixture({
  String id = appSettingsRowId,
  String dateFormat = 'iso',
  String timeFormat = '24h',
  String quickAddDurationsMinutes = '15,30,45,60',
  bool countPausedTimeAsBreak = false,
  DateTime? updatedAt,
}) {
  return AppSettingsRow(
    id: id,
    dateFormat: dateFormat,
    timeFormat: timeFormat,
    quickAddDurationsMinutes: quickAddDurationsMinutes,
    countPausedTimeAsBreak: countPausedTimeAsBreak,
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  );
}
```

- [ ] **Step 2: List every literal to migrate**

Run: `grep -rn "AppSettingsRow(" test/`
Expected: matches in eleven files, among them `test/core/format/date_format_test.dart`, `test/features/settings/break_rule_tiers_editor_test.dart`, `test/features/timer/timer_screen_test.dart` and `test/data/sync_round_trip_test.dart`.

- [ ] **Step 3: Migrate each literal**

In each file, replace the literal with a call passing **only** the fields that literal set to something other than the fixture's default, and add the relative import (e.g. `import '../../support/app_settings_fixture.dart';` from `test/features/*/`). Worked example, from `break_rule_tiers_editor_test.dart`:

```dart
      // before
      appSettingsProvider.overrideWith(
        (ref) => Stream.value(
          AppSettingsRow(
            id: 'default',
            dateFormat: 'iso',
            timeFormat: '24h',
            quickAddDurationsMinutes: '15,30,45,60',
            countPausedTimeAsBreak: countPausedTimeAsBreak,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
      ),

      // after
      appSettingsProvider.overrideWith(
        (ref) => Stream.value(
          appSettingsFixture(countPausedTimeAsBreak: countPausedTimeAsBreak),
        ),
      ),
```

`test/data/sync_round_trip_test.dart` builds an older-peer payload from a real row's `.toJson()`; that literal migrates exactly the same way.

- [ ] **Step 4: Verify no literal is left and the suite is unchanged**

Run: `grep -rn "AppSettingsRow(" test/ ; flutter analyze > /tmp/analyze.log 2>&1; tail -3 /tmp/analyze.log; flutter test --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: the grep prints nothing, `No issues found!`, and no `[E]` lines. Same test count as before this task — it changes no behaviour.

- [ ] **Step 5: Commit**

```bash
git add test/support/app_settings_fixture.dart test/
git commit -m "test(settings): build settings rows through one fixture"
```

---

### Task 2: `AppSettings` — target and balance columns

**Files:**
- Modify: `lib/data/drift/tables/app_settings_table.dart`
- Modify: `lib/data/drift/daos/app_settings_dao.dart`
- Modify: `lib/data/drift/database.dart:66` (`schemaVersion`) and `:68-94` (`onUpgrade`)
- Modify: `test/support/app_settings_fixture.dart`
- Test: `test/data/drift/app_settings_dao_test.dart`

**Interfaces:**
- Consumes: `appSettingsFixture` from Task 1.
- Produces: `AppSettingsRow` gains `int targetMinutesMonday … targetMinutesSunday` (default `0`), `String targetInputMode` (default `'perWeekday'`), `String balanceResetMode` (default `'none'`), `int? balanceResetDay`, `int? balanceResetMonth`, `int? carryOverMaxMinutes`, `int? carryOverMinMinutes`, `bool absenceTrackingEnabled` (default `false`). `AppSettingsDao.updateSettings` gains `int? targetMinutesMonday … targetMinutesSunday`, `String? targetInputMode`, `String? balanceResetMode`, `bool? absenceTrackingEnabled` and `Value<int?> balanceResetDay/balanceResetMonth/carryOverMaxMinutes/carryOverMinMinutes = const Value.absent()`. `AppDatabase.schemaVersion == 9`.

- [ ] **Step 1: Write the failing tests**

Append to `test/data/drift/app_settings_dao_test.dart`, inside the existing `main()`:

```dart
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
```

Add the drift import at the top of the file, next to the existing imports:

```dart
import 'package:drift/drift.dart' show Value;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/drift/app_settings_dao_test.dart --reporter expanded > /tmp/test.log 2>&1; grep -c '\[E\]' /tmp/test.log`
Expected: compile failure — `The named parameter 'targetMinutesMonday' isn't defined`.

- [ ] **Step 3: Add the columns to the table**

In `lib/data/drift/tables/app_settings_table.dart`, add inside `class AppSettings`, after `countPausedTimeAsBreak` and before `updatedAt`:

```dart
  // Per-weekday target work time in minutes. 0 means "not a work day" and
  // doubles as the free-day marker, so no separate flag is needed. These
  // seven values are the single source of truth for every target and
  // balance calculation; a weekly figure entered in Settings is
  // distributed across them on save and never stored separately.
  IntColumn get targetMinutesMonday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesTuesday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesWednesday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesThursday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesFriday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesSaturday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesSunday => integer().withDefault(const Constant(0))();
  // 'perWeekday' | 'perWeek' -- affects only how the settings screen
  // renders and reopens, never the calculation.
  TextColumn get targetInputMode => text().withDefault(const Constant('perWeekday'))();
  // 'none' | 'resetToZero' | 'carryOver' -- what happens to the accumulated
  // balance when the yearly cutoff is crossed.
  TextColumn get balanceResetMode => text().withDefault(const Constant('none'))();
  // The recurring cutoff, so a fiscal year end works as well as a calendar
  // one. Both null while balanceResetMode is 'none'.
  IntColumn get balanceResetDay => integer().nullable()();
  IntColumn get balanceResetMonth => integer().nullable()();
  // Bounds of what survives a cutoff in 'carryOver' mode; null means
  // unbounded on that side.
  IntColumn get carryOverMaxMinutes => integer().nullable()();
  IntColumn get carryOverMinMinutes => integer().nullable()();
  // Global switch for the absence feature (phase 2). Declared here so the
  // AppSettings row needs only one migration across the whole design.
  BoolColumn get absenceTrackingEnabled => boolean().withDefault(const Constant(false))();
```

- [ ] **Step 4: Bump the schema version and add the migration**

In `lib/data/drift/database.dart`, change `int get schemaVersion => 8;` to `=> 9;` and append inside `onUpgrade`, after the existing `if (from < 8)` block:

```dart
      if (from < 9) {
        await m.addColumn(appSettings, appSettings.targetMinutesMonday);
        await m.addColumn(appSettings, appSettings.targetMinutesTuesday);
        await m.addColumn(appSettings, appSettings.targetMinutesWednesday);
        await m.addColumn(appSettings, appSettings.targetMinutesThursday);
        await m.addColumn(appSettings, appSettings.targetMinutesFriday);
        await m.addColumn(appSettings, appSettings.targetMinutesSaturday);
        await m.addColumn(appSettings, appSettings.targetMinutesSunday);
        await m.addColumn(appSettings, appSettings.targetInputMode);
        await m.addColumn(appSettings, appSettings.balanceResetMode);
        await m.addColumn(appSettings, appSettings.balanceResetDay);
        await m.addColumn(appSettings, appSettings.balanceResetMonth);
        await m.addColumn(appSettings, appSettings.carryOverMaxMinutes);
        await m.addColumn(appSettings, appSettings.carryOverMinMinutes);
        await m.addColumn(appSettings, appSettings.absenceTrackingEnabled);
      }
```

- [ ] **Step 5: Regenerate the drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: succeeds; `lib/data/drift/database.g.dart` now carries the new fields on `AppSettingsRow`.

- [ ] **Step 6: Extend the DAO**

In `lib/data/drift/daos/app_settings_dao.dart`, add the drift `Value` import if not present (`import 'package:drift/drift.dart';` already covers it), then replace `updateSettings` and `_defaultRow` with:

```dart
  /// Upserts the singleton row, changing only the fields passed in.
  ///
  /// Non-nullable fields take a plain nullable parameter (`null` = leave
  /// alone). The four nullable balance fields take a [Value] instead,
  /// because `null` there has to stay usable as a real value — clearing a
  /// carry-over bound is a legitimate edit, and `??` could never express it.
  Future<AppSettingsRow> updateSettings({
    String? dateFormat,
    String? timeFormat,
    String? quickAddDurationsMinutes,
    bool? countPausedTimeAsBreak,
    int? targetMinutesMonday,
    int? targetMinutesTuesday,
    int? targetMinutesWednesday,
    int? targetMinutesThursday,
    int? targetMinutesFriday,
    int? targetMinutesSaturday,
    int? targetMinutesSunday,
    String? targetInputMode,
    String? balanceResetMode,
    Value<int?> balanceResetDay = const Value.absent(),
    Value<int?> balanceResetMonth = const Value.absent(),
    Value<int?> carryOverMaxMinutes = const Value.absent(),
    Value<int?> carryOverMinMinutes = const Value.absent(),
    bool? absenceTrackingEnabled,
  }) async {
    final current =
        await (select(appSettings)..where((s) => s.id.equals(appSettingsRowId))).getSingleOrNull() ??
            _defaultRow();
    final updated = AppSettingsRow(
      id: appSettingsRowId,
      dateFormat: dateFormat ?? current.dateFormat,
      timeFormat: timeFormat ?? current.timeFormat,
      quickAddDurationsMinutes: quickAddDurationsMinutes ?? current.quickAddDurationsMinutes,
      countPausedTimeAsBreak: countPausedTimeAsBreak ?? current.countPausedTimeAsBreak,
      targetMinutesMonday: targetMinutesMonday ?? current.targetMinutesMonday,
      targetMinutesTuesday: targetMinutesTuesday ?? current.targetMinutesTuesday,
      targetMinutesWednesday: targetMinutesWednesday ?? current.targetMinutesWednesday,
      targetMinutesThursday: targetMinutesThursday ?? current.targetMinutesThursday,
      targetMinutesFriday: targetMinutesFriday ?? current.targetMinutesFriday,
      targetMinutesSaturday: targetMinutesSaturday ?? current.targetMinutesSaturday,
      targetMinutesSunday: targetMinutesSunday ?? current.targetMinutesSunday,
      targetInputMode: targetInputMode ?? current.targetInputMode,
      balanceResetMode: balanceResetMode ?? current.balanceResetMode,
      balanceResetDay:
          balanceResetDay.present ? balanceResetDay.value : current.balanceResetDay,
      balanceResetMonth:
          balanceResetMonth.present ? balanceResetMonth.value : current.balanceResetMonth,
      carryOverMaxMinutes:
          carryOverMaxMinutes.present ? carryOverMaxMinutes.value : current.carryOverMaxMinutes,
      carryOverMinMinutes:
          carryOverMinMinutes.present ? carryOverMinMinutes.value : current.carryOverMinMinutes,
      absenceTrackingEnabled: absenceTrackingEnabled ?? current.absenceTrackingEnabled,
      updatedAt: DateTime.now().toUtc(),
    );
    await into(appSettings).insertOnConflictUpdate(updated);
    return updated;
  }

  AppSettingsRow _defaultRow() => AppSettingsRow(
        id: appSettingsRowId,
        dateFormat: 'iso',
        timeFormat: '24h',
        quickAddDurationsMinutes: '15,30,45,60',
        countPausedTimeAsBreak: false,
        targetMinutesMonday: 0,
        targetMinutesTuesday: 0,
        targetMinutesWednesday: 0,
        targetMinutesThursday: 0,
        targetMinutesFriday: 0,
        targetMinutesSaturday: 0,
        targetMinutesSunday: 0,
        targetInputMode: 'perWeekday',
        balanceResetMode: 'none',
        absenceTrackingEnabled: false,
        updatedAt: DateTime.now().toUtc(),
      );
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/data/drift/app_settings_dao_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines, all tests pass.

- [ ] **Step 8: Extend the test fixture with the new columns**

The generated constructor now requires the seven target fields, the two mode fields and `absenceTrackingEnabled`, so `test/support/app_settings_fixture.dart` no longer compiles. Add a parameter per new column, defaulting to the same value the table declares, and pass each through:

```dart
AppSettingsRow appSettingsFixture({
  String id = appSettingsRowId,
  String dateFormat = 'iso',
  String timeFormat = '24h',
  String quickAddDurationsMinutes = '15,30,45,60',
  bool countPausedTimeAsBreak = false,
  int targetMinutesMonday = 0,
  int targetMinutesTuesday = 0,
  int targetMinutesWednesday = 0,
  int targetMinutesThursday = 0,
  int targetMinutesFriday = 0,
  int targetMinutesSaturday = 0,
  int targetMinutesSunday = 0,
  String targetInputMode = 'perWeekday',
  String balanceResetMode = 'none',
  int? balanceResetDay,
  int? balanceResetMonth,
  int? carryOverMaxMinutes,
  int? carryOverMinMinutes,
  bool absenceTrackingEnabled = false,
  DateTime? updatedAt,
}) {
  return AppSettingsRow(
    id: id,
    dateFormat: dateFormat,
    timeFormat: timeFormat,
    quickAddDurationsMinutes: quickAddDurationsMinutes,
    countPausedTimeAsBreak: countPausedTimeAsBreak,
    targetMinutesMonday: targetMinutesMonday,
    targetMinutesTuesday: targetMinutesTuesday,
    targetMinutesWednesday: targetMinutesWednesday,
    targetMinutesThursday: targetMinutesThursday,
    targetMinutesFriday: targetMinutesFriday,
    targetMinutesSaturday: targetMinutesSaturday,
    targetMinutesSunday: targetMinutesSunday,
    targetInputMode: targetInputMode,
    balanceResetMode: balanceResetMode,
    balanceResetDay: balanceResetDay,
    balanceResetMonth: balanceResetMonth,
    carryOverMaxMinutes: carryOverMaxMinutes,
    carryOverMinMinutes: carryOverMinMinutes,
    absenceTrackingEnabled: absenceTrackingEnabled,
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  );
}
```

- [ ] **Step 9: Run the whole suite**

Run: `flutter analyze > /tmp/analyze.log 2>&1; tail -3 /tmp/analyze.log; flutter test --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: `No issues found!` and no `[E]` lines — nothing outside the fixture should have needed a change.

- [ ] **Step 10: Commit**

```bash
git add lib/data/drift/tables/app_settings_table.dart lib/data/drift/daos/app_settings_dao.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/drift/daos/app_settings_dao.g.dart test/data/drift/app_settings_dao_test.dart test/support/app_settings_fixture.dart
git commit -m "feat(settings): store per-weekday targets and the balance rule"
```

---

### Task 3: Sync the new settings fields

**Files:**
- Modify: `lib/data/sync/synced_writes.dart:311-330` (`updateAppSettings`)
- Modify: `lib/data/sync/sync_ingestor.dart:160-184` (the `EntityTypes.appSettings` case)
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `AppSettingsDao.updateSettings` from Task 2.
- Produces: `SyncedWrites.updateAppSettings` with the identical parameter list as `updateSettings` (same names, same `Value<int?>` treatment), returning `Future<AppSettingsRow>`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/data/sync_round_trip_test.dart`:

```dart
  test('per-weekday targets and the reset rule reach a second device', () async {
    final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(writerDb.close);
    final writes = SyncedWrites(
      db: writerDb,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'),
    );
    await writes.updateAppSettings(
      targetMinutesMonday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: const Value(1),
      balanceResetMonth: const Value(1),
    );

    final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(readerDb.close);
    await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

    final row = (await readerDb.select(readerDb.appSettings).get()).single;
    expect(row.targetMinutesMonday, 480);
    expect(row.balanceResetMode, 'resetToZero');
    expect(row.balanceResetDay, 1);
    expect(row.balanceResetMonth, 1);
  });

  test(
    'ingesting an app_settings event from a peer that predates the target '
    'columns backfills their defaults instead of throwing',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final full = await writerDb.appSettingsDao.updateSettings(dateFormat: 'de');
      final v8Payload = full.toJson()
        ..remove('targetMinutesMonday')
        ..remove('targetMinutesTuesday')
        ..remove('targetMinutesWednesday')
        ..remove('targetMinutesThursday')
        ..remove('targetMinutesFriday')
        ..remove('targetMinutesSaturday')
        ..remove('targetMinutesSunday')
        ..remove('targetInputMode')
        ..remove('balanceResetMode')
        ..remove('absenceTrackingEnabled');
      await SyncLogWriter(syncRoot: syncRoot, deviceId: 'old-peer').appendEvent(
        entityType: EntityTypes.appSettings,
        entityId: appSettingsRowId,
        op: EventOp.update,
        payload: v8Payload,
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

      final row = (await readerDb.select(readerDb.appSettings).get()).single;
      expect(row.dateFormat, 'de');
      expect(row.targetMinutesMonday, 0);
      expect(row.targetInputMode, 'perWeekday');
      expect(row.balanceResetMode, 'none');
      expect(row.absenceTrackingEnabled, isFalse);
    },
  );
```

Add to that file's imports if missing:

```dart
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
```

(the file already imports `driftRuntimeOptions`; extend the existing `show` clause rather than adding a second import.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/sync_round_trip_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `The named parameter 'targetMinutesMonday' isn't defined` for `updateAppSettings`.

- [ ] **Step 3: Widen the write-through method**

In `lib/data/sync/synced_writes.dart`, replace the parameter list and forwarding call of `updateAppSettings` so it mirrors the DAO exactly:

```dart
  Future<AppSettingsRow> updateAppSettings({
    String? dateFormat,
    String? timeFormat,
    String? quickAddDurationsMinutes,
    bool? countPausedTimeAsBreak,
    int? targetMinutesMonday,
    int? targetMinutesTuesday,
    int? targetMinutesWednesday,
    int? targetMinutesThursday,
    int? targetMinutesFriday,
    int? targetMinutesSaturday,
    int? targetMinutesSunday,
    String? targetInputMode,
    String? balanceResetMode,
    Value<int?> balanceResetDay = const Value.absent(),
    Value<int?> balanceResetMonth = const Value.absent(),
    Value<int?> carryOverMaxMinutes = const Value.absent(),
    Value<int?> carryOverMinMinutes = const Value.absent(),
    bool? absenceTrackingEnabled,
  }) async {
    final updated = await db.appSettingsDao.updateSettings(
      dateFormat: dateFormat,
      timeFormat: timeFormat,
      quickAddDurationsMinutes: quickAddDurationsMinutes,
      countPausedTimeAsBreak: countPausedTimeAsBreak,
      targetMinutesMonday: targetMinutesMonday,
      targetMinutesTuesday: targetMinutesTuesday,
      targetMinutesWednesday: targetMinutesWednesday,
      targetMinutesThursday: targetMinutesThursday,
      targetMinutesFriday: targetMinutesFriday,
      targetMinutesSaturday: targetMinutesSaturday,
      targetMinutesSunday: targetMinutesSunday,
      targetInputMode: targetInputMode,
      balanceResetMode: balanceResetMode,
      balanceResetDay: balanceResetDay,
      balanceResetMonth: balanceResetMonth,
      carryOverMaxMinutes: carryOverMaxMinutes,
      carryOverMinMinutes: carryOverMinMinutes,
      absenceTrackingEnabled: absenceTrackingEnabled,
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

Ensure `package:drift/drift.dart` is imported in that file (it is, for `Value`).

- [ ] **Step 4: Extend the ingestor's backfill**

In `lib/data/sync/sync_ingestor.dart`, extend the existing backfill map in the `EntityTypes.appSettings` case (the nullable columns need no entry — `fromJson` accepts their absence):

```dart
          final payload = {
            'quickAddDurationsMinutes': '15,30,45,60',
            'countPausedTimeAsBreak': false,
            'targetMinutesMonday': 0,
            'targetMinutesTuesday': 0,
            'targetMinutesWednesday': 0,
            'targetMinutesThursday': 0,
            'targetMinutesFriday': 0,
            'targetMinutesSaturday': 0,
            'targetMinutesSunday': 0,
            'targetInputMode': 'perWeekday',
            'balanceResetMode': 'none',
            'absenceTrackingEnabled': false,
            ...entity.payload!,
          };
```

Update that block's comment to name v9 alongside v5 and v7 as a version whose fields are backfilled.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/data/sync_round_trip_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines.

- [ ] **Step 6: Commit**

```bash
git add lib/data/sync/synced_writes.dart lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): propagate work-time targets to the other devices"
```

---

### Task 4: Per-day balances (pure module)

**Files:**
- Create: `lib/features/reports/balance_calculations.dart`
- Test: `test/features/reports/balance_calculations_test.dart`

**Interfaces:**
- Consumes: `AppSettingsRow` from Task 2; `TimeEntry` and `TimeEntry.workedDuration` from `lib/data/drift/time_entry_extensions.dart`.
- Produces:
  - `int targetMinutesForWeekday(AppSettingsRow settings, int weekday)` — `weekday` is `DateTime.monday`…`DateTime.sunday`.
  - `bool hasAnyTarget(AppSettingsRow settings)`.
  - `class DayBalance { final DateTime day; final Duration worked; final Duration target; Duration get balance; }` — `day` is local midnight.
  - `List<DayBalance> dayBalances(List<TimeEntry> entries, AppSettingsRow settings)` — ascending by day.

- [ ] **Step 1: Write the failing tests**

Create `test/features/reports/balance_calculations_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/balance_calculations.dart';

import '../../support/app_settings_fixture.dart';

AppSettingsRow settingsWith({
  int monday = 0,
  int tuesday = 0,
  int wednesday = 0,
  int thursday = 0,
  int friday = 0,
  int saturday = 0,
  int sunday = 0,
  String balanceResetMode = 'none',
  int? balanceResetDay,
  int? balanceResetMonth,
  int? carryOverMaxMinutes,
  int? carryOverMinMinutes,
}) {
  return appSettingsFixture(
    targetMinutesMonday: monday,
    targetMinutesTuesday: tuesday,
    targetMinutesWednesday: wednesday,
    targetMinutesThursday: thursday,
    targetMinutesFriday: friday,
    targetMinutesSaturday: saturday,
    targetMinutesSunday: sunday,
    balanceResetMode: balanceResetMode,
    balanceResetDay: balanceResetDay,
    balanceResetMonth: balanceResetMonth,
    carryOverMaxMinutes: carryOverMaxMinutes,
    carryOverMinMinutes: carryOverMinMinutes,
  );
}

/// A finished entry running [minutes] from 09:00 local time on [day].
TimeEntry entryOn(DateTime day, int minutes, {String id = 'e'}) {
  final start = DateTime(day.year, day.month, day.day, 9);
  return TimeEntry(
    id: id,
    startAt: start.toUtc(),
    endAt: start.add(Duration(minutes: minutes)).toUtc(),
    totalPausedSeconds: 0,
    source: 'manual',
    deviceId: 'test',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  // 2026-09-07 is a Monday.
  final monday = DateTime(2026, 9, 7);
  final tuesday = DateTime(2026, 9, 8);
  final saturday = DateTime(2026, 9, 12);

  test('targetMinutesForWeekday reads the column matching the weekday', () {
    final settings = settingsWith(monday: 480, saturday: 120);
    expect(targetMinutesForWeekday(settings, DateTime.monday), 480);
    expect(targetMinutesForWeekday(settings, DateTime.saturday), 120);
    expect(targetMinutesForWeekday(settings, DateTime.sunday), 0);
  });

  test('hasAnyTarget is false only when every weekday is zero', () {
    expect(hasAnyTarget(settingsWith()), isFalse);
    expect(hasAnyTarget(settingsWith(sunday: 1)), isTrue);
  });

  test('a day worked short of its target yields a negative balance', () {
    final balances = dayBalances([entryOn(monday, 420)], settingsWith(monday: 480));
    expect(balances, hasLength(1));
    expect(balances.single.worked, const Duration(minutes: 420));
    expect(balances.single.target, const Duration(minutes: 480));
    expect(balances.single.balance, const Duration(minutes: -60));
  });

  test('several entries on one day are summed into a single day', () {
    final balances = dayBalances(
      [entryOn(monday, 240, id: 'a'), entryOn(monday, 240, id: 'b')],
      settingsWith(monday: 480),
    );
    expect(balances, hasLength(1));
    expect(balances.single.balance, Duration.zero);
  });

  test('time tracked on a day with no target counts fully as a plus', () {
    final balances = dayBalances([entryOn(saturday, 120)], settingsWith(monday: 480));
    expect(balances.single.target, Duration.zero);
    expect(balances.single.balance, const Duration(minutes: 120));
  });

  test('a work day without any entry is not counted while absences are off', () {
    final balances = dayBalances([entryOn(monday, 480)], settingsWith(monday: 480, tuesday: 480));
    expect(balances.map((b) => b.day), [monday]);
  });

  test('a running entry does not contribute a day', () {
    final running = TimeEntry(
      id: 'running',
      startAt: DateTime(monday.year, monday.month, monday.day, 9).toUtc(),
      endAt: null,
      totalPausedSeconds: 0,
      source: 'manual',
      deviceId: 'test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    expect(dayBalances([running], settingsWith(monday: 480)), isEmpty);
  });

  test('days come back ascending regardless of input order', () {
    final balances = dayBalances(
      [entryOn(tuesday, 60, id: 'b'), entryOn(monday, 60, id: 'a')],
      settingsWith(monday: 480, tuesday: 480),
    );
    expect(balances.map((b) => b.day), [monday, tuesday]);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/reports/balance_calculations_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `Target of URI doesn't exist: '.../balance_calculations.dart'`.

- [ ] **Step 3: Write the module**

Create `lib/features/reports/balance_calculations.dart`:

```dart
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';
import 'report_calculations.dart' show totalsByDay;

/// Flex-time ("Gleitzeit") balance arithmetic. Pure: no Riverpod, no
/// Flutter, no database access beyond drift's row types — the same shape as
/// report_calculations.dart, and testable with plain in-memory lists.
///
/// Nothing here is materialized in the database on purpose: a cached
/// balance would need recomputation after every cross-device event-log
/// merge, and those merges happen at arbitrary times.
library;

/// Target work minutes for [weekday] (`DateTime.monday` … `DateTime.sunday`).
/// `0` means the day is not a work day.
int targetMinutesForWeekday(AppSettingsRow settings, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return settings.targetMinutesMonday;
    case DateTime.tuesday:
      return settings.targetMinutesTuesday;
    case DateTime.wednesday:
      return settings.targetMinutesWednesday;
    case DateTime.thursday:
      return settings.targetMinutesThursday;
    case DateTime.friday:
      return settings.targetMinutesFriday;
    case DateTime.saturday:
      return settings.targetMinutesSaturday;
    default:
      return settings.targetMinutesSunday;
  }
}

/// Whether any target is configured at all. False in a fresh install, where
/// every tracked minute would otherwise read as overtime — callers show an
/// empty state pointing at Settings instead of a number.
bool hasAnyTarget(AppSettingsRow settings) => [
      settings.targetMinutesMonday,
      settings.targetMinutesTuesday,
      settings.targetMinutesWednesday,
      settings.targetMinutesThursday,
      settings.targetMinutesFriday,
      settings.targetMinutesSaturday,
      settings.targetMinutesSunday,
    ].any((minutes) => minutes > 0);

/// One calendar day's contribution to the balance.
class DayBalance {
  const DayBalance({
    required this.day,
    required this.worked,
    required this.target,
  });

  /// Local midnight of the day, the same key [totalsByDay] groups by.
  final DateTime day;
  final Duration worked;
  final Duration target;

  Duration get balance => worked - target;
}

/// Per-day balances, ascending by day.
///
/// Only days carrying at least one finished entry are returned. While
/// absence tracking is off (phase 1 always), a day off cannot be recorded,
/// so counting empty work days would manufacture a deficit. Phase 2 makes
/// this conditional on `settings.absenceTrackingEnabled`.
List<DayBalance> dayBalances(List<TimeEntry> entries, AppSettingsRow settings) {
  final workedByDay = totalsByDay(entries);
  final days = workedByDay.keys.toList()..sort();
  return [
    for (final day in days)
      DayBalance(
        day: day,
        worked: workedByDay[day]!,
        target: Duration(minutes: targetMinutesForWeekday(settings, day.weekday)),
      ),
  ];
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/reports/balance_calculations_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/balance_calculations.dart test/features/reports/balance_calculations_test.dart
git commit -m "feat(reports): compute per-day work-time balances"
```

---

### Task 5: The cutoff pass

**Files:**
- Modify: `lib/features/reports/balance_calculations.dart`
- Test: `test/features/reports/balance_calculations_test.dart`

**Interfaces:**
- Consumes: `DayBalance`, `dayBalances` from Task 4.
- Produces:
  - `DateTime? lastCutoffOnOrBefore(AppSettingsRow settings, DateTime day)` — local midnight, or `null` when `balanceResetMode == 'none'` or the cutoff is not fully configured.
  - `Duration runningBalance(List<DayBalance> balances, AppSettingsRow settings, {required DateTime asOf})`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/reports/balance_calculations_test.dart`, inside `main()`:

```dart
  test('lastCutoffOnOrBefore returns null when no rule is configured', () {
    expect(lastCutoffOnOrBefore(settingsWith(), DateTime(2026, 9, 7)), isNull);
  });

  test('lastCutoffOnOrBefore returns null when the rule lacks a date', () {
    final settings = settingsWith(balanceResetMode: 'resetToZero');
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 9, 7)), isNull);
  });

  test('lastCutoffOnOrBefore picks this year once the date has passed', () {
    final settings = settingsWith(
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 7,
    );
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 9, 7)), DateTime(2026, 7, 1));
  });

  test('lastCutoffOnOrBefore falls back to last year before the date', () {
    final settings = settingsWith(
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 7,
    );
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 3, 1)), DateTime(2025, 7, 1));
  });

  test('a 29 February cutoff clamps to the 28th in a non-leap year', () {
    final settings = settingsWith(
      balanceResetMode: 'resetToZero',
      balanceResetDay: 29,
      balanceResetMonth: 2,
    );
    expect(lastCutoffOnOrBefore(settings, DateTime(2026, 6, 1)), DateTime(2026, 2, 28));
  });

  test('without a rule the balance is the plain sum', () {
    final settings = settingsWith(monday: 480, tuesday: 480);
    final balances = dayBalances(
      [entryOn(monday, 540, id: 'a'), entryOn(tuesday, 540, id: 'b')],
      settings,
    );
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 120),
    );
  });

  test('resetToZero drops everything earned before the cutoff', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 9,
    );
    // 2026-08-31 is a Monday, 2026-09-07 the next one.
    final balances = dayBalances(
      [entryOn(DateTime(2026, 8, 31), 540, id: 'a'), entryOn(monday, 540, id: 'b')],
      settings,
    );
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 60),
      reason: 'only the day after the 1 September cutoff survives',
    );
  });

  test('a cutoff after the last worked day still applies', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 10,
    );
    final balances = dayBalances([entryOn(monday, 540)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 10, 5)),
      Duration.zero,
    );
  });

  test('carryOver clamps the surviving balance to the maximum', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'carryOver',
      balanceResetDay: 1,
      balanceResetMonth: 9,
      carryOverMaxMinutes: 30,
    );
    final balances = dayBalances([entryOn(DateTime(2026, 8, 31), 600)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 30),
      reason: '120 minutes earned, only 30 carried over',
    );
  });

  test('carryOver clamps a deficit to the minimum', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'carryOver',
      balanceResetDay: 1,
      balanceResetMonth: 9,
      carryOverMinMinutes: -30,
    );
    final balances = dayBalances([entryOn(DateTime(2026, 8, 31), 300)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: -30),
    );
  });

  test('carryOver leaves a balance inside the bounds alone', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'carryOver',
      balanceResetDay: 1,
      balanceResetMonth: 9,
      carryOverMaxMinutes: 600,
      carryOverMinMinutes: -600,
    );
    final balances = dayBalances([entryOn(DateTime(2026, 8, 31), 540)], settings);
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 9, 30)),
      const Duration(minutes: 60),
    );
  });

  test('several cutoffs in a gap between worked days all apply', () {
    final settings = settingsWith(
      monday: 480,
      balanceResetMode: 'resetToZero',
      balanceResetDay: 1,
      balanceResetMonth: 1,
    );
    // 2024-01-08 and 2026-01-05 are both Mondays, with two cutoffs between.
    final balances = dayBalances(
      [entryOn(DateTime(2024, 1, 8), 600, id: 'a'), entryOn(DateTime(2026, 1, 5), 540, id: 'b')],
      settings,
    );
    expect(
      runningBalance(balances, settings, asOf: DateTime(2026, 2, 1)),
      const Duration(minutes: 60),
    );
  });

  test('days after asOf are ignored', () {
    final settings = settingsWith(monday: 480, tuesday: 480);
    final balances = dayBalances(
      [entryOn(monday, 540, id: 'a'), entryOn(tuesday, 540, id: 'b')],
      settings,
    );
    expect(runningBalance(balances, settings, asOf: monday), const Duration(minutes: 60));
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/reports/balance_calculations_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `The function 'lastCutoffOnOrBefore' isn't defined`.

- [ ] **Step 3: Implement the cutoff helpers**

Append to `lib/features/reports/balance_calculations.dart`:

```dart
/// The cutoff date falling in [year], with the configured day clamped to
/// that month's length — a 29 February rule becomes 28 February in a
/// non-leap year rather than silently rolling into March.
DateTime? _cutoffInYear(AppSettingsRow settings, int year) {
  final month = settings.balanceResetMonth;
  final day = settings.balanceResetDay;
  if (month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1) return null;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > daysInMonth ? daysInMonth : day);
}

/// The most recent cutoff on or before [day], or null when no usable rule
/// is configured. A rule with `balanceResetMode == 'none'`, or one missing
/// its date, has no cutoff at all.
DateTime? lastCutoffOnOrBefore(AppSettingsRow settings, DateTime day) {
  if (settings.balanceResetMode == 'none') return null;
  final thisYear = _cutoffInYear(settings, day.year);
  if (thisYear == null) return null;
  if (!thisYear.isAfter(day)) return thisYear;
  return _cutoffInYear(settings, day.year - 1);
}

/// Applies the reset rule to a balance that has just crossed a cutoff.
Duration _afterCutoff(Duration balance, AppSettingsRow settings) {
  if (settings.balanceResetMode == 'resetToZero') return Duration.zero;
  final max = settings.carryOverMaxMinutes;
  final min = settings.carryOverMinMinutes;
  if (max != null && balance.inMinutes > max) return Duration(minutes: max);
  if (min != null && balance.inMinutes < min) return Duration(minutes: min);
  return balance;
}

/// The running balance up to and including [asOf].
///
/// Applied as a single forward pass: days are added in order, and whenever
/// one or more cutoffs fall between the previous day and the current one
/// the accumulated balance is reset or clamped first. Deterministic and
/// linear in the number of worked days, no matter how long the history —
/// a recursive "balance of the previous period" formulation would re-walk
/// the same years once per cutoff.
Duration runningBalance(
  List<DayBalance> balances,
  AppSettingsRow settings, {
  required DateTime asOf,
}) {
  var total = Duration.zero;
  var previous = DateTime(1970);

  void applyCutoffsBetween(DateTime from, DateTime to) {
    if (settings.balanceResetMode == 'none') return;
    for (var year = from.year; year <= to.year; year++) {
      final cutoff = _cutoffInYear(settings, year);
      if (cutoff == null) return;
      if (cutoff.isAfter(from) && !cutoff.isAfter(to)) {
        total = _afterCutoff(total, settings);
      }
    }
  }

  for (final day in balances) {
    if (day.day.isAfter(asOf)) break;
    applyCutoffsBetween(previous, day.day);
    total += day.balance;
    previous = day.day;
  }
  applyCutoffsBetween(previous, asOf);
  return total;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/reports/balance_calculations_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/balance_calculations.dart test/features/reports/balance_calculations_test.dart
git commit -m "feat(reports): apply the balance cutoff in a forward pass"
```

---

### Task 6: Weekly target distribution (pure helper)

**Files:**
- Create: `lib/features/settings/weekly_target_distribution.dart`
- Test: `test/features/settings/weekly_target_distribution_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Map<int, int> distributeWeeklyMinutes(int weeklyMinutes, Set<int> workDays)` — keys are all seven `DateTime.monday`…`DateTime.sunday`, values sum exactly to `weeklyMinutes`, non-work days map to `0`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/settings/weekly_target_distribution_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/settings/weekly_target_distribution.dart';

void main() {
  const workWeek = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };

  test('an evenly divisible week splits into equal days', () {
    final result = distributeWeeklyMinutes(2400, workWeek);
    expect(result[DateTime.monday], 480);
    expect(result[DateTime.friday], 480);
    expect(result[DateTime.saturday], 0);
  });

  test('every weekday is present in the result', () {
    final result = distributeWeeklyMinutes(2400, workWeek);
    expect(result.keys.toSet(), {1, 2, 3, 4, 5, 6, 7});
  });

  test('a remainder goes to the earliest days so the week sums exactly', () {
    final result = distributeWeeklyMinutes(2313, workWeek);
    expect(result.values.reduce((a, b) => a + b), 2313);
    expect(result[DateTime.monday], 463);
    expect(result[DateTime.tuesday], 463);
    expect(result[DateTime.wednesday], 463);
    expect(result[DateTime.thursday], 462);
    expect(result[DateTime.friday], 462);
  });

  test('no work days yields an all-zero week', () {
    final result = distributeWeeklyMinutes(2400, const {});
    expect(result.values.every((minutes) => minutes == 0), isTrue);
  });

  test('a negative weekly figure is treated as zero', () {
    final result = distributeWeeklyMinutes(-60, workWeek);
    expect(result.values.every((minutes) => minutes == 0), isTrue);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/settings/weekly_target_distribution_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the helper**

Create `lib/features/settings/weekly_target_distribution.dart`:

```dart
/// Splits a weekly target across the chosen work days.
///
/// Returns a value for all seven weekdays (`DateTime.monday` …
/// `DateTime.sunday`); non-work days get `0`. The remainder of an uneven
/// division is handed to the earliest work days, so the seven values sum to
/// exactly [weeklyMinutes] — a settings screen that showed the sum back to
/// the user would otherwise drift by a few minutes each time it round-trips.
/// A negative [weeklyMinutes] is treated as zero rather than rejected: the
/// only caller is a text field, and an empty week is a meaningful state.
Map<int, int> distributeWeeklyMinutes(int weeklyMinutes, Set<int> workDays) {
  final total = weeklyMinutes < 0 ? 0 : weeklyMinutes;
  final days = workDays.toList()..sort();
  final result = {for (var weekday = 1; weekday <= 7; weekday++) weekday: 0};
  if (days.isEmpty) return result;

  final base = total ~/ days.length;
  var remainder = total % days.length;
  for (final weekday in days) {
    result[weekday] = base + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder--;
  }
  return result;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/settings/weekly_target_distribution_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/weekly_target_distribution.dart test/features/settings/weekly_target_distribution_test.dart
git commit -m "feat(settings): distribute a weekly target across work days"
```

---

### Task 7: Work-time targets editor

**Files:**
- Create: `lib/features/settings/work_time_targets_editor.dart`
- Create: `lib/features/settings/work_time_settings_screen.dart`
- Modify: `lib/features/settings/settings_home_screen.dart` (new `ListTile` after the time-tracking one)
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/settings/work_time_targets_editor_test.dart`

**Interfaces:**
- Consumes: `distributeWeeklyMinutes` (Task 6), `SyncedWrites.updateAppSettings` (Task 3), `appSettingsProvider` from `lib/core/di/app_settings_provider.dart`, `syncedWritesProvider` from `lib/core/di/sync_providers.dart`.
- Produces: `WorkTimeTargetsEditor` (a `ConsumerStatefulWidget`) and `WorkTimeSettingsScreen`.

- [ ] **Step 1: Add the localized strings**

Add to `lib/l10n/app_de.arb` (the template):

```json
  "settingsCategoryWorkTime": "Arbeitszeit & Zeitkonto",
  "settingsWorkTimeTargetsTitle": "Soll-Arbeitszeit",
  "settingsWorkTimeTargetsDescription": "Legt fest, wie viel Arbeitszeit pro Tag erwartet wird. Ohne Soll-Zeit kann kein Zeitkonto geführt werden.",
  "settingsWorkTimeModePerWeekday": "Pro Wochentag",
  "settingsWorkTimeModePerWeek": "Pro Woche",
  "settingsWorkTimeWeeklyHours": "Wochensoll in Stunden",
  "settingsWorkTimeWorkDays": "Arbeitstage",
  "settingsWorkTimeHoursSuffix": "h",
  "settingsWorkTimeSaveError": "Die Arbeitszeit konnte nicht gespeichert werden.",
```

Add the same keys with these translations:

- `app_en.arb`: `"Work time & balance"`, `"Target work time"`, `"Sets how much work is expected per day. Without a target there is no balance to keep."`, `"Per weekday"`, `"Per week"`, `"Weekly target in hours"`, `"Work days"`, `"h"`, `"Could not save the work time."`
- `app_fr.arb`: `"Temps de travail et compteur"`, `"Temps de travail cible"`, `"Définit le temps de travail attendu par jour. Sans cible, aucun compteur n'est possible."`, `"Par jour de semaine"`, `"Par semaine"`, `"Cible hebdomadaire en heures"`, `"Jours travaillés"`, `"h"`, `"Impossible d'enregistrer le temps de travail."`
- `app_es.arb`: `"Jornada y saldo horario"`, `"Jornada objetivo"`, `"Define cuánto trabajo se espera al día. Sin objetivo no hay saldo que llevar."`, `"Por día de la semana"`, `"Por semana"`, `"Objetivo semanal en horas"`, `"Días laborables"`, `"h"`, `"No se pudo guardar la jornada."`
- `app_it.arb`: `"Orario di lavoro e saldo"`, `"Orario previsto"`, `"Definisce quanto lavoro è previsto al giorno. Senza un obiettivo non c'è saldo da tenere."`, `"Per giorno della settimana"`, `"Per settimana"`, `"Obiettivo settimanale in ore"`, `"Giorni lavorativi"`, `"h"`, `"Impossibile salvare l'orario di lavoro."`
- `app_nl.arb`: `"Werktijd en saldo"`, `"Streefwerktijd"`, `"Bepaalt hoeveel werk per dag wordt verwacht. Zonder streeftijd is er geen saldo bij te houden."`, `"Per weekdag"`, `"Per week"`, `"Weekstreeftijd in uren"`, `"Werkdagen"`, `"u"`, `"De werktijd kon niet worden opgeslagen."`

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing test**

Create `test/features/settings/work_time_targets_editor_test.dart`:

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
import 'package:hickory/features/settings/work_time_targets_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

// SyncedWrites' real SyncLogWriter does real file I/O, which flutter_test's
// binding only services inside WidgetTester.runAsync -- outside of it an
// awaited write never completes and hangs the test forever. Every
// interaction that triggers a write therefore runs inside runAsync,
// together with the poll that waits for its effect. The trap is documented
// in full at test/features/settings/break_rule_tiers_editor_test.dart:17.
Future<void> waitFor(Future<bool> Function() condition, {int maxTries = 50}) async {
  for (var attempt = 0; attempt < maxTries; attempt++) {
    if (await condition()) {
      // The DB write completes before the sync log's trailing file write,
      // which is awaited afterwards in the same chain; let it finish inside
      // this runAsync scope so it cannot race tearDown's directory delete.
      await Future.delayed(const Duration(milliseconds: 50));
      return;
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

Directory makeSyncRoot(String prefix) => Directory.systemTemp.createTempSync(prefix);

Future<void> removeSyncRoot(Directory syncRoot) async {
  // Windows can transiently hold the log file open after the write returns;
  // retry briefly rather than fail on an unrelated cleanup race.
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!syncRoot.existsSync()) return;
    try {
      syncRoot.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = makeSyncRoot('hickory_work_time_targets_test_');
  });

  tearDown(() async {
    await db.close();
    await removeSyncRoot(syncRoot);
  });

  // appDatabaseProvider is the only data override: appSettingsProvider
  // reads through it, so the editor stays reactive to what the writes
  // actually store instead of observing a frozen stream.
  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: SingleChildScrollView(child: WorkTimeTargetsEditor())),
        ),
      );

  testWidgets('starts in per-weekday mode with seven fields', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(7));
  });

  testWidgets('entering a daily target writes it to the database', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.enterText(find.byKey(const ValueKey('workTimeTarget1')), '8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).targetMinutesMonday == 480,
      );
    });

    final row = await db.appSettingsDao.watchSettings().first;
    expect(row.targetMinutesMonday, 480);
  });

  testWidgets('weekly mode shows one field and the work-day toggles', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Pro Woche'));
      await waitFor(
        () async =>
            (await db.appSettingsDao.watchSettings().first).targetInputMode == 'perWeek',
      );
    });
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(7));
  });

  testWidgets('a weekly target is distributed across the selected work days', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Pro Woche'));
      await waitFor(
        () async =>
            (await db.appSettingsDao.watchSettings().first).targetInputMode == 'perWeek',
      );
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.enterText(find.byKey(const ValueKey('workTimeWeekly')), '40');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).targetMinutesMonday == 480,
      );
    });

    final row = await db.appSettingsDao.watchSettings().first;
    expect(row.targetMinutesMonday, 480);
    expect(row.targetMinutesFriday, 480);
    expect(row.targetMinutesSaturday, 0);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/settings/work_time_targets_editor_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `Target of URI doesn't exist: '.../work_time_targets_editor.dart'`.

- [ ] **Step 4: Write the editor**

Create `lib/features/settings/work_time_targets_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../features/reports/balance_calculations.dart' show targetMinutesForWeekday;
import '../../l10n/app_localizations.dart';
import 'weekly_target_distribution.dart';

/// Settings editor for the per-weekday work-time target. Two input modes
/// over the same seven stored values: seven day fields, or one weekly
/// figure plus work-day toggles that is distributed on save. The mode is
/// persisted only so the screen reopens the way the user left it — every
/// calculation reads the seven day values.
class WorkTimeTargetsEditor extends ConsumerStatefulWidget {
  const WorkTimeTargetsEditor({super.key});

  @override
  ConsumerState<WorkTimeTargetsEditor> createState() => _WorkTimeTargetsEditorState();
}

class _WorkTimeTargetsEditorState extends ConsumerState<WorkTimeTargetsEditor> {
  /// True while a write is in flight — disables the inputs so a fast
  /// double edit cannot interleave two read-modify-write cycles on the
  /// singleton settings row.
  bool _busy = false;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save work-time target: $error');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsWorkTimeSaveError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setMode(String mode) async {
    await _guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(targetInputMode: mode);
    });
  }

  Future<void> _setDayMinutes(int weekday, int minutes) async {
    await _guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        targetMinutesMonday: weekday == DateTime.monday ? minutes : null,
        targetMinutesTuesday: weekday == DateTime.tuesday ? minutes : null,
        targetMinutesWednesday: weekday == DateTime.wednesday ? minutes : null,
        targetMinutesThursday: weekday == DateTime.thursday ? minutes : null,
        targetMinutesFriday: weekday == DateTime.friday ? minutes : null,
        targetMinutesSaturday: weekday == DateTime.saturday ? minutes : null,
        targetMinutesSunday: weekday == DateTime.sunday ? minutes : null,
      );
    });
  }

  Future<void> _setWeekly(int weeklyMinutes, Set<int> workDays) async {
    await _guardedWrite(() async {
      final perDay = distributeWeeklyMinutes(weeklyMinutes, workDays);
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        targetInputMode: 'perWeek',
        targetMinutesMonday: perDay[DateTime.monday],
        targetMinutesTuesday: perDay[DateTime.tuesday],
        targetMinutesWednesday: perDay[DateTime.wednesday],
        targetMinutesThursday: perDay[DateTime.thursday],
        targetMinutesFriday: perDay[DateTime.friday],
        targetMinutesSaturday: perDay[DateTime.saturday],
        targetMinutesSunday: perDay[DateTime.sunday],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const Center(child: CircularProgressIndicator());

    final isWeekly = settings.targetInputMode == 'perWeek';
    final workDays = {
      for (var weekday = 1; weekday <= 7; weekday++)
        if (targetMinutesForWeekday(settings, weekday) > 0) weekday,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsWorkTimeTargetsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l10n.settingsWorkTimeTargetsDescription,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l10n.settingsWorkTimeModePerWeekday)),
            ButtonSegment(value: true, label: Text(l10n.settingsWorkTimeModePerWeek)),
          ],
          selected: {isWeekly},
          onSelectionChanged: _busy
              ? null
              : (selection) => _setMode(selection.first ? 'perWeek' : 'perWeekday'),
        ),
        const SizedBox(height: 16),
        if (isWeekly)
          _WeeklyInput(
            settings: settings,
            workDays: workDays,
            enabled: !_busy,
            onChanged: _setWeekly,
          )
        else
          _PerWeekdayInput(settings: settings, enabled: !_busy, onChanged: _setDayMinutes),
      ],
    );
  }
}

/// The weekday's localized full name, from intl rather than seven ARB keys
/// per locale. 2024-01-01 was a Monday, so it anchors the offset.
String weekdayName(BuildContext context, int weekday) {
  final localeName = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.EEEE(localeName).format(DateTime(2024, 1, weekday));
}

/// Parses an hours field ("7,7" or "7.7") into whole minutes; null when the
/// text is not a number.
int? hoursTextToMinutes(String text) {
  final hours = double.tryParse(text.trim().replaceAll(',', '.'));
  if (hours == null) return null;
  return (hours * 60).round();
}

String minutesToHoursText(int minutes) {
  if (minutes == 0) return '';
  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toStringAsFixed(2).replaceAll('.', ',');
}

class _PerWeekdayInput extends StatelessWidget {
  const _PerWeekdayInput({
    required this.settings,
    required this.enabled,
    required this.onChanged,
  });

  final AppSettingsRow settings;
  final bool enabled;
  final Future<void> Function(int weekday, int minutes) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(weekdayName(context, weekday))),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: ValueKey('workTimeTarget$weekday'),
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(
                      text: minutesToHoursText(targetMinutesForWeekday(settings, weekday)),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: l10n.settingsWorkTimeHoursSuffix,
                    ),
                    onSubmitted: (text) {
                      final minutes = hoursTextToMinutes(text);
                      if (minutes != null && minutes >= 0) onChanged(weekday, minutes);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WeeklyInput extends StatefulWidget {
  const _WeeklyInput({
    required this.settings,
    required this.workDays,
    required this.enabled,
    required this.onChanged,
  });

  final AppSettingsRow settings;
  final Set<int> workDays;
  final bool enabled;
  final Future<void> Function(int weeklyMinutes, Set<int> workDays) onChanged;

  @override
  State<_WeeklyInput> createState() => _WeeklyInputState();
}

class _WeeklyInputState extends State<_WeeklyInput> {
  late Set<int> _workDays = widget.workDays.isEmpty
      ? {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday}
      : {...widget.workDays};

  int get _weeklyMinutes => [
        for (var weekday = 1; weekday <= 7; weekday++)
          targetMinutesForWeekday(widget.settings, weekday),
      ].fold(0, (sum, minutes) => sum + minutes);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('workTimeWeekly'),
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          controller: TextEditingController(text: minutesToHoursText(_weeklyMinutes)),
          decoration: InputDecoration(
            labelText: l10n.settingsWorkTimeWeeklyHours,
            isDense: true,
            suffixText: l10n.settingsWorkTimeHoursSuffix,
          ),
          onSubmitted: (text) {
            final minutes = hoursTextToMinutes(text);
            if (minutes != null && minutes >= 0) widget.onChanged(minutes, _workDays);
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.settingsWorkTimeWorkDays, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              FilterChip(
                label: Text(weekdayName(context, weekday)),
                selected: _workDays.contains(weekday),
                onSelected: widget.enabled
                    ? (selected) {
                        setState(() {
                          selected ? _workDays.add(weekday) : _workDays.remove(weekday);
                        });
                        widget.onChanged(_weeklyMinutes, _workDays);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Write the screen and wire it into Settings**

Create `lib/features/settings/work_time_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'settings_sub_page.dart';
import 'work_time_targets_editor.dart';

/// Target work time and, from Task 8, the balance reset rule.
class WorkTimeSettingsScreen extends StatelessWidget {
  const WorkTimeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSubPage(
      title: l10n.settingsCategoryWorkTime,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: WorkTimeTargetsEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

In `lib/features/settings/settings_home_screen.dart`, add the import and insert a tile with a `Divider(height: 1)` before it, directly after the time-tracking `ListTile`:

```dart
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(l10n.settingsCategoryWorkTime),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkTimeSettingsScreen(),
                    ),
                  ),
                ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/settings/ test/l10n/ --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines — the ARB completeness test confirms all six locales carry the new keys.

- [ ] **Step 7: Run the whole suite and the analyzer**

Run: `flutter analyze > /tmp/analyze.log 2>&1; tail -3 /tmp/analyze.log; flutter test --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: `No issues found!` and no `[E]` lines.

- [ ] **Step 8: Commit**

```bash
git add lib/features/settings/work_time_targets_editor.dart lib/features/settings/work_time_settings_screen.dart lib/features/settings/settings_home_screen.dart lib/l10n/ test/features/settings/work_time_targets_editor_test.dart
git commit -m "feat(settings): edit the target work time per day or per week"
```

---

### Task 8: Balance reset rule editor

**Files:**
- Create: `lib/features/settings/balance_rule_editor.dart`
- Modify: `lib/features/settings/work_time_settings_screen.dart` (second card)
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/settings/balance_rule_editor_test.dart`

**Interfaces:**
- Consumes: `SyncedWrites.updateAppSettings` (Task 3), `appSettingsProvider`.
- Produces: `BalanceRuleEditor` (a `ConsumerStatefulWidget`).

- [ ] **Step 1: Add the localized strings**

Add to `lib/l10n/app_de.arb`:

```json
  "settingsBalanceTitle": "Zeitkonto",
  "settingsBalanceDescription": "Legt fest, was am Stichtag mit dem angesammelten Saldo passiert.",
  "settingsBalanceModeNone": "Kein Stichtag",
  "settingsBalanceModeReset": "Auf 0 setzen",
  "settingsBalanceModeCarryOver": "Übertrag mit Kappung",
  "settingsBalanceCutoff": "Stichtag",
  "settingsBalanceCutoffMissing": "Bitte einen Stichtag wählen.",
  "settingsBalanceCarryOverMax": "Höchstens übertragen (Stunden)",
  "settingsBalanceCarryOverMin": "Höchstens Minus übertragen (Stunden)",
  "settingsBalanceBoundMissing": "Bitte mindestens eine Grenze angeben.",
```

The same keys in the other five locales:

- `app_en.arb`: `"Balance"`, `"Sets what happens to the accumulated balance on the cutoff date."`, `"No cutoff"`, `"Reset to zero"`, `"Carry over with caps"`, `"Cutoff date"`, `"Please choose a cutoff date."`, `"Carry over at most (hours)"`, `"Carry over at most this deficit (hours)"`, `"Please set at least one bound."`
- `app_fr.arb`: `"Compteur"`, `"Définit ce qu'il advient du solde accumulé à la date de clôture."`, `"Aucune clôture"`, `"Remettre à zéro"`, `"Report plafonné"`, `"Date de clôture"`, `"Veuillez choisir une date de clôture."`, `"Reporter au maximum (heures)"`, `"Reporter au maximum ce déficit (heures)"`, `"Veuillez définir au moins une limite."`
- `app_es.arb`: `"Saldo horario"`, `"Define qué ocurre con el saldo acumulado en la fecha de corte."`, `"Sin corte"`, `"Poner a cero"`, `"Arrastre con tope"`, `"Fecha de corte"`, `"Elige una fecha de corte."`, `"Arrastrar como máximo (horas)"`, `"Arrastrar como máximo este déficit (horas)"`, `"Indica al menos un límite."`
- `app_it.arb`: `"Saldo ore"`, `"Definisce cosa accade al saldo accumulato alla data di chiusura."`, `"Nessuna chiusura"`, `"Azzerare"`, `"Riporto con tetto"`, `"Data di chiusura"`, `"Scegli una data di chiusura."`, `"Riportare al massimo (ore)"`, `"Riportare al massimo questo deficit (ore)"`, `"Indica almeno un limite."`
- `app_nl.arb`: `"Tijdsaldo"`, `"Bepaalt wat er op de peildatum met het opgebouwde saldo gebeurt."`, `"Geen peildatum"`, `"Op nul zetten"`, `"Overdracht met begrenzing"`, `"Peildatum"`, `"Kies een peildatum."`, `"Hoogstens overdragen (uren)"`, `"Hoogstens dit tekort overdragen (uren)"`, `"Stel minstens één grens in."`

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing test**

Create `test/features/settings/balance_rule_editor_test.dart`:

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
import 'package:hickory/features/settings/balance_rule_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

// SyncedWrites' real SyncLogWriter does real file I/O, which flutter_test's
// binding only services inside WidgetTester.runAsync -- outside of it an
// awaited write never completes and hangs the test forever. Every
// interaction that triggers a write therefore runs inside runAsync,
// together with the poll that waits for its effect. The trap is documented
// in full at test/features/settings/break_rule_tiers_editor_test.dart:17.
Future<void> waitFor(Future<bool> Function() condition, {int maxTries = 50}) async {
  for (var attempt = 0; attempt < maxTries; attempt++) {
    if (await condition()) {
      // The DB write completes before the sync log's trailing file write,
      // which is awaited afterwards in the same chain; let it finish inside
      // this runAsync scope so it cannot race tearDown's directory delete.
      await Future.delayed(const Duration(milliseconds: 50));
      return;
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

Directory makeSyncRoot(String prefix) => Directory.systemTemp.createTempSync(prefix);

Future<void> removeSyncRoot(Directory syncRoot) async {
  // Windows can transiently hold the log file open after the write returns;
  // retry briefly rather than fail on an unrelated cleanup race.
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!syncRoot.existsSync()) return;
    try {
      syncRoot.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = makeSyncRoot('hickory_balance_rule_test_');
  });

  tearDown(() async {
    await db.close();
    await removeSyncRoot(syncRoot);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: SingleChildScrollView(child: BalanceRuleEditor())),
        ),
      );

  /// Opens the mode dropdown and picks [label]. No runAsync: choosing a
  /// mode other than "no cutoff" is held locally until the rule is
  /// complete, so nothing is written yet.
  Future<void> chooseMode(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('balanceMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('no cutoff hides the date and the bounds', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Stichtag'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('choosing reset-to-zero reveals the cutoff but no bounds', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    expect(find.text('Stichtag'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('choosing carry-over reveals both bounds', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Übertrag mit Kappung');

    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('an incomplete rule is not persisted and says what is missing', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    final row = await db.appSettingsDao.watchSettings().first;
    expect(row.balanceResetMode, 'none', reason: 'incomplete rules must not reach the database');
    expect(find.text('Bitte einen Stichtag wählen.'), findsOneWidget);
  });

  testWidgets('picking a cutoff month persists the complete rule', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    await tester.tap(find.byKey(const ValueKey('balanceCutoffMonth')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Juli').last);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).balanceResetMonth == 7,
      );
    });

    final row = await db.appSettingsDao.watchSettings().first;
    expect(row.balanceResetMode, 'resetToZero');
    expect(row.balanceResetMonth, 7);
    expect(row.balanceResetDay, 1, reason: 'the day defaults to the 1st until changed');
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/settings/balance_rule_editor_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `Target of URI doesn't exist: '.../balance_rule_editor.dart'`.

- [ ] **Step 4: Write the editor**

Create `lib/features/settings/balance_rule_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import 'work_time_targets_editor.dart' show hoursTextToMinutes, minutesToHoursText;

/// Settings editor for what happens to the flex-time balance at the yearly
/// cutoff. The rule is only written once it is complete: a mode without a
/// cutoff date, or a carry-over without any bound, would leave the
/// calculation guessing, so the editor keeps it local and says which field
/// is missing instead.
class BalanceRuleEditor extends ConsumerStatefulWidget {
  const BalanceRuleEditor({super.key});

  @override
  ConsumerState<BalanceRuleEditor> createState() => _BalanceRuleEditorState();
}

class _BalanceRuleEditorState extends ConsumerState<BalanceRuleEditor> {
  /// The mode the user has selected but not yet completed. Null once the
  /// stored rule and the selection agree.
  String? _pendingMode;
  bool _busy = false;

  String _selectedMode(String storedMode) => _pendingMode ?? storedMode;

  Future<void> _write({
    required String mode,
    required Value<int?> day,
    required Value<int?> month,
    Value<int?> max = const Value.absent(),
    Value<int?> min = const Value.absent(),
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        balanceResetMode: mode,
        balanceResetDay: day,
        balanceResetMonth: month,
        carryOverMaxMinutes: max,
        carryOverMinMinutes: min,
      );
      if (mounted) setState(() => _pendingMode = null);
    } catch (error) {
      debugPrint('Failed to save the balance rule: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const Center(child: CircularProgressIndicator());

    final mode = _selectedMode(settings.balanceResetMode);
    final hasCutoff = settings.balanceResetMonth != null && settings.balanceResetDay != null;
    final localeName = Localizations.localeOf(context).toLanguageTag();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsBalanceTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsBalanceDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        // A dropdown, not RadioListTile: that widget's groupValue/onChanged
        // API is deprecated in the Flutter version this repo pins, and
        // nothing in lib/ uses it. DropdownButtonFormField matches
        // general_settings_screen.dart, which is the house pattern here.
        DropdownButtonFormField<String>(
          key: const ValueKey('balanceMode'),
          initialValue: mode,
          isDense: true,
          items: [
            DropdownMenuItem(value: 'none', child: Text(l10n.settingsBalanceModeNone)),
            DropdownMenuItem(value: 'resetToZero', child: Text(l10n.settingsBalanceModeReset)),
            DropdownMenuItem(value: 'carryOver', child: Text(l10n.settingsBalanceModeCarryOver)),
          ],
          onChanged: _busy
              ? null
              : (selected) {
                  if (selected == null) return;
                  if (selected == 'none') {
                    // The only mode that is complete on its own, so it is
                    // written straight away and clears the stale bounds.
                    _write(
                      mode: 'none',
                      day: const Value(null),
                      month: const Value(null),
                      max: const Value(null),
                      min: const Value(null),
                    );
                    return;
                  }
                  setState(() => _pendingMode = selected);
                },
        ),
        if (mode != 'none') ...[
          const SizedBox(height: 8),
          Text(l10n.settingsBalanceCutoff, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('balanceCutoffMonth'),
                  initialValue: settings.balanceResetMonth,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (var month = 1; month <= 12; month++)
                      DropdownMenuItem(
                        value: month,
                        child: Text(DateFormat.MMMM(localeName).format(DateTime(2024, month))),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (month) {
                          if (month == null) return;
                          _write(
                            mode: mode,
                            day: Value(settings.balanceResetDay ?? 1),
                            month: Value(month),
                          );
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('balanceCutoffDay'),
                  initialValue: settings.balanceResetDay,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (var day = 1; day <= 31; day++)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: _busy
                      ? null
                      : (day) {
                          if (day == null) return;
                          _write(
                            mode: mode,
                            day: Value(day),
                            month: Value(settings.balanceResetMonth ?? 1),
                          );
                        },
                ),
              ),
            ],
          ),
          if (!hasCutoff) ...[
            const SizedBox(height: 8),
            Text(
              l10n.settingsBalanceCutoffMissing,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ],
        if (mode == 'carryOver') ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('carryOverMax'),
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: TextEditingController(
              text: minutesToHoursText(settings.carryOverMaxMinutes ?? 0),
            ),
            decoration: InputDecoration(
              labelText: l10n.settingsBalanceCarryOverMax,
              isDense: true,
            ),
            onSubmitted: (text) {
              final minutes = hoursTextToMinutes(text);
              _write(
                mode: mode,
                day: Value(settings.balanceResetDay ?? 1),
                month: Value(settings.balanceResetMonth ?? 1),
                max: Value(minutes),
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('carryOverMin'),
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: TextEditingController(
              text: minutesToHoursText(settings.carryOverMinMinutes ?? 0),
            ),
            decoration: InputDecoration(
              labelText: l10n.settingsBalanceCarryOverMin,
              isDense: true,
            ),
            onSubmitted: (text) {
              final minutes = hoursTextToMinutes(text);
              _write(
                mode: mode,
                day: Value(settings.balanceResetDay ?? 1),
                month: Value(settings.balanceResetMonth ?? 1),
                min: Value(minutes == null ? null : -minutes.abs()),
              );
            },
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 5: Add the card to the screen**

In `lib/features/settings/work_time_settings_screen.dart`, add the import and a second card after the first:

```dart
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BalanceRuleEditor(),
            ),
          ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/settings/ test/l10n/ --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines.

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/balance_rule_editor.dart lib/features/settings/work_time_settings_screen.dart lib/l10n/ test/features/settings/balance_rule_editor_test.dart
git commit -m "feat(settings): configure the balance cutoff rule"
```

---

### Task 9: The balance tile in the Reports tab

**Files:**
- Create: `lib/features/reports/balance_card.dart`
- Modify: `lib/features/reports/reports_providers.dart` (balance provider)
- Modify: `lib/features/reports/reports_screen.dart` (`_ReportRangeAndBody.build`, above the `Expanded` body)
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/reports/balance_card_test.dart`

**Interfaces:**
- Consumes: `dayBalances`, `runningBalance`, `lastCutoffOnOrBefore`, `hasAnyTarget` (Tasks 4-5); `allEntriesProvider` from `lib/features/timer/timer_providers.dart`; `appSettingsProvider`.
- Produces: `BalanceCard` (a `ConsumerWidget`), and `formatSignedDuration(Duration)` in `balance_card.dart`.

- [ ] **Step 1: Add the localized strings**

Add to `lib/l10n/app_de.arb`:

```json
  "reportsBalanceTitle": "Zeitkonto",
  "reportsBalanceSince": "Saldo seit {date}",
  "@reportsBalanceSince": {
    "placeholders": {
      "date": { "type": "String" }
    }
  },
  "reportsBalanceAllTime": "Saldo gesamt",
  "reportsBalanceNoTargets": "Noch keine Soll-Arbeitszeit hinterlegt.",
  "reportsBalanceConfigure": "Unter Einstellungen → Arbeitszeit & Zeitkonto festlegen.",
```

The same keys in the other five locales (`reportsBalanceSince` keeps the `{date}` placeholder and its `@`-block in each file):

- `app_en.arb`: `"Balance"`, `"Balance since {date}"`, `"Balance overall"`, `"No target work time set yet."`, `"Set it under Settings → Work time & balance."`
- `app_fr.arb`: `"Compteur"`, `"Solde depuis le {date}"`, `"Solde total"`, `"Aucun temps de travail cible défini."`, `"À définir dans Réglages → Temps de travail et compteur."`
- `app_es.arb`: `"Saldo horario"`, `"Saldo desde el {date}"`, `"Saldo total"`, `"Aún no hay jornada objetivo definida."`, `"Defínela en Ajustes → Jornada y saldo horario."`
- `app_it.arb`: `"Saldo ore"`, `"Saldo dal {date}"`, `"Saldo complessivo"`, `"Nessun orario previsto impostato."`, `"Impostalo in Impostazioni → Orario di lavoro e saldo."`
- `app_nl.arb`: `"Tijdsaldo"`, `"Saldo sinds {date}"`, `"Saldo totaal"`, `"Nog geen streefwerktijd ingesteld."`, `"Stel die in bij Instellingen → Werktijd en saldo."`

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing test**

Create `test/features/reports/balance_card_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/balance_card.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BalanceCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('formatSignedDuration always carries an explicit sign', () {
    expect(formatSignedDuration(const Duration(minutes: 90)), '+1:30');
    expect(formatSignedDuration(const Duration(minutes: -90)), '-1:30');
    expect(formatSignedDuration(Duration.zero), '+0:00');
  });

  testWidgets('without any target it points at the settings instead of a number', (tester) async {
    await pumpCard(tester);
    expect(find.text('Noch keine Soll-Arbeitszeit hinterlegt.'), findsOneWidget);
  });

  testWidgets('with a target it shows the overall balance', (tester) async {
    await db.appSettingsDao.updateSettings(targetMinutesMonday: 480);
    await pumpCard(tester);
    expect(find.text('Saldo gesamt'), findsOneWidget);
    expect(find.text('+0:00'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/reports/balance_card_test.dart --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log`
Expected: FAIL — `Target of URI doesn't exist: '.../balance_card.dart'`.

- [ ] **Step 4: Add the provider**

Append to `lib/features/reports/reports_providers.dart`:

```dart
/// The flex-time balance as of today, over the whole history — deliberately
/// not scoped to the report's selected range or its project/billable
/// filters: "overtime, but only for project X" is not a meaningful number.
final workTimeBalanceProvider = Provider<AsyncValue<Duration>>((ref) {
  final entries = ref.watch(allEntriesProvider);
  final settings = ref.watch(appSettingsProvider);
  if (entries.isLoading || settings.isLoading) return const AsyncValue.loading();
  final entryList = entries.value;
  final settingsRow = settings.value;
  if (entryList == null || settingsRow == null) return const AsyncValue.loading();
  return AsyncValue.data(
    runningBalance(
      dayBalances(entryList, settingsRow),
      settingsRow,
      asOf: DateTime.now(),
    ),
  );
});
```

Add these imports to that file:

```dart
import '../../core/di/app_settings_provider.dart';
import '../timer/timer_providers.dart' show allEntriesProvider;
import 'balance_calculations.dart';
```

- [ ] **Step 5: Write the card**

Create `lib/features/reports/balance_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import 'balance_calculations.dart';
import 'reports_providers.dart';

/// "+1:30" / "-0:45" — the sign is always explicit, because a balance of
/// "1:30" would be ambiguous between a surplus and a deficit. Deliberately
/// not the shared formatDuration, which has no notion of a sign.
String formatSignedDuration(Duration balance) {
  final sign = balance.isNegative ? '-' : '+';
  final absolute = balance.abs();
  final minutes = absolute.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '$sign${absolute.inHours}:$minutes';
}

/// The flex-time balance, as the Reports tab's first tile. Shows an empty
/// state pointing at Settings while no target is configured: with the
/// shipped defaults (every weekday 0) every tracked minute would otherwise
/// read as overtime.
class BalanceCard extends ConsumerWidget {
  const BalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();

    if (!hasAnyTarget(settings)) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: Text(l10n.reportsBalanceNoTargets),
          subtitle: Text(l10n.reportsBalanceConfigure),
        ),
      );
    }

    final cutoff = lastCutoffOnOrBefore(settings, DateTime.now());
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final label = cutoff == null
        ? l10n.reportsBalanceAllTime
        : l10n.reportsBalanceSince(DateFormat.yMd(localeName).format(cutoff));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ref.watch(workTimeBalanceProvider).when(
              data: (balance) {
                // Icon and colour together, never colour alone.
                final isDeficit = balance.isNegative;
                final color = isDeficit ? theme.colorScheme.error : theme.colorScheme.primary;
                return Row(
                  children: [
                    Icon(
                      isDeficit ? Icons.trending_down : Icons.trending_up,
                      color: color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
                    Text(
                      formatSignedDuration(balance),
                      style: theme.textTheme.headlineSmall?.copyWith(color: color),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(l10n.reportsError('$e')),
            ),
      ),
    );
  }
}
```

- [ ] **Step 6: Mount the card in the Reports tab**

In `lib/features/reports/reports_screen.dart`, add `import 'balance_card.dart';` and, inside `_ReportRangeAndBody.build`, insert between the `const SizedBox(height: 16)` that follows the chips row and the `Expanded(`:

```dart
        const BalanceCard(),
        const SizedBox(height: 16),
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/features/reports/ test/l10n/ --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: no `[E]` lines. If `reports_screen_test.dart` now fails with "A Timer is still pending even after the widget tree was disposed", the harness is subscribing to a live drift stream — add `appDatabaseProvider.overrideWithValue(<in-memory db>)` to its `ProviderScope`, the same trap documented at `test/features/entries/quick_add_bar_test.dart:49`.

- [ ] **Step 8: Run the whole suite and the analyzer**

Run: `flutter analyze > /tmp/analyze.log 2>&1; tail -3 /tmp/analyze.log; flutter test --reporter expanded > /tmp/test.log 2>&1; grep '\[E\]' /tmp/test.log; tail -3 /tmp/test.log`
Expected: `No issues found!` and no `[E]` lines.

- [ ] **Step 9: Update the memory files and the changelog**

Create `docs/memory/features/work-time-balance.md` recording: the seven weekday columns are the single source of truth (the weekly mode is input-only); the cutoff is a single forward pass, never recursive; balance ignores the report filters on purpose; the empty state exists because a fresh install has all-zero targets. Add a row to `docs/memory/features.md`:

```markdown
| Work-time balance | Target hours, cutoff rule, flex-time balance tile | [work-time-balance.md](features/work-time-balance.md) |
```

Add to `CHANGELOG.md` under `## [Unreleased]` → `### Added`:

```markdown
- Configurable target work time, per weekday or per week, with a yearly balance cutoff rule
- A flex-time balance tile in the Reports tab
```

- [ ] **Step 10: Commit**

```bash
git add lib/features/reports/balance_card.dart lib/features/reports/reports_providers.dart lib/features/reports/reports_screen.dart lib/l10n/ test/features/reports/balance_card_test.dart docs/memory/ CHANGELOG.md
git commit -m "feat(reports): show the work-time balance in the reports tab"
```
