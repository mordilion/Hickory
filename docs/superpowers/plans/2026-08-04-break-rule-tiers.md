# Break Rule Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each day's break time in `EntriesList`'s day header, flagged red with a
warning icon when it's below a configurable, tiered minimum-break rule, with Settings
presets (Germany/Austria/Switzerland/None) that fill an otherwise freely editable list
of break-rule tiers.

**Architecture:** A new synced Drift table `BreakRuleTiers` (table → DAO → sync
wiring), following the exact existing pattern used by `Projects`/`TimeEntries`. A pure
Dart calculation module computes each day's actual break time (gaps between entries)
and the required break for a given worked duration (tier lookup) — no DB/Flutter
dependency, mirrors `report_calculations.dart`. A plain `StreamProvider` wires the DAO
into the widget tree. `EntriesList`'s day header and a new Settings section both
consume this.

**Tech Stack:** Flutter, Riverpod (plain providers — drift-generated types must not go
through `@riverpod` codegen, see Global Constraints), Drift.

**Full design:** `docs/superpowers/specs/2026-08-04-break-rule-tiers-design.md`

## Global Constraints

- English only in code, comments, and commit messages (repo convention).
- ARB template locale is **German** (`lib/l10n/app_de.arb`, `template-arb-file:
  app_de.arb` in `l10n.yaml`) — add the German string first, then the same key with a
  real translation to `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`,
  `app_nl.arb`. `test/l10n/arb_completeness_test.dart` fails the build if any locale's
  key set diverges. After editing ARB files, run `flutter gen-l10n` before running any
  test that uses the new keys.
- Providers touching Drift-generated row classes (`TimeEntry`, `BreakRuleTier`, ...)
  must be **plain** `Provider`/`FutureProvider`/`StreamProvider`, not `@riverpod`
  codegen — mixing riverpod_generator with drift's generator in the same type trips
  `rrousselGit/riverpod#4323` (see `lib/features/reports/reports_providers.dart` and
  `lib/core/di/app_settings_provider.dart` for the existing precedent).
- Every new synced entity follows the exact existing pattern: Drift table → DAO →
  `EntityTypes` constant → `SyncedWrites` write-through method(s) →
  `SyncIngestor._applyMaterializedEntity` case → round-trip test in
  `test/data/sync_round_trip_test.dart`.
- No Dart records (`(int, int)` etc.) — the codebase has no existing record-type usage;
  use plain immutable classes instead, per `dart/architecture.md`'s immutable-class rule.
- Break time = sum of gaps between chronologically consecutive entries **within the
  same calendar day** only. It is unrelated to `TimeEntry.totalPausedSeconds` (the
  Timer's own pause button) — do not conflate the two.
- The red/insufficient state applies to every day shown, including today while it's
  still in progress — no special-casing "today" anywhere in this feature.
- Don't add fixed dependency version numbers by hand; this plan introduces no new
  third-party dependencies.
- After any Drift table/column change: run `dart run build_runner build
  --delete-conflicting-outputs` before running tests.

---

### Task 1: `BreakRuleTiers` table, DAO, migration, and provider

**Files:**
- Create: `lib/data/drift/tables/break_rule_tiers_table.dart`
- Create: `lib/data/drift/daos/break_rule_tiers_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Create: `lib/core/di/break_rule_tiers_provider.dart`
- Test: `test/data/drift/break_rule_tiers_dao_test.dart`

**Interfaces:**
- Produces: `BreakRuleTiers` table with `@DataClassName('BreakRuleTier')`, columns
  `id` (text, PK), `afterMinutes` (int), `requiredBreakMinutes` (int), `deviceId`
  (text), `createdAt`/`updatedAt` (datetime). `BreakRuleTiersDao` with
  `watchAllTiers()`, `getAllTiers()`, `createTier({required deviceId, afterMinutes,
  requiredBreakMinutes})`, `deleteTier(String id)`. `breakRuleTiersProvider` —
  `StreamProvider<List<BreakRuleTier>>`. `AppDatabase.schemaVersion == 6`.

- [ ] **Step 1: Create the table**

Create `lib/data/drift/tables/break_rule_tiers_table.dart`:

```dart
import 'package:drift/drift.dart';

/// A single break-time requirement: once a day's worked time reaches
/// [afterMinutes], at least [requiredBreakMinutes] of break time is
/// required that day. Multiple tiers let the user model tiered rules (e.g.
/// 30 min after 6h, 45 min after 9h) -- evaluation picks the tier with the
/// highest [afterMinutes] that the day's worked time has reached. Synced
/// across the user's own devices via the event log, like every other
/// entity. See docs/superpowers/specs/2026-08-04-break-rule-tiers-design.md.
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

Edit `lib/data/drift/database.dart`. Current content is:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/activity_samples_dao.dart';
import 'daos/app_settings_dao.dart';
import 'daos/events_dao.dart';
import 'daos/jira_worklogs_dao.dart';
import 'daos/projects_dao.dart';
import 'daos/time_entries_dao.dart';
import 'tables/activity_samples_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/clients_table.dart';
import 'tables/events_table.dart';
import 'tables/jira_worklogs_table.dart';
import 'tables/projects_table.dart';
import 'tables/sync_file_states_table.dart';
import 'tables/tags_table.dart';
import 'tables/time_entries_table.dart';
import 'tables/time_entry_tags_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Clients,
    Projects,
    Tags,
    TimeEntries,
    TimeEntryTags,
    Events,
    SyncFileStates,
    ActivitySamples,
    AppSettings,
    JiraWorklogs,
  ],
  daos: [ProjectsDao, TimeEntriesDao, EventsDao, ActivitySamplesDao, AppSettingsDao, JiraWorklogsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

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
        await m.addColumn(appSettings, appSettings.quickAddDurationsMinutes);
      }
    },
  );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'hickory.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
```

Replace it with:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/activity_samples_dao.dart';
import 'daos/app_settings_dao.dart';
import 'daos/break_rule_tiers_dao.dart';
import 'daos/events_dao.dart';
import 'daos/jira_worklogs_dao.dart';
import 'daos/projects_dao.dart';
import 'daos/time_entries_dao.dart';
import 'tables/activity_samples_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/break_rule_tiers_table.dart';
import 'tables/clients_table.dart';
import 'tables/events_table.dart';
import 'tables/jira_worklogs_table.dart';
import 'tables/projects_table.dart';
import 'tables/sync_file_states_table.dart';
import 'tables/tags_table.dart';
import 'tables/time_entries_table.dart';
import 'tables/time_entry_tags_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Clients,
    Projects,
    Tags,
    TimeEntries,
    TimeEntryTags,
    Events,
    SyncFileStates,
    ActivitySamples,
    AppSettings,
    JiraWorklogs,
    BreakRuleTiers,
  ],
  daos: [
    ProjectsDao,
    TimeEntriesDao,
    EventsDao,
    ActivitySamplesDao,
    AppSettingsDao,
    JiraWorklogsDao,
    BreakRuleTiersDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 6;

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
        await m.addColumn(appSettings, appSettings.quickAddDurationsMinutes);
      }
      if (from < 6) {
        await m.createTable(breakRuleTiers);
      }
    },
  );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'hickory.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
```

- [ ] **Step 4: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors; `lib/data/drift/daos/break_rule_tiers_dao.g.dart`
and an updated `lib/data/drift/database.g.dart` are generated.

- [ ] **Step 5: Create the Riverpod provider**

Create `lib/core/di/break_rule_tiers_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import 'database_provider.dart';

// Plain (non-generated) provider -- see app_settings_provider.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final breakRuleTiersProvider = StreamProvider<List<BreakRuleTier>>((ref) {
  return ref.watch(appDatabaseProvider).breakRuleTiersDao.watchAllTiers();
});
```

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
git add lib/data/drift/tables/break_rule_tiers_table.dart lib/data/drift/daos/break_rule_tiers_dao.dart lib/data/drift/daos/break_rule_tiers_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/core/di/break_rule_tiers_provider.dart test/data/drift/break_rule_tiers_dao_test.dart
git commit -m "feat(db): add BreakRuleTiers table, DAO, and provider"
```

---

### Task 2: Cross-device sync wiring

**Files:**
- Modify: `lib/data/sync/entity_types.dart`
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `BreakRuleTiersDao` (Task 1), `breakRuleTiersProvider` (Task 1, not used
  in this task but confirms the DAO is wired).
- Produces: `BreakRuleTierValues` (immutable class: `afterMinutes`,
  `requiredBreakMinutes`). `SyncedWrites.createBreakRuleTier({required deviceId,
  afterMinutes, requiredBreakMinutes})`, `SyncedWrites.deleteBreakRuleTier(String
  id)`, `SyncedWrites.replaceBreakRuleTiers({required deviceId, required
  List<BreakRuleTierValues> tiers})`.

- [ ] **Step 1: Add the entity type constant**

Edit `lib/data/sync/entity_types.dart`. Current content:

```dart
/// String values used in [SyncEvent.entityType]. Kept as constants so the
/// writer (emitting events) and the ingestor (dispatching on entityType)
/// can't drift apart on the literal strings.
abstract final class EntityTypes {
  static const project = 'project';
  static const timeEntry = 'time_entry';
  static const client = 'client';
  static const tag = 'tag';
  static const activitySample = 'activity_sample';
  static const appSettings = 'app_settings';
  static const jiraWorklog = 'jira_worklog';
}
```

Replace it with:

```dart
/// String values used in [SyncEvent.entityType]. Kept as constants so the
/// writer (emitting events) and the ingestor (dispatching on entityType)
/// can't drift apart on the literal strings.
abstract final class EntityTypes {
  static const project = 'project';
  static const timeEntry = 'time_entry';
  static const client = 'client';
  static const tag = 'tag';
  static const activitySample = 'activity_sample';
  static const appSettings = 'app_settings';
  static const jiraWorklog = 'jira_worklog';
  static const breakRuleTier = 'break_rule_tier';
}
```

- [ ] **Step 2: Add the write-through methods to `SyncedWrites`**

Edit `lib/data/sync/synced_writes.dart`. Find this existing method (it ends the
`updateAppSettings` block):

```dart
    return updated;
  }

  /// Writes the given Jira sync-tracking row and logs it, so the state
```

Replace that snippet with (inserting the new class above `SyncedWrites` and the three
new methods between `updateAppSettings` and the Jira methods):

```dart
    return updated;
  }

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

  /// Replaces the entire tier list with [tiers] -- used when applying a
  /// preset in Settings. Deletes every existing tier, then creates the new
  /// set; each step is logged individually via [deleteBreakRuleTier] /
  /// [createBreakRuleTier], matching how every other multi-step write in
  /// this codebase logs one event per DAO call rather than inventing a
  /// batch-event concept.
  Future<void> replaceBreakRuleTiers({
    required String deviceId,
    required List<BreakRuleTierValues> tiers,
  }) async {
    final existing = await db.breakRuleTiersDao.getAllTiers();
    for (final tier in existing) {
      await deleteBreakRuleTier(tier.id);
    }
    for (final values in tiers) {
      await createBreakRuleTier(
        deviceId: deviceId,
        afterMinutes: values.afterMinutes,
        requiredBreakMinutes: values.requiredBreakMinutes,
      );
    }
  }

  /// Writes the given Jira sync-tracking row and logs it, so the state
```

No new import is needed for `BreakRuleTier` -- it's already visible via the existing
`import '../drift/database.dart';` at the top of the file (Drift generates the
`BreakRuleTier` data class into `database.g.dart`, a `part` of that same library).

Now add the `BreakRuleTierValues` class. Find the top of the file (right after the
imports, before the `SyncedWrites` class doc comment):

```dart
import 'package:drift/drift.dart' show Value;
import 'package:sync_engine/sync_engine.dart';
import 'package:uuid/uuid.dart';

import '../drift/database.dart';
import '../drift/tables/app_settings_table.dart' show appSettingsRowId;
import '../drift/tables/jira_worklogs_table.dart' show JiraWorklogStatus;
import 'entity_types.dart';
import 'sync_log_writer.dart';

/// Thin write-through wrapper around the DAOs: every mutation is applied to
```

Replace it with:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:sync_engine/sync_engine.dart';
import 'package:uuid/uuid.dart';

import '../drift/database.dart';
import '../drift/tables/app_settings_table.dart' show appSettingsRowId;
import '../drift/tables/jira_worklogs_table.dart' show JiraWorklogStatus;
import 'entity_types.dart';
import 'sync_log_writer.dart';

/// A single break-rule tier's editable values, used when applying a preset
/// (see [SyncedWrites.replaceBreakRuleTiers]) or creating one manually. Not
/// a Dart record: the codebase has no existing record-type usage, and a
/// plain immutable class matches house style.
class BreakRuleTierValues {
  const BreakRuleTierValues({required this.afterMinutes, required this.requiredBreakMinutes});

  final int afterMinutes;
  final int requiredBreakMinutes;
}

/// Thin write-through wrapper around the DAOs: every mutation is applied to
```

- [ ] **Step 3: Materialize `break_rule_tier` events in the ingestor**

Edit `lib/data/sync/sync_ingestor.dart`. Find the `jiraWorklog` case and the `default`
that follows it:

```dart
      case EntityTypes.jiraWorklog:
        if (entity.isDeleted) {
          await (db.delete(db.jiraWorklogs)..where((w) => w.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.jiraWorklogs)
              .insertOnConflictUpdate(JiraWorklogRow.fromJson(entity.payload!).toCompanion(true));
        }
      default:
```

Replace it with:

```dart
      case EntityTypes.jiraWorklog:
        if (entity.isDeleted) {
          await (db.delete(db.jiraWorklogs)..where((w) => w.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.jiraWorklogs)
              .insertOnConflictUpdate(JiraWorklogRow.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.breakRuleTier:
        if (entity.isDeleted) {
          await (db.delete(db.breakRuleTiers)..where((t) => t.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.breakRuleTiers)
              .insertOnConflictUpdate(BreakRuleTier.fromJson(entity.payload!).toCompanion(true));
        }
      default:
```

Also update `rebuildFromScratch` to clear `breakRuleTiers`. Find:

```dart
  Future<void> rebuildFromScratch() async {
    await db.eventsDao.clearAll();
    await db.transaction(() async {
      await db.delete(db.timeEntries).go();
      await db.delete(db.projects).go();
      await db.delete(db.jiraWorklogs).go();
    });
    await syncNow();
  }
```

Replace it with:

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

- [ ] **Step 4: Write the round-trip test**

Edit `test/data/sync_round_trip_test.dart`. The file ends with:

```dart
      expect(await readerDb.jiraWorklogsDao.getAll(), isEmpty);
    },
  );
}
```

Replace it with (adding a new test before the closing `}`):

```dart
      expect(await readerDb.jiraWorklogsDao.getAll(), isEmpty);
    },
  );

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

  test(
    'replaceBreakRuleTiers swaps the whole tier set and syncs the result',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      await writerWrites.createBreakRuleTier(
        deviceId: 'dev_a',
        afterMinutes: 120,
        requiredBreakMinutes: 10,
      );

      await writerWrites.replaceBreakRuleTiers(
        deviceId: 'dev_a',
        tiers: const [
          BreakRuleTierValues(afterMinutes: 360, requiredBreakMinutes: 30),
          BreakRuleTierValues(afterMinutes: 540, requiredBreakMinutes: 45),
        ],
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final tiers = await readerDb.breakRuleTiersDao.getAllTiers();
      expect(tiers, hasLength(2));
      expect(tiers.map((t) => t.afterMinutes), [360, 540]);
    },
  );
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS (all tests, including the two new ones)

- [ ] **Step 6: Commit**

```bash
git add lib/data/sync/entity_types.dart lib/data/sync/synced_writes.dart lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): propagate break rule tiers across devices"
```

---

### Task 3: Break-time calculation module and day-grouping wiring

**Files:**
- Create: `lib/features/entries/break_rule_calculations.dart`
- Modify: `lib/features/entries/day_grouping.dart`
- Test: `test/features/entries/break_rule_calculations_test.dart`
- Modify: `test/features/entries/day_grouping_test.dart`

**Interfaces:**
- Consumes: `BreakRuleTier` (Task 1, via `database.dart`).
- Produces: `Duration dayBreakDuration(List<TimeEntry> dayEntries)`, `Duration?
  requiredBreakForWorked(Duration workedDuration, List<BreakRuleTier> tiers)`.
  `EntryDayGroup` gains a `breakDuration` field (`Duration`, required, positioned
  after `totalDuration`).

- [ ] **Step 1: Write the failing tests for the calculation module**

Create `test/features/entries/break_rule_calculations_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/break_rule_calculations.dart';

TimeEntry _entry({required String id, required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: null,
    startAt: startAt,
    endAt: endAt,
    pausedAt: null,
    totalPausedSeconds: 0,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

BreakRuleTier _tier({required int afterMinutes, required int requiredBreakMinutes}) {
  final now = DateTime.utc(2026, 1, 1);
  return BreakRuleTier(
    id: 'tier-$afterMinutes',
    afterMinutes: afterMinutes,
    requiredBreakMinutes: requiredBreakMinutes,
    deviceId: 'device-1',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('dayBreakDuration', () {
    test('returns zero for no entries', () {
      expect(dayBreakDuration(const []), Duration.zero);
    });

    test('returns zero for a single entry', () {
      final entries = [
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      ];
      expect(dayBreakDuration(entries), Duration.zero);
    });

    test('sums the gap between two entries', () {
      final entries = [
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 12)),
        _entry(id: '2', startAt: DateTime(2026, 8, 1, 13), endAt: DateTime(2026, 8, 1, 17)),
      ];
      expect(dayBreakDuration(entries), const Duration(hours: 1));
    });

    test('sums gaps across more than two entries, regardless of input order', () {
      final entries = [
        // Deliberately out of chronological order.
        _entry(id: '3', startAt: DateTime(2026, 8, 1, 15), endAt: DateTime(2026, 8, 1, 17)),
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 11)),
        _entry(id: '2', startAt: DateTime(2026, 8, 1, 11, 30), endAt: DateTime(2026, 8, 1, 14)),
      ];
      // Gap 1->2: 11:00-11:30 = 30min. Gap 2->3: 14:00-15:00 = 1h.
      expect(dayBreakDuration(entries), const Duration(hours: 1, minutes: 30));
    });

    test('back-to-back entries contribute a zero gap', () {
      final entries = [
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 12)),
        _entry(id: '2', startAt: DateTime(2026, 8, 1, 12), endAt: DateTime(2026, 8, 1, 17)),
      ];
      expect(dayBreakDuration(entries), Duration.zero);
    });
  });

  group('requiredBreakForWorked', () {
    test('returns null when there are no tiers', () {
      expect(requiredBreakForWorked(const Duration(hours: 8), const []), isNull);
    });

    test('returns null when worked time is below every tier threshold', () {
      final tiers = [_tier(afterMinutes: 360, requiredBreakMinutes: 30)];
      expect(requiredBreakForWorked(const Duration(hours: 5), tiers), isNull);
    });

    test('returns the smallest tier exactly at its threshold', () {
      final tiers = [
        _tier(afterMinutes: 360, requiredBreakMinutes: 30),
        _tier(afterMinutes: 540, requiredBreakMinutes: 45),
      ];
      expect(
        requiredBreakForWorked(const Duration(hours: 6), tiers),
        const Duration(minutes: 30),
      );
    });

    test('returns the highest tier reached, given unordered tiers', () {
      final tiers = [
        _tier(afterMinutes: 540, requiredBreakMinutes: 45),
        _tier(afterMinutes: 360, requiredBreakMinutes: 30),
      ];
      expect(
        requiredBreakForWorked(const Duration(hours: 10), tiers),
        const Duration(minutes: 45),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/entries/break_rule_calculations_test.dart`
Expected: FAIL with "Error: Not found: 'package:hickory/features/entries/break_rule_calculations.dart'" (file doesn't exist yet)

- [ ] **Step 3: Implement the calculation module**

Create `lib/features/entries/break_rule_calculations.dart`:

```dart
import '../../data/drift/database.dart';

/// Sum of the gaps between chronologically consecutive entries in
/// [dayEntries] (all entries must share the same calendar day and have a
/// non-null [TimeEntry.endAt] -- guaranteed by [EntriesList]'s "finished
/// entries only" filter and day_grouping.dart's grouping). Entries are
/// sorted by [TimeEntry.startAt] first since callers make no ordering
/// guarantee. Overlapping or back-to-back entries contribute zero for that
/// gap. A day with 0 or 1 entries has zero break time. Mirrors
/// docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md's
/// "gaps between entries within the same calendar day" definition -- the
/// overnight gap into the next day is never part of this, and explicit
/// Timer-pause time ([TimeEntry.totalPausedSeconds]) is unrelated.
Duration dayBreakDuration(List<TimeEntry> dayEntries) {
  if (dayEntries.length < 2) return Duration.zero;
  final sorted = [...dayEntries]..sort((a, b) => a.startAt.compareTo(b.startAt));
  var total = Duration.zero;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].startAt.difference(sorted[i - 1].endAt!);
    if (gap > Duration.zero) total += gap;
  }
  return total;
}

/// The break time required once [workedDuration] is reached, per [tiers]:
/// the tier with the highest [BreakRuleTier.afterMinutes] that is `<=`
/// [workedDuration]'s minutes. Returns null if [tiers] is empty or every
/// tier's threshold exceeds [workedDuration] (no requirement yet).
Duration? requiredBreakForWorked(Duration workedDuration, List<BreakRuleTier> tiers) {
  final workedMinutes = workedDuration.inMinutes;
  BreakRuleTier? best;
  for (final tier in tiers) {
    if (tier.afterMinutes > workedMinutes) continue;
    if (best == null || tier.afterMinutes > best.afterMinutes) best = tier;
  }
  return best == null ? null : Duration(minutes: best.requiredBreakMinutes);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/entries/break_rule_calculations_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Write the failing test for day_grouping.dart's new field**

Edit `test/features/entries/day_grouping_test.dart`. Find:

```dart
  test("sums workedDuration across a day's entries into totalDuration", () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      _entry(id: '2', startAt: DateTime(2026, 8, 1, 11), endAt: DateTime(2026, 8, 1, 11, 30)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(1));
    expect(groups.single.totalDuration, const Duration(hours: 1, minutes: 30));
  });
```

Add this new test directly after it:

```dart

  test("computes breakDuration from gaps between a day's entries", () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 12)),
      _entry(id: '2', startAt: DateTime(2026, 8, 1, 13), endAt: DateTime(2026, 8, 1, 17)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(1));
    expect(groups.single.breakDuration, const Duration(hours: 1));
  });
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `flutter test test/features/entries/day_grouping_test.dart`
Expected: FAIL with "The named parameter 'breakDuration' is required" (or similar --
`EntryDayGroup` doesn't have the field yet)

- [ ] **Step 7: Add `breakDuration` to `EntryDayGroup`**

Edit `lib/features/entries/day_grouping.dart`. Current content:

```dart
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';

/// One calendar day's worth of entries for [EntriesList], with a
/// pre-summed [totalDuration] so the widget doesn't recompute it per frame.
class EntryDayGroup {
  const EntryDayGroup({required this.day, required this.entries, required this.totalDuration});

  /// Local midnight for this group's calendar day.
  final DateTime day;
  final List<TimeEntry> entries;
  final Duration totalDuration;
}

/// Groups [entries] by the local calendar day of [TimeEntry.startAt],
/// newest day first; entries within a day keep their input order. Each
/// group's [EntryDayGroup.totalDuration] is the sum of
/// [TimeEntryDuration.workedDuration] across that day's entries.
List<EntryDayGroup> groupEntriesByDay(List<TimeEntry> entries) {
  final entriesByDay = <DateTime, List<TimeEntry>>{};
  for (final entry in entries) {
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    entriesByDay.putIfAbsent(day, () => []).add(entry);
  }
  final sortedDays = entriesByDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in sortedDays)
      EntryDayGroup(
        day: day,
        entries: entriesByDay[day]!,
        totalDuration: entriesByDay[day]!.fold(
          Duration.zero,
          (sum, entry) => sum + entry.workedDuration,
        ),
      ),
  ];
}
```

Replace it with:

```dart
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';
import 'break_rule_calculations.dart';

/// One calendar day's worth of entries for [EntriesList], with pre-summed
/// [totalDuration] and [breakDuration] so the widget doesn't recompute them
/// per frame.
class EntryDayGroup {
  const EntryDayGroup({
    required this.day,
    required this.entries,
    required this.totalDuration,
    required this.breakDuration,
  });

  /// Local midnight for this group's calendar day.
  final DateTime day;
  final List<TimeEntry> entries;
  final Duration totalDuration;
  final Duration breakDuration;
}

/// Groups [entries] by the local calendar day of [TimeEntry.startAt],
/// newest day first; entries within a day keep their input order. Each
/// group's [EntryDayGroup.totalDuration] is the sum of
/// [TimeEntryDuration.workedDuration] across that day's entries, and
/// [EntryDayGroup.breakDuration] is [dayBreakDuration] applied to that
/// day's entries.
List<EntryDayGroup> groupEntriesByDay(List<TimeEntry> entries) {
  final entriesByDay = <DateTime, List<TimeEntry>>{};
  for (final entry in entries) {
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    entriesByDay.putIfAbsent(day, () => []).add(entry);
  }
  final sortedDays = entriesByDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in sortedDays)
      EntryDayGroup(
        day: day,
        entries: entriesByDay[day]!,
        totalDuration: entriesByDay[day]!.fold(
          Duration.zero,
          (sum, entry) => sum + entry.workedDuration,
        ),
        breakDuration: dayBreakDuration(entriesByDay[day]!),
      ),
  ];
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter test test/features/entries/day_grouping_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 9: Commit**

```bash
git add lib/features/entries/break_rule_calculations.dart lib/features/entries/day_grouping.dart test/features/entries/break_rule_calculations_test.dart test/features/entries/day_grouping_test.dart
git commit -m "feat(entries): add break-time calculation and day-grouping wiring"
```

---

### Task 4: Day-header break-time display in `EntriesList`

**Files:**
- Modify: `lib/features/entries/entries_list.dart`
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/entries/entries_list_test.dart`

**Interfaces:**
- Consumes: `breakRuleTiersProvider` (Task 1), `dayBreakDuration`/`requiredBreakForWorked`
  (Task 3, via `EntryDayGroup.breakDuration` and a local call to
  `requiredBreakForWorked`), `BreakRuleTierValues`/`BreakRuleTier` (Task 1/2).
- Produces: `_HeaderRow`/`_DayHeader` render break time; `l10n.entriesBreakLabel(String
  duration)` and `l10n.entriesBreakInsufficientTooltip`.

- [ ] **Step 1: Add the new ARB keys**

Edit `lib/l10n/app_de.arb`. Find:

```json
  "entriesEndBeforeStartError": "Ende muss nach dem Start liegen.",
  "entriesDeleteConfirmTitle": "Eintrag löschen?",
  "entriesDeleteConfirmMessage": "Dieser Eintrag wird endgültig gelöscht. Das kann nicht rückgängig gemacht werden.",
```

Replace it with:

```json
  "entriesEndBeforeStartError": "Ende muss nach dem Start liegen.",
  "entriesDeleteConfirmTitle": "Eintrag löschen?",
  "entriesDeleteConfirmMessage": "Dieser Eintrag wird endgültig gelöscht. Das kann nicht rückgängig gemacht werden.",
  "entriesBreakLabel": "Pause: {duration}",
  "@entriesBreakLabel": {
    "placeholders": {
      "duration": { "type": "String" }
    }
  },
  "entriesBreakInsufficientTooltip": "Pause zu kurz",
```

Edit `lib/l10n/app_en.arb`. Find:

```json
  "entriesEndBeforeStartError": "End must be after the start.",
  "entriesDeleteConfirmTitle": "Delete entry?",
  "entriesDeleteConfirmMessage": "This entry will be permanently deleted. This cannot be undone.",
```

Replace it with:

```json
  "entriesEndBeforeStartError": "End must be after the start.",
  "entriesDeleteConfirmTitle": "Delete entry?",
  "entriesDeleteConfirmMessage": "This entry will be permanently deleted. This cannot be undone.",
  "entriesBreakLabel": "Break: {duration}",
  "entriesBreakInsufficientTooltip": "Break too short",
```

Edit `lib/l10n/app_es.arb`. Find:

```json
  "entriesEndBeforeStartError": "El fin debe ser posterior al inicio.",
  "entriesDeleteConfirmTitle": "¿Eliminar entrada?",
  "entriesDeleteConfirmMessage": "Esta entrada se eliminará permanentemente. Esta acción no se puede deshacer.",
```

Replace it with:

```json
  "entriesEndBeforeStartError": "El fin debe ser posterior al inicio.",
  "entriesDeleteConfirmTitle": "¿Eliminar entrada?",
  "entriesDeleteConfirmMessage": "Esta entrada se eliminará permanentemente. Esta acción no se puede deshacer.",
  "entriesBreakLabel": "Pausa: {duration}",
  "entriesBreakInsufficientTooltip": "Pausa demasiado corta",
```

Edit `lib/l10n/app_fr.arb`. Find:

```json
  "entriesEndBeforeStartError": "La fin doit être postérieure au début.",
  "entriesDeleteConfirmTitle": "Supprimer l'entrée ?",
  "entriesDeleteConfirmMessage": "Cette entrée sera définitivement supprimée. Cette action est irréversible.",
```

Replace it with:

```json
  "entriesEndBeforeStartError": "La fin doit être postérieure au début.",
  "entriesDeleteConfirmTitle": "Supprimer l'entrée ?",
  "entriesDeleteConfirmMessage": "Cette entrée sera définitivement supprimée. Cette action est irréversible.",
  "entriesBreakLabel": "Pause : {duration}",
  "entriesBreakInsufficientTooltip": "Pause trop courte",
```

Edit `lib/l10n/app_it.arb`. Find:

```json
  "entriesEndBeforeStartError": "La fine deve essere successiva all'inizio.",
  "entriesDeleteConfirmTitle": "Eliminare la voce?",
  "entriesDeleteConfirmMessage": "Questa voce verrà eliminata definitivamente. Questa azione non può essere annullata.",
```

Replace it with:

```json
  "entriesEndBeforeStartError": "La fine deve essere successiva all'inizio.",
  "entriesDeleteConfirmTitle": "Eliminare la voce?",
  "entriesDeleteConfirmMessage": "Questa voce verrà eliminata definitivamente. Questa azione non può essere annullata.",
  "entriesBreakLabel": "Pausa: {duration}",
  "entriesBreakInsufficientTooltip": "Pausa troppo breve",
```

Edit `lib/l10n/app_nl.arb`. Find:

```json
  "entriesEndBeforeStartError": "Het einde moet na het begin liggen.",
  "entriesDeleteConfirmTitle": "Item verwijderen?",
  "entriesDeleteConfirmMessage": "Dit item wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.",
```

Replace it with:

```json
  "entriesEndBeforeStartError": "Het einde moet na het begin liggen.",
  "entriesDeleteConfirmTitle": "Item verwijderen?",
  "entriesDeleteConfirmMessage": "Dit item wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.",
  "entriesBreakLabel": "Pauze: {duration}",
  "entriesBreakInsufficientTooltip": "Pauze te kort",
```

- [ ] **Step 2: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes with no errors; `lib/l10n/app_localizations*.dart` are updated
with `entriesBreakLabel` and `entriesBreakInsufficientTooltip`.

- [ ] **Step 3: Write the failing widget tests**

Edit `test/features/entries/entries_list_test.dart`. Current content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({required String id, required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: 'Entry $id',
    startAt: startAt,
    endAt: endAt,
    pausedAt: null,
    totalPausedSeconds: 0,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Widget makeApp(List<TimeEntry> entries) => ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  testWidgets('groups entries under Today/Yesterday headers with totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
        _entry(id: '2', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
      ]),
    );
    await tester.pumpAndSettle();

    // Match the full header text ("Today · 01:00") rather than just the
    // duration substring: with a single entry per day, the day total equals
    // that entry's own duration, so a substring match on the duration alone
    // would also match the entry row's trailing duration text. The '24h'
    // settings override above maps to TimeFormatStyle.h24, which hides
    // seconds in both the header total and the entry row's own duration.
    expect(find.text('Today · 01:00'), findsOneWidget);
    expect(find.text('Yesterday · 00:30'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no finished entries', (tester) async {
    await tester.pumpWidget(makeApp(const []));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet.'), findsOneWidget);
  });
}
```

Replace it with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({required String id, required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: 'Entry $id',
    startAt: startAt,
    endAt: endAt,
    pausedAt: null,
    totalPausedSeconds: 0,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

BreakRuleTier _tier({required int afterMinutes, required int requiredBreakMinutes}) {
  final now = DateTime.utc(2026, 1, 1);
  return BreakRuleTier(
    id: 'tier-$afterMinutes',
    afterMinutes: afterMinutes,
    requiredBreakMinutes: requiredBreakMinutes,
    deviceId: 'device-1',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Widget makeApp(List<TimeEntry> entries, {List<BreakRuleTier> tiers = const []}) => ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          breakRuleTiersProvider.overrideWith((ref) => Stream.value(tiers)),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  testWidgets('groups entries under Today/Yesterday headers with totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
        _entry(id: '2', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
      ]),
    );
    await tester.pumpAndSettle();

    // Match the full header text ("Today · 01:00") rather than just the
    // duration substring: with a single entry per day, the day total equals
    // that entry's own duration, so a substring match on the duration alone
    // would also match the entry row's trailing duration text. The '24h'
    // settings override above maps to TimeFormatStyle.h24, which hides
    // seconds in both the header total and the entry row's own duration.
    expect(find.text('Today · 01:00'), findsOneWidget);
    expect(find.text('Yesterday · 00:30'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no finished entries', (tester) async {
    await tester.pumpWidget(makeApp(const []));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet.'), findsOneWidget);
  });

  testWidgets('shows break time in the day header when no rule is configured', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 2))),
        _entry(
          id: '2',
          startAt: today.add(const Duration(hours: 3)),
          endAt: today.add(const Duration(hours: 4)),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Break: 01:00'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets(
    'marks the break red with a warning icon when it is below the required tier, '
    'including for today',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      await tester.pumpWidget(
        makeApp(
          [
            _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 7))),
            _entry(
              id: '2',
              startAt: today.add(const Duration(hours: 7, minutes: 10)),
              endAt: today.add(const Duration(hours: 8)),
            ),
          ],
          tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Break: 00:10'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    },
  );

  testWidgets('does not mark the break red when it meets the required tier', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp(
        [
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 6))),
          _entry(
            id: '2',
            startAt: today.add(const Duration(hours: 6, minutes: 30)),
            endAt: today.add(const Duration(hours: 7, minutes: 30)),
          ),
        ],
        tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Break: 00:30'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
```

- [ ] **Step 4: Run the tests to verify the new ones fail**

Run: `flutter test test/features/entries/entries_list_test.dart`
Expected: the two pre-existing tests still PASS; the three new ones FAIL (either a
missing-provider-override analysis error until Step 5 lands, or a `findsOneWidget`
assertion failure since the break text doesn't render yet)

- [ ] **Step 5: Wire break-time display into `EntriesList`**

Edit `lib/features/entries/entries_list.dart`. Current content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'day_grouping.dart';
import 'manual_entry_dialog.dart';

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return Center(child: Text(l10n.entriesEmpty));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        final groups = groupEntriesByDay(finished);
        final rows = <_ListRow>[
          for (final group in groups) ...[
            _HeaderRow(group.day, group.totalDuration),
            for (final entry in group.entries) _EntryRow(entry),
          ],
        ];
        final localeName = Localizations.localeOf(context).languageCode;
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _HeaderRow) {
              return _DayHeader(
                day: row.day,
                total: row.total,
                l10n: l10n,
                dateStyle: dateStyle,
                timeStyle: timeStyle,
                localeName: localeName,
              );
            }
```

Replace it with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'break_rule_calculations.dart';
import 'day_grouping.dart';
import 'manual_entry_dialog.dart';

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
    final tiersAsync = ref.watch(breakRuleTiersProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return Center(child: Text(l10n.entriesEmpty));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
        final groups = groupEntriesByDay(finished);
        final rows = <_ListRow>[
          for (final group in groups) ...[
            _HeaderRow(
              group.day,
              group.totalDuration,
              group.breakDuration,
              requiredBreakForWorked(group.totalDuration, tiers),
            ),
            for (final entry in group.entries) _EntryRow(entry),
          ],
        ];
        final localeName = Localizations.localeOf(context).languageCode;
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _HeaderRow) {
              return _DayHeader(
                day: row.day,
                total: row.total,
                breakDuration: row.breakDuration,
                requiredBreak: row.requiredBreak,
                l10n: l10n,
                dateStyle: dateStyle,
                timeStyle: timeStyle,
                localeName: localeName,
              );
            }
```

Now find the `_HeaderRow` class:

```dart
class _HeaderRow extends _ListRow {
  _HeaderRow(this.day, this.total);
  final DateTime day;
  final Duration total;
}
```

Replace it with:

```dart
class _HeaderRow extends _ListRow {
  _HeaderRow(this.day, this.total, this.breakDuration, this.requiredBreak);
  final DateTime day;
  final Duration total;
  final Duration breakDuration;
  final Duration? requiredBreak;
}
```

Finally, find the entire `_DayHeader` class:

```dart
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.total,
    required this.l10n,
    required this.dateStyle,
    required this.timeStyle,
    required this.localeName,
  });

  final DateTime day;
  final Duration total;
  final AppLocalizations l10n;
  final DateFormatStyle dateStyle;
  final TimeFormatStyle timeStyle;
  final String localeName;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.entriesToday;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return l10n.entriesYesterday;
    return formatDate(day, dateStyle, localeName);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        l10n.entriesDayHeader(_label(), formatDuration(total, timeStyle)),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
```

Replace it with:

```dart
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.total,
    required this.breakDuration,
    required this.requiredBreak,
    required this.l10n,
    required this.dateStyle,
    required this.timeStyle,
    required this.localeName,
  });

  final DateTime day;
  final Duration total;
  final Duration breakDuration;
  final Duration? requiredBreak;
  final AppLocalizations l10n;
  final DateFormatStyle dateStyle;
  final TimeFormatStyle timeStyle;
  final String localeName;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.entriesToday;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return l10n.entriesYesterday;
    return formatDate(day, dateStyle, localeName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiredBreak = this.requiredBreak;
    final isInsufficient = requiredBreak != null && breakDuration < requiredBreak;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            l10n.entriesDayHeader(_label(), formatDuration(total, timeStyle)),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isInsufficient)
            Tooltip(
              message: l10n.entriesBreakInsufficientTooltip,
              child: Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
            ),
          Text(
            l10n.entriesBreakLabel(formatDuration(breakDuration, timeStyle)),
            style: isInsufficient
                ? theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error)
                : theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/entries/entries_list_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 7: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS (all tests)

- [ ] **Step 8: Commit**

```bash
git add lib/features/entries/entries_list.dart lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart test/features/entries/entries_list_test.dart
git commit -m "feat(entries): show break time in the day header, red when insufficient"
```

---

### Task 5: Settings break-rule editor

**Files:**
- Create: `lib/features/settings/break_rule_tiers_editor.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/settings/break_rule_tiers_editor_test.dart`

**Interfaces:**
- Consumes: `breakRuleTiersProvider` (Task 1), `BreakRuleTierValues` /
  `SyncedWrites.createBreakRuleTier` / `.deleteBreakRuleTier` / `.replaceBreakRuleTiers`
  (Task 2), `deviceIdProvider` (existing, `lib/core/di/device_id_provider.dart`),
  `syncedWritesProvider` (existing, `lib/core/di/sync_providers.dart`).
- Produces: `BreakRuleTiersEditor` widget, wired into `SettingsScreen`.

- [ ] **Step 1: Add the new ARB keys**

Edit `lib/l10n/app_de.arb`. Find the last existing settings key:

```json
  "settingsQuickAddNewDurationLabel": "Minuten",
```

Replace it with:

```json
  "settingsQuickAddNewDurationLabel": "Minuten",
  "settingsBreakRuleTitle": "Pausenregeln",
  "settingsBreakRuleDescription": "Legt fest, ab wie viel Arbeitszeit wie viel Pause nötig ist. Die Tagesübersicht warnt, wenn die Pause zu kurz war.",
  "settingsBreakRulePresetGermany": "Deutschland",
  "settingsBreakRulePresetAustria": "Österreich",
  "settingsBreakRulePresetSwitzerland": "Schweiz",
  "settingsBreakRuleNone": "Keine",
  "settingsBreakRuleTierLabel": "Ab {worked} → {breakTime} Pause",
  "@settingsBreakRuleTierLabel": {
    "placeholders": {
      "worked": { "type": "String" },
      "breakTime": { "type": "String" }
    }
  },
  "settingsBreakRuleRemoveTooltip": "Entfernen",
  "settingsBreakRuleAddLabel": "Regel hinzufügen",
  "settingsBreakRuleAddTitle": "Neue Pausenregel",
  "settingsBreakRuleAfterMinutesLabel": "Ab Minuten Arbeit",
  "settingsBreakRuleRequiredMinutesLabel": "Minuten Pause nötig",
```

Edit `lib/l10n/app_en.arb`. Find:

```json
  "settingsQuickAddNewDurationLabel": "Minutes",
```

Replace it with:

```json
  "settingsQuickAddNewDurationLabel": "Minutes",
  "settingsBreakRuleTitle": "Break rules",
  "settingsBreakRuleDescription": "Sets how much break time is required after how much work. The day overview warns when the break was too short.",
  "settingsBreakRulePresetGermany": "Germany",
  "settingsBreakRulePresetAustria": "Austria",
  "settingsBreakRulePresetSwitzerland": "Switzerland",
  "settingsBreakRuleNone": "None",
  "settingsBreakRuleTierLabel": "After {worked} → {breakTime} break",
  "settingsBreakRuleRemoveTooltip": "Remove",
  "settingsBreakRuleAddLabel": "Add rule",
  "settingsBreakRuleAddTitle": "New break rule",
  "settingsBreakRuleAfterMinutesLabel": "After minutes worked",
  "settingsBreakRuleRequiredMinutesLabel": "Minutes break required",
```

Edit `lib/l10n/app_es.arb`. Find:

```json
  "settingsQuickAddNewDurationLabel": "Minutos",
```

Replace it with:

```json
  "settingsQuickAddNewDurationLabel": "Minutos",
  "settingsBreakRuleTitle": "Reglas de descanso",
  "settingsBreakRuleDescription": "Define cuánto descanso se necesita a partir de cuánto tiempo trabajado. El resumen diario avisa si la pausa fue demasiado corta.",
  "settingsBreakRulePresetGermany": "Alemania",
  "settingsBreakRulePresetAustria": "Austria",
  "settingsBreakRulePresetSwitzerland": "Suiza",
  "settingsBreakRuleNone": "Ninguna",
  "settingsBreakRuleTierLabel": "Tras {worked} → {breakTime} de descanso",
  "settingsBreakRuleRemoveTooltip": "Eliminar",
  "settingsBreakRuleAddLabel": "Añadir regla",
  "settingsBreakRuleAddTitle": "Nueva regla de descanso",
  "settingsBreakRuleAfterMinutesLabel": "Tras minutos trabajados",
  "settingsBreakRuleRequiredMinutesLabel": "Minutos de descanso necesarios",
```

Edit `lib/l10n/app_fr.arb`. Find:

```json
  "settingsQuickAddNewDurationLabel": "Minutes",
```

Replace it with:

```json
  "settingsQuickAddNewDurationLabel": "Minutes",
  "settingsBreakRuleTitle": "Règles de pause",
  "settingsBreakRuleDescription": "Définit la pause requise en fonction du temps travaillé. Le résumé du jour avertit si la pause était trop courte.",
  "settingsBreakRulePresetGermany": "Allemagne",
  "settingsBreakRulePresetAustria": "Autriche",
  "settingsBreakRulePresetSwitzerland": "Suisse",
  "settingsBreakRuleNone": "Aucune",
  "settingsBreakRuleTierLabel": "Après {worked} → {breakTime} de pause",
  "settingsBreakRuleRemoveTooltip": "Supprimer",
  "settingsBreakRuleAddLabel": "Ajouter une règle",
  "settingsBreakRuleAddTitle": "Nouvelle règle de pause",
  "settingsBreakRuleAfterMinutesLabel": "Après minutes travaillées",
  "settingsBreakRuleRequiredMinutesLabel": "Minutes de pause requises",
```

Edit `lib/l10n/app_it.arb`. Find:

```json
  "settingsQuickAddNewDurationLabel": "Minuti",
```

Replace it with:

```json
  "settingsQuickAddNewDurationLabel": "Minuti",
  "settingsBreakRuleTitle": "Regole sulla pausa",
  "settingsBreakRuleDescription": "Definisce quanta pausa è necessaria in base al tempo lavorato. Il riepilogo giornaliero avvisa se la pausa è stata troppo breve.",
  "settingsBreakRulePresetGermany": "Germania",
  "settingsBreakRulePresetAustria": "Austria",
  "settingsBreakRulePresetSwitzerland": "Svizzera",
  "settingsBreakRuleNone": "Nessuna",
  "settingsBreakRuleTierLabel": "Dopo {worked} → {breakTime} di pausa",
  "settingsBreakRuleRemoveTooltip": "Rimuovi",
  "settingsBreakRuleAddLabel": "Aggiungi regola",
  "settingsBreakRuleAddTitle": "Nuova regola di pausa",
  "settingsBreakRuleAfterMinutesLabel": "Dopo minuti lavorati",
  "settingsBreakRuleRequiredMinutesLabel": "Minuti di pausa richiesti",
```

Edit `lib/l10n/app_nl.arb`. Find:

```json
  "settingsQuickAddNewDurationLabel": "Minuten",
```

Replace it with:

```json
  "settingsQuickAddNewDurationLabel": "Minuten",
  "settingsBreakRuleTitle": "Pauzeregels",
  "settingsBreakRuleDescription": "Bepaalt hoeveel pauze nodig is na hoeveel werktijd. Het dagoverzicht waarschuwt als de pauze te kort was.",
  "settingsBreakRulePresetGermany": "Duitsland",
  "settingsBreakRulePresetAustria": "Oostenrijk",
  "settingsBreakRulePresetSwitzerland": "Zwitserland",
  "settingsBreakRuleNone": "Geen",
  "settingsBreakRuleTierLabel": "Na {worked} → {breakTime} pauze",
  "settingsBreakRuleRemoveTooltip": "Verwijderen",
  "settingsBreakRuleAddLabel": "Regel toevoegen",
  "settingsBreakRuleAddTitle": "Nieuwe pauzeregel",
  "settingsBreakRuleAfterMinutesLabel": "Na minuten gewerkt",
  "settingsBreakRuleRequiredMinutesLabel": "Minuten pauze nodig",
```

- [ ] **Step 2: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes with no errors.

- [ ] **Step 3: Create the editor widget**

Create `lib/features/settings/break_rule_tiers_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart';
import '../../l10n/app_localizations.dart';

enum _PresetCountry { germany, austria, switzerland }

class _Preset {
  const _Preset({required this.country, required this.tiers});
  final _PresetCountry country;
  final List<BreakRuleTierValues> tiers;
}

const _presets = [
  _Preset(
    country: _PresetCountry.germany,
    tiers: [
      BreakRuleTierValues(afterMinutes: 360, requiredBreakMinutes: 30),
      BreakRuleTierValues(afterMinutes: 540, requiredBreakMinutes: 45),
    ],
  ),
  _Preset(
    country: _PresetCountry.austria,
    tiers: [BreakRuleTierValues(afterMinutes: 360, requiredBreakMinutes: 30)],
  ),
  _Preset(
    country: _PresetCountry.switzerland,
    tiers: [
      BreakRuleTierValues(afterMinutes: 330, requiredBreakMinutes: 15),
      BreakRuleTierValues(afterMinutes: 420, requiredBreakMinutes: 30),
      BreakRuleTierValues(afterMinutes: 540, requiredBreakMinutes: 60),
    ],
  ),
];

String _presetLabel(AppLocalizations l10n, _PresetCountry country) => switch (country) {
      _PresetCountry.germany => l10n.settingsBreakRulePresetGermany,
      _PresetCountry.austria => l10n.settingsBreakRulePresetAustria,
      _PresetCountry.switzerland => l10n.settingsBreakRulePresetSwitzerland,
    };

/// Settings-screen editor for the day header's break-time rule (see
/// EntriesList). Persists through the synced BreakRuleTiers table, so the
/// rule follows the user across devices, same as every other setting. See
/// docs/superpowers/specs/2026-08-04-break-rule-tiers-design.md.
class BreakRuleTiersEditor extends ConsumerWidget {
  const BreakRuleTiersEditor({super.key});

  Future<void> _applyPreset(WidgetRef ref, List<BreakRuleTierValues> tiers) async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.replaceBreakRuleTiers(deviceId: deviceId, tiers: tiers);
  }

  Future<void> _remove(WidgetRef ref, String id) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.deleteBreakRuleTier(id);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final afterController = TextEditingController();
    final requiredController = TextEditingController();
    final result = await showDialog<BreakRuleTierValues>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsBreakRuleAddTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: afterController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.settingsBreakRuleAfterMinutesLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: requiredController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.settingsBreakRuleRequiredMinutesLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final after = int.tryParse(afterController.text.trim());
              final required = int.tryParse(requiredController.text.trim());
              if (after == null || required == null || after <= 0 || required <= 0) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop(
                BreakRuleTierValues(afterMinutes: after, requiredBreakMinutes: required),
              );
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (result == null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.createBreakRuleTier(
      deviceId: deviceId,
      afterMinutes: result.afterMinutes,
      requiredBreakMinutes: result.requiredBreakMinutes,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tiersAsync = ref.watch(breakRuleTiersProvider);
    final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
    final settings = ref.watch(appSettingsProvider).value;
    final timeStyle = settings.timeStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsBreakRuleTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsBreakRuleDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              ActionChip(
                label: Text(_presetLabel(l10n, preset.country)),
                onPressed: () => _applyPreset(ref, preset.tiers),
              ),
            ActionChip(
              label: Text(l10n.settingsBreakRuleNone),
              onPressed: () => _applyPreset(ref, const []),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final tier in tiers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.settingsBreakRuleTierLabel(
                formatDuration(Duration(minutes: tier.afterMinutes), timeStyle),
                formatDuration(Duration(minutes: tier.requiredBreakMinutes), timeStyle),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.settingsBreakRuleRemoveTooltip,
              onPressed: () => _remove(ref, tier.id),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsBreakRuleAddLabel),
          onPressed: () => _add(context, ref),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Wire the editor into `SettingsScreen`**

Edit `lib/features/settings/settings_screen.dart`. Find:

```dart
import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';
```

Replace it with:

```dart
import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import 'break_rule_tiers_editor.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';
```

Then find the final part of `build()`:

```dart
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: QuickAddDurationsEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

Replace it with:

```dart
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: QuickAddDurationsEditor(),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BreakRuleTiersEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Write the widget tests**

Create `test/features/settings/break_rule_tiers_editor_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/break_rule_tiers_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

Future<void> pumpUntilTrue(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_break_rule_settings_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp({List<BreakRuleTier> tiers = const []}) => ProviderScope(
        overrides: [
          breakRuleTiersProvider.overrideWith((ref) => Stream.value(tiers)),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
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
          locale: const Locale('en'),
          home: const Scaffold(body: BreakRuleTiersEditor()),
        ),
      );

  testWidgets('tapping the Germany preset creates its two tiers', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Germany'));

    await pumpUntilTrue(
      tester,
      () async => (await db.select(db.breakRuleTiers).get()).length == 2,
    );

    final tiers = await db.select(db.breakRuleTiers).get();
    tiers.sort((a, b) => a.afterMinutes.compareTo(b.afterMinutes));
    expect(tiers.map((t) => t.afterMinutes), [360, 540]);
    expect(tiers.map((t) => t.requiredBreakMinutes), [30, 45]);
  });

  testWidgets('tapping a preset replaces any existing tiers rather than adding to them', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'old',
            afterMinutes: 120,
            requiredBreakMinutes: 10,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Austria'));

    await pumpUntilTrue(
      tester,
      () async {
        final rows = await db.select(db.breakRuleTiers).get();
        return rows.length == 1 && rows.single.afterMinutes == 360;
      },
    );

    final tiers = await db.select(db.breakRuleTiers).get();
    expect(tiers, hasLength(1));
    expect(tiers.single.afterMinutes, 360);
  });

  testWidgets('tapping None clears all tiers', (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'old',
            afterMinutes: 360,
            requiredBreakMinutes: 30,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('None'));

    await pumpUntilTrue(
      tester,
      () async => (await db.select(db.breakRuleTiers).get()).isEmpty,
    );

    expect(await db.select(db.breakRuleTiers).get(), isEmpty);
  });

  testWidgets('removing a tier deletes it', (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'tier-1',
            afterMinutes: 360,
            requiredBreakMinutes: 30,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));

    await pumpUntilTrue(
      tester,
      () async => (await db.select(db.breakRuleTiers).get()).isEmpty,
    );

    expect(await db.select(db.breakRuleTiers).get(), isEmpty);
  });

  testWidgets('adding a tier via the dialog persists it', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '300');
    await tester.enterText(find.byType(TextField).last, '20');
    await tester.tap(find.text('Save'));

    await pumpUntilTrue(
      tester,
      () async => (await db.select(db.breakRuleTiers).get()).isNotEmpty,
    );

    final tiers = await db.select(db.breakRuleTiers).get();
    expect(tiers, hasLength(1));
    expect(tiers.single.afterMinutes, 300);
    expect(tiers.single.requiredBreakMinutes, 20);
  });
}
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/settings/break_rule_tiers_editor_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 7: Run the full test suite and analyzer to check for regressions**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add lib/features/settings/break_rule_tiers_editor.dart lib/features/settings/settings_screen.dart lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart test/features/settings/break_rule_tiers_editor_test.dart
git commit -m "feat(settings): add break-rule presets and editable tier list"
```
