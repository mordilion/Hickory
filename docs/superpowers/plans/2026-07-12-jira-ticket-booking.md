# Jira Ticket Booking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a time entry carry an optional Jira ticket key and push it to Jira as a worklog via a manual "Sync to Jira" action, keeping Jira in sync with later local edits and deletes.

**Architecture:** A new `jiraTicketKey` column on `TimeEntries` plus a new `JiraWorklogs` tracking table (synced across the user's own devices via the existing event-log mechanism, same as `Projects`/`TimeEntries`). A `JiraSyncService` reconciles entries against tracking rows on demand, talking to Jira through a small `JiraClient` REST wrapper. Credentials live in per-device secure storage, never in the synced log.

**Tech Stack:** Flutter, Riverpod (plain providers — see rationale below), Drift, `http`, `flutter_secure_storage`, mocktail.

**Full design:** `docs/superpowers/specs/2026-07-12-jira-ticket-booking-design.md`

## Global Constraints

- English only in code, comments, and commit messages (repo convention).
- ARB template locale is **German** (`lib/l10n/app_de.arb`, `template-arb-file: app_de.arb` in `l10n.yaml`) — write the German string first, then add the same key with a real translation to `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`. `test/l10n/arb_completeness_test.dart` fails the build if any locale's key set diverges.
- Providers touching Drift-generated row classes (`TimeEntry`, `JiraWorklogRow`, ...) must be **plain** `Provider`/`FutureProvider`/`StreamProvider`, not `@riverpod` codegen — mixing riverpod_generator with drift's generator in the same type trips `rrousselGit/riverpod#4323` (see `lib/features/timer/timer_providers.dart` and `lib/core/di/sync_providers.dart` for the existing precedent).
- Never store Jira credentials (base URL, email, API token) anywhere that reaches the synced event log or the SQLite database — secure storage only, per device.
- Don't add fixed dependency version numbers by hand; use `flutter pub add <package>` so pub resolves and pins the current compatible version, matching how every other dependency in `pubspec.yaml` got there.
- Every new Dart file follows the existing DAO/provider/table conventions already in `lib/data/drift/` and `lib/core/di/` — read the referenced existing file in each task before writing the new one if anything here is unclear.

---

### Task 1: Data model — `jiraTicketKey` column, `JiraWorklogs` table, DAO, migration

**Files:**
- Modify: `lib/data/drift/tables/time_entries_table.dart`
- Create: `lib/data/drift/tables/jira_worklogs_table.dart`
- Create: `lib/data/drift/daos/jira_worklogs_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/sync/entity_types.dart`
- Test: `test/data/drift/jira_worklogs_dao_test.dart`

**Interfaces:**
- Produces: `JiraWorklogs` table with `@DataClassName('JiraWorklogRow')`, columns `id` (text, PK), `syncedTicketKey` (text, nullable), `jiraWorklogId` (text, nullable), `status` (text, default `JiraWorklogStatus.pending`), `lastError` (text, nullable), `syncedAt` (datetime, nullable). `JiraWorklogStatus` constants: `pending`, `synced`, `error`, `pendingDelete`. `JiraWorklogsDao` with `watchAll()`, `getAll()`, `getForEntry(String id)`, `upsert(Insertable<JiraWorklogRow>)`, `deleteForEntry(String id)`. `TimeEntries.jiraTicketKey` (text, nullable). `EntityTypes.jiraWorklog = 'jira_worklog'`. `AppDatabase.schemaVersion == 4`.

- [ ] **Step 1: Add the `jiraTicketKey` column to `TimeEntries`**

Edit `lib/data/drift/tables/time_entries_table.dart`, adding the column after `deviceId` (before `createdAt`):

```dart
  TextColumn get deviceId => text()();
  // Optional Jira issue key this entry books time against (e.g. "PROJ-123"),
  // independent of projectId. See
  // docs/superpowers/specs/2026-07-12-jira-ticket-booking-design.md.
  TextColumn get jiraTicketKey => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
```

- [ ] **Step 2: Create the `JiraWorklogs` table**

Create `lib/data/drift/tables/jira_worklogs_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Values used in [JiraWorklogRow.status].
abstract final class JiraWorklogStatus {
  static const pending = 'pending';
  static const synced = 'synced';
  static const error = 'error';
  static const pendingDelete = 'pendingDelete';
}

/// Tracks the Jira worklog sync state for one time entry (1:1, keyed by the
/// entry's own id). Deliberately has no `.references(TimeEntries, #id)` —
/// this row must be able to outlive its time entry so a delete can still be
/// pushed to Jira after the entry itself is gone locally (see
/// [JiraWorklogStatus.pendingDelete]).
///
/// Synced across the user's own devices via the event log, like every other
/// entity (see EntityTypes.jiraWorklog) — otherwise a second device
/// wouldn't know an entry was already pushed and would create a duplicate
/// worklog on its own next sync.
@DataClassName('JiraWorklogRow')
class JiraWorklogs extends Table {
  TextColumn get id => text()();
  // Issue key the worklog currently exists under in Jira; null until the
  // first successful push.
  TextColumn get syncedTicketKey => text().nullable()();
  // Jira-assigned worklog id; null until the first successful push.
  TextColumn get jiraWorklogId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant(JiraWorklogStatus.pending))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 3: Create the `JiraWorklogsDao`**

Create `lib/data/drift/daos/jira_worklogs_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/jira_worklogs_table.dart';

part 'jira_worklogs_dao.g.dart';

@DriftAccessor(tables: [JiraWorklogs])
class JiraWorklogsDao extends DatabaseAccessor<AppDatabase> with _$JiraWorklogsDaoMixin {
  JiraWorklogsDao(super.db);

  Stream<List<JiraWorklogRow>> watchAll() => select(jiraWorklogs).watch();

  Future<List<JiraWorklogRow>> getAll() => select(jiraWorklogs).get();

  Future<JiraWorklogRow?> getForEntry(String timeEntryId) {
    return (select(jiraWorklogs)..where((w) => w.id.equals(timeEntryId))).getSingleOrNull();
  }

  Future<void> upsert(Insertable<JiraWorklogRow> row) {
    return into(jiraWorklogs).insertOnConflictUpdate(row);
  }

  Future<void> deleteForEntry(String timeEntryId) {
    return (delete(jiraWorklogs)..where((w) => w.id.equals(timeEntryId))).go();
  }
}
```

- [ ] **Step 4: Register the table/DAO and add the schema migration**

Edit `lib/data/drift/database.dart`. Add imports:

```dart
import 'daos/jira_worklogs_dao.dart';
import 'tables/jira_worklogs_table.dart';
```

Add `JiraWorklogs` to the `tables:` list and `JiraWorklogsDao` to the `daos:` list in the `@DriftDatabase(...)` annotation. Bump the version and extend the migration:

```dart
  @override
  int get schemaVersion => 4;

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
    },
  );
```

- [ ] **Step 5: Add the `jira_worklog` entity type constant**

Edit `lib/data/sync/entity_types.dart`, adding one line inside the class:

```dart
  static const jiraWorklog = 'jira_worklog';
```

- [ ] **Step 6: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors; `lib/data/drift/database.g.dart` and `lib/data/drift/daos/jira_worklogs_dao.g.dart` are (re)generated.

- [ ] **Step 7: Write the DAO test**

Create `test/data/drift/jira_worklogs_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert creates a pending row with no jiraWorklogId yet', () async {
    await db.jiraWorklogsDao.upsert(const JiraWorklogsCompanion.insert(id: 'entry_1'));

    final row = await db.jiraWorklogsDao.getForEntry('entry_1');
    expect(row, isNotNull);
    expect(row!.status, JiraWorklogStatus.pending);
    expect(row.jiraWorklogId, isNull);
  });

  test('upsert on an existing id updates it in place', () async {
    await db.jiraWorklogsDao.upsert(const JiraWorklogsCompanion.insert(id: 'entry_1'));
    await db.jiraWorklogsDao.upsert(
      JiraWorklogsCompanion.insert(
        id: 'entry_1',
        jiraWorklogId: const Value('10001'),
        syncedTicketKey: const Value('PROJ-1'),
        status: const Value(JiraWorklogStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 12)),
      ),
    );

    final rows = await db.jiraWorklogsDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.jiraWorklogId, '10001');
    expect(rows.single.status, JiraWorklogStatus.synced);
  });

  test('deleteForEntry removes the tracking row', () async {
    await db.jiraWorklogsDao.upsert(const JiraWorklogsCompanion.insert(id: 'entry_1'));
    await db.jiraWorklogsDao.deleteForEntry('entry_1');

    expect(await db.jiraWorklogsDao.getForEntry('entry_1'), isNull);
  });

  test('a time entry can carry an optional jiraTicketKey', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    expect(entry.jiraTicketKey, isNull);
  });
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `flutter test test/data/drift/jira_worklogs_dao_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 9: Commit**

```bash
git add lib/data/drift/tables/time_entries_table.dart lib/data/drift/tables/jira_worklogs_table.dart lib/data/drift/daos/jira_worklogs_dao.dart lib/data/drift/daos/jira_worklogs_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/sync/entity_types.dart test/data/drift/jira_worklogs_dao_test.dart
git commit -m "feat(db): add jiraTicketKey column and JiraWorklogs tracking table"
```

---

### Task 2: Cross-device sync wiring for `JiraWorklogs`

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `JiraWorklogsDao` (Task 1), `EntityTypes.jiraWorklog` (Task 1).
- Produces: `SyncedWrites.upsertJiraWorklogState(JiraWorklogRow row)` and `SyncedWrites.deleteJiraWorklogState(String timeEntryId)` — used by Task 3 and the `JiraSyncService` (Task 6).

- [ ] **Step 1: Add the write-through methods to `SyncedWrites`**

Edit `lib/data/sync/synced_writes.dart`, adding after `updateAppSettings`:

```dart
  /// Writes the given Jira sync-tracking row and logs it, so the state
  /// (e.g. "this entry now has a Jira worklog") propagates to the user's
  /// other devices the same way every other entity does.
  Future<void> upsertJiraWorklogState(JiraWorklogRow row) async {
    await db.jiraWorklogsDao.upsert(row.toCompanion(true));
    await logWriter.appendEvent(
      entityType: EntityTypes.jiraWorklog,
      entityId: row.id,
      op: EventOp.update,
      payload: row.toJson(),
    );
  }

  /// Removes a Jira sync-tracking row (used once a pending delete has been
  /// pushed to Jira, or when a row was never pushed and no longer needs
  /// tracking) and logs the tombstone.
  Future<void> deleteJiraWorklogState(String timeEntryId) async {
    await db.jiraWorklogsDao.deleteForEntry(timeEntryId);
    await logWriter.appendEvent(
      entityType: EntityTypes.jiraWorklog,
      entityId: timeEntryId,
      op: EventOp.delete,
      payload: null,
    );
  }
```

- [ ] **Step 2: Materialize `jira_worklog` events in the ingestor**

Edit `lib/data/sync/sync_ingestor.dart`, adding a case to `_applyMaterializedEntity`'s switch, after the `EntityTypes.appSettings` case and before `default`:

```dart
      case EntityTypes.jiraWorklog:
        if (entity.isDeleted) {
          await (db.delete(db.jiraWorklogs)..where((w) => w.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.jiraWorklogs)
              .insertOnConflictUpdate(JiraWorklogRow.fromJson(entity.payload!).toCompanion(true));
        }
```

Also update `rebuildFromScratch` to clear `jiraWorklogs` alongside `timeEntries`/`projects`, so a rebuild starts from the same clean slate for every deletable entity type:

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

- [ ] **Step 3: Write the round-trip test**

Edit `test/data/sync_round_trip_test.dart`, adding a new test at the end of `main()`, before the closing `}`:

```dart
  test(
    'a jira worklog tracking row syncs to a second device, including a later update',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final entry = await writerWrites.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 7, 7, 9),
        endAt: DateTime.utc(2026, 7, 7, 10),
        jiraTicketKey: 'PROJ-1',
      );
      await writerWrites.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: 'PROJ-1',
          jiraWorklogId: '10001',
          status: JiraWorklogStatus.synced,
          lastError: null,
          syncedAt: DateTime.utc(2026, 7, 7, 10),
        ),
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final worklogs = await readerDb.jiraWorklogsDao.getAll();
      expect(worklogs, hasLength(1));
      expect(worklogs.single.jiraWorklogId, '10001');
      expect(worklogs.single.status, JiraWorklogStatus.synced);

      // Device B doesn't know the entry was already pushed unless the
      // tracking row itself synced — this is the correctness property the
      // design doc calls out as the reason JiraWorklogs must be synced.
      await writerWrites.deleteJiraWorklogState(entry.id);
      await ingestor.syncNow();

      expect(await readerDb.jiraWorklogsDao.getAll(), isEmpty);
    },
  );
```

Add the import at the top of the file:

```dart
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS (4 tests total, including the 3 pre-existing ones)

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/synced_writes.dart lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): propagate jira worklog tracking rows across devices"
```

---

### Task 3: `jiraTicketKey` on entry create/update, pendingDelete on entry delete

**Files:**
- Modify: `lib/data/drift/daos/time_entries_dao.dart`
- Modify: `lib/data/sync/synced_writes.dart`
- Test: `test/data/synced_writes_jira_test.dart`

**Interfaces:**
- Consumes: `JiraWorklogsDao.getForEntry` (Task 1), `SyncedWrites.upsertJiraWorklogState`/`deleteJiraWorklogState` (Task 2).
- Produces: `TimeEntriesDao.startEntry`/`createManualEntry` gain `String? jiraTicketKey`; `TimeEntriesDao.updateEntry` gains `Value<String?> jiraTicketKey`; `TimeEntriesDao.getAllEntries()` (one-shot list, used by `JiraSyncService` in Task 6). `SyncedWrites` mirrors the same params through and `SyncedWrites.deleteEntry` now reconciles any existing `JiraWorklogs` row before deleting.

- [ ] **Step 1: Add `jiraTicketKey` support and `getAllEntries` to `TimeEntriesDao`**

Edit `lib/data/drift/daos/time_entries_dao.dart`. Update `startEntry`:

```dart
  Future<TimeEntry> startEntry({
    required String deviceId,
    String? projectId,
    String? description,
    String? jiraTicketKey,
  }) async {
    final now = DateTime.now().toUtc();
    final entry = TimeEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: Value(projectId),
      description: Value(description),
      jiraTicketKey: Value(jiraTicketKey),
      startAt: now,
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(timeEntries).insert(entry);
    return (select(timeEntries)..where((t) => t.id.equals(entry.id.value))).getSingle();
  }
```

Update `createManualEntry`:

```dart
  Future<TimeEntry> createManualEntry({
    required String deviceId,
    required DateTime startAt,
    required DateTime endAt,
    String? projectId,
    String? description,
    String? jiraTicketKey,
  }) async {
    final now = DateTime.now().toUtc();
    final entry = TimeEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: Value(projectId),
      description: Value(description),
      jiraTicketKey: Value(jiraTicketKey),
      startAt: startAt.toUtc(),
      endAt: Value(endAt.toUtc()),
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(timeEntries).insert(entry);
    return (select(timeEntries)..where((t) => t.id.equals(entry.id.value))).getSingle();
  }
```

Update `updateEntry`:

```dart
  Future<void> updateEntry(
    String id, {
    Value<String?> projectId = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> jiraTicketKey = const Value.absent(),
    Value<DateTime> startAt = const Value.absent(),
    Value<DateTime?> endAt = const Value.absent(),
  }) {
    return (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(
        projectId: projectId,
        description: description,
        jiraTicketKey: jiraTicketKey,
        startAt: startAt,
        endAt: endAt,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
```

Add a one-shot list method, next to `watchAllEntries`:

```dart
  /// One-shot counterpart to [watchAllEntries], for the Jira sync
  /// reconciliation pass (JiraSyncService), which needs a plain snapshot
  /// rather than a live stream.
  Future<List<TimeEntry>> getAllEntries() => select(timeEntries).get();
```

- [ ] **Step 2: Mirror the params and add delete reconciliation in `SyncedWrites`**

Edit `lib/data/sync/synced_writes.dart`. Update `startEntry`:

```dart
  Future<TimeEntry> startEntry({
    required String deviceId,
    String? projectId,
    String? description,
    String? jiraTicketKey,
  }) async {
    final entry = await db.timeEntriesDao.startEntry(
      deviceId: deviceId,
      projectId: projectId,
      description: description,
      jiraTicketKey: jiraTicketKey,
    );
    await _logCurrentState(entry.id, EventOp.create);
    return entry;
  }
```

Update `createManualEntry`:

```dart
  Future<TimeEntry> createManualEntry({
    required String deviceId,
    required DateTime startAt,
    required DateTime endAt,
    String? projectId,
    String? description,
    String? jiraTicketKey,
  }) async {
    final entry = await db.timeEntriesDao.createManualEntry(
      deviceId: deviceId,
      startAt: startAt,
      endAt: endAt,
      projectId: projectId,
      description: description,
      jiraTicketKey: jiraTicketKey,
    );
    await _logCurrentState(entry.id, EventOp.create);
    return entry;
  }
```

Update `updateEntry`:

```dart
  Future<void> updateEntry(
    String id, {
    Value<String?> projectId = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> jiraTicketKey = const Value.absent(),
    Value<DateTime> startAt = const Value.absent(),
    Value<DateTime?> endAt = const Value.absent(),
  }) async {
    await db.timeEntriesDao.updateEntry(
      id,
      projectId: projectId,
      description: description,
      jiraTicketKey: jiraTicketKey,
      startAt: startAt,
      endAt: endAt,
    );
    await _logCurrentState(id, EventOp.update);
  }
```

Update `deleteEntry`:

```dart
  Future<void> deleteEntry(String id) async {
    final worklog = await db.jiraWorklogsDao.getForEntry(id);
    if (worklog != null) {
      if (worklog.jiraWorklogId == null) {
        await deleteJiraWorklogState(id);
      } else {
        await upsertJiraWorklogState(worklog.copyWith(status: JiraWorklogStatus.pendingDelete));
      }
    }
    await db.timeEntriesDao.deleteEntry(id);
    await logWriter.appendEvent(
      entityType: EntityTypes.timeEntry,
      entityId: id,
      op: EventOp.delete,
      payload: null,
    );
  }
```

Add the import needed for `JiraWorklogStatus` at the top of the file:

```dart
import '../drift/tables/jira_worklogs_table.dart' show JiraWorklogStatus;
```

- [ ] **Step 3: Write the test**

Create `test/data/synced_writes_jira_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_jira_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('createManualEntry persists the optional jiraTicketKey', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-42',
    );

    expect(entry.jiraTicketKey, 'PROJ-42');
  });

  test('deleteEntry marks a pushed worklog pendingDelete instead of removing it', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-42',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: 'PROJ-42',
        jiraWorklogId: '10001',
        status: JiraWorklogStatus.synced,
        lastError: null,
        syncedAt: DateTime.utc(2026, 7, 7, 10),
      ),
    );

    await writes.deleteEntry(entry.id);

    final remainingEntry =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    expect(remainingEntry, isNull);

    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog, isNotNull);
    expect(worklog!.status, JiraWorklogStatus.pendingDelete);
  });

  test('deleteEntry removes the tracking row outright if it was never pushed', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-42',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: null,
        jiraWorklogId: null,
        status: JiraWorklogStatus.error,
        lastError: 'network error',
        syncedAt: null,
      ),
    );

    await writes.deleteEntry(entry.id);

    expect(await db.jiraWorklogsDao.getForEntry(entry.id), isNull);
  });
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/synced_writes_jira_test.dart test/data/drift/time_entries_dao_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/drift/daos/time_entries_dao.dart lib/data/sync/synced_writes.dart test/data/synced_writes_jira_test.dart
git commit -m "feat(entries): support jiraTicketKey and reconcile jira state on delete"
```

---

### Task 4: Jira credentials storage

**Files:**
- Create: `lib/features/jira/jira_credentials_store.dart`
- Create: `lib/features/jira/secure_jira_credentials_store.dart`
- Modify: `pubspec.yaml` (via `flutter pub add`)

**Interfaces:**
- Produces: `JiraCredentials {baseUrl, email, apiToken}`, abstract `JiraCredentialsStore {read(), write(JiraCredentials), clear()}`, `SecureJiraCredentialsStore implements JiraCredentialsStore`. Consumed by Task 7 (providers) and Task 12 (Sync screen UI).

**Note on testing:** `SecureJiraCredentialsStore` is a thin pass-through to `flutter_secure_storage` (a platform plugin) with no branching logic of its own — same situation as this codebase's existing `lib/core/di/device_id_provider.dart`, which also does direct platform I/O and has no dedicated unit test. Mocking the plugin's platform channel here would be fragile (channel details vary by platform backend) for no real gain, so this task is verified by static analysis and by the interface being exercised through the fakes used in later tasks' tests, not a dedicated test file.

- [ ] **Step 1: Add the new dependencies**

Run: `flutter pub add http flutter_secure_storage`
Expected: `pubspec.yaml` gains `http:` and `flutter_secure_storage:` entries under `dependencies:`, `flutter pub get` completes without errors.

- [ ] **Step 2: Define the credentials model and interface**

Create `lib/features/jira/jira_credentials_store.dart`:

```dart
/// Jira Cloud connection details needed to call the REST API.
class JiraCredentials {
  const JiraCredentials({required this.baseUrl, required this.email, required this.apiToken});

  final String baseUrl;
  final String email;
  final String apiToken;
}

/// Reads/writes the Jira connection details this device uses to talk to
/// Jira. Deliberately per-device and never synced — see the design doc for
/// why secrets must not enter the synced event log.
abstract class JiraCredentialsStore {
  Future<JiraCredentials?> read();
  Future<void> write(JiraCredentials credentials);
  Future<void> clear();
}
```

- [ ] **Step 3: Implement the secure-storage-backed store**

Create `lib/features/jira/secure_jira_credentials_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'jira_credentials_store.dart';

class SecureJiraCredentialsStore implements JiraCredentialsStore {
  SecureJiraCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _baseUrlKey = 'jira_base_url';
  static const _emailKey = 'jira_email';
  static const _apiTokenKey = 'jira_api_token';

  @override
  Future<JiraCredentials?> read() async {
    final baseUrl = await _storage.read(key: _baseUrlKey);
    final email = await _storage.read(key: _emailKey);
    final apiToken = await _storage.read(key: _apiTokenKey);
    if (baseUrl == null || email == null || apiToken == null) return null;
    return JiraCredentials(baseUrl: baseUrl, email: email, apiToken: apiToken);
  }

  @override
  Future<void> write(JiraCredentials credentials) async {
    await _storage.write(key: _baseUrlKey, value: credentials.baseUrl);
    await _storage.write(key: _emailKey, value: credentials.email);
    await _storage.write(key: _apiTokenKey, value: credentials.apiToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _baseUrlKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _apiTokenKey);
  }
}
```

- [ ] **Step 4: Verify it compiles cleanly**

Run: `dart analyze lib/features/jira`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/jira/jira_credentials_store.dart lib/features/jira/secure_jira_credentials_store.dart
git commit -m "feat(jira): add per-device secure credentials storage"
```

---

### Task 5: `JiraClient` — REST API wrapper

**Files:**
- Create: `lib/features/jira/jira_client.dart`
- Create: `lib/features/jira/http_jira_client.dart`
- Test: `test/features/jira/http_jira_client_test.dart`

**Interfaces:**
- Consumes: `JiraCredentials` (Task 4).
- Produces: abstract `JiraClient {testConnection(), createWorklog(...), updateWorklog(...), deleteWorklog(...), searchIssues(String)}`, `JiraIssueSuggestion {key, summary}`, `JiraApiException`, `HttpJiraClient implements JiraClient`. Consumed by Task 6 (sync service), Task 7 (providers), Task 8 (autocomplete widget).

- [ ] **Step 1: Define the client interface**

Create `lib/features/jira/jira_client.dart`:

```dart
/// One issue-search result, as returned by Jira's issue picker.
class JiraIssueSuggestion {
  const JiraIssueSuggestion({required this.key, required this.summary});

  final String key;
  final String summary;
}

/// Raised for any non-2xx Jira response, or for a search response Jira
/// couldn't parse. Carries a caller-safe message (no tokens, no full
/// response bodies) suitable for surfacing in the UI.
class JiraApiException implements Exception {
  JiraApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the Jira REST API for worklog booking. Implementations must
/// throw [JiraApiException] on failure — callers rely on that to decide
/// whether a push succeeded.
abstract class JiraClient {
  /// Returns true if the configured credentials can authenticate against
  /// Jira, false otherwise. Never throws for an auth failure — only for
  /// transport-level errors.
  Future<bool> testConnection();

  /// Creates a worklog on [issueKey] and returns the new worklog's id.
  Future<String> createWorklog({
    required String issueKey,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  });

  Future<void> updateWorklog({
    required String issueKey,
    required String worklogId,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  });

  /// Deleting a worklog that's already gone (404) is treated as success —
  /// the end state the caller wants is "no worklog", which already holds.
  Future<void> deleteWorklog({required String issueKey, required String worklogId});

  /// Empty query returns no results without calling the network.
  Future<List<JiraIssueSuggestion>> searchIssues(String query);
}
```

- [ ] **Step 2: Implement the HTTP client**

Create `lib/features/jira/http_jira_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'jira_client.dart';
import 'jira_credentials_store.dart';

class HttpJiraClient implements JiraClient {
  HttpJiraClient({required JiraCredentials credentials, http.Client? httpClient})
    : _credentials = credentials,
      _httpClient = httpClient ?? http.Client();

  final JiraCredentials _credentials;
  final http.Client _httpClient;

  @override
  Future<bool> testConnection() async {
    final response = await _httpClient.get(_uri('/myself'), headers: _headers);
    return response.statusCode == 200;
  }

  @override
  Future<String> createWorklog({
    required String issueKey,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) async {
    final response = await _httpClient.post(
      _uri('/issue/$issueKey/worklog'),
      headers: _headers,
      body: jsonEncode(_worklogBody(timeSpent: timeSpent, startedAt: startedAt, comment: comment)),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw JiraApiException(
        'Failed to create worklog on $issueKey (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['id'] as String;
  }

  @override
  Future<void> updateWorklog({
    required String issueKey,
    required String worklogId,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) async {
    final response = await _httpClient.put(
      _uri('/issue/$issueKey/worklog/$worklogId'),
      headers: _headers,
      body: jsonEncode(_worklogBody(timeSpent: timeSpent, startedAt: startedAt, comment: comment)),
    );
    if (response.statusCode != 200) {
      throw JiraApiException(
        'Failed to update worklog $worklogId on $issueKey (HTTP ${response.statusCode}).',
      );
    }
  }

  @override
  Future<void> deleteWorklog({required String issueKey, required String worklogId}) async {
    final response = await _httpClient.delete(
      _uri('/issue/$issueKey/worklog/$worklogId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw JiraApiException(
        'Failed to delete worklog $worklogId on $issueKey (HTTP ${response.statusCode}).',
      );
    }
  }

  @override
  Future<List<JiraIssueSuggestion>> searchIssues(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _httpClient.get(_uri('/issue/picker', {'query': query}), headers: _headers);
    if (response.statusCode != 200) {
      throw JiraApiException('Issue search failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final sections = decoded['sections'] as List<dynamic>? ?? const [];
    return [
      for (final section in sections)
        for (final issue in (section as Map<String, dynamic>)['issues'] as List<dynamic>? ?? const [])
          JiraIssueSuggestion(
            key: (issue as Map<String, dynamic>)['key'] as String,
            summary: (issue['summaryText'] as String?) ?? '',
          ),
    ];
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _credentials.baseUrl.endsWith('/')
        ? _credentials.baseUrl.substring(0, _credentials.baseUrl.length - 1)
        : _credentials.baseUrl;
    return Uri.parse('$base/rest/api/2$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers {
    final basic = base64Encode(utf8.encode('${_credentials.email}:${_credentials.apiToken}'));
    return {
      'Authorization': 'Basic $basic',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _worklogBody({
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) {
    return {
      'timeSpentSeconds': timeSpent.inSeconds,
      'started': _formatStarted(startedAt),
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    };
  }

  /// Jira's worklog `started` field requires its own bespoke format —
  /// `yyyy-MM-ddTHH:mm:ss.SSSZZZZ` with milliseconds always three digits and
  /// no colon in the offset (`+0000`, not `+00:00`) — incompatible with
  /// [DateTime.toIso8601String], hence built by hand.
  String _formatStarted(DateTime dateTime) {
    final utc = dateTime.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
        '${two(utc.second)}.${three(utc.millisecond)}+0000';
  }
}
```

- [ ] **Step 2b: Run analysis to catch mistakes early**

Run: `dart analyze lib/features/jira`
Expected: `No issues found!`

- [ ] **Step 3: Write the test**

Create `test/features/jira/http_jira_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/jira/http_jira_client.dart';
import 'package:hickory/features/jira/jira_client.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const credentials = JiraCredentials(
    baseUrl: 'https://example.atlassian.net',
    email: 'me@example.com',
    apiToken: 'token-123',
  );

  test('testConnection returns true on HTTP 200', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/api/2/myself');
        expect(request.headers['Authorization'], startsWith('Basic '));
        return http.Response('{}', 200);
      }),
    );

    expect(await client.testConnection(), isTrue);
  });

  test('testConnection returns false on HTTP 401', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('{}', 401)),
    );

    expect(await client.testConnection(), isFalse);
  });

  test('createWorklog posts the expected body and returns the new id', () async {
    late Map<String, dynamic> sentBody;
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/api/2/issue/PROJ-1/worklog');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': '10050'}), 201);
      }),
    );

    final id = await client.createWorklog(
      issueKey: 'PROJ-1',
      timeSpent: const Duration(hours: 1, minutes: 30),
      startedAt: DateTime.utc(2026, 7, 7, 9, 0, 0),
      comment: 'Design review',
    );

    expect(id, '10050');
    expect(sentBody['timeSpentSeconds'], 5400);
    expect(sentBody['started'], '2026-07-07T09:00:00.000+0000');
    expect(sentBody['comment'], 'Design review');
  });

  test('createWorklog throws JiraApiException on a non-2xx response', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('not found', 404)),
    );

    expect(
      () => client.createWorklog(
        issueKey: 'PROJ-1',
        timeSpent: const Duration(minutes: 30),
        startedAt: DateTime.utc(2026, 7, 7),
      ),
      throwsA(isA<JiraApiException>()),
    );
  });

  test('updateWorklog puts to the worklog id path', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/rest/api/2/issue/PROJ-1/worklog/10050');
        return http.Response('{}', 200);
      }),
    );

    await client.updateWorklog(
      issueKey: 'PROJ-1',
      worklogId: '10050',
      timeSpent: const Duration(hours: 1),
      startedAt: DateTime.utc(2026, 7, 7, 9),
    );
  });

  test('deleteWorklog treats 404 as success', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.method, 'DELETE');
        return http.Response('', 404);
      }),
    );

    await client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10050');
  });

  test('deleteWorklog throws on other error codes', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('', 500)),
    );

    expect(
      () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10050'),
      throwsA(isA<JiraApiException>()),
    );
  });

  test('searchIssues returns an empty list for a blank query without a request', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => fail('should not be called')),
    );

    expect(await client.searchIssues('  '), isEmpty);
  });

  test('searchIssues parses issues out of every section', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['query'], 'PROJ');
        return http.Response(
          jsonEncode({
            'sections': [
              {
                'id': 'cs',
                'issues': [
                  {'key': 'PROJ-1', 'summaryText': 'First issue'},
                  {'key': 'PROJ-2', 'summaryText': 'Second issue'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    final results = await client.searchIssues('PROJ');

    expect(results, hasLength(2));
    expect(results.first.key, 'PROJ-1');
    expect(results.first.summary, 'First issue');
  });
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/jira/http_jira_client_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/jira/jira_client.dart lib/features/jira/http_jira_client.dart test/features/jira/http_jira_client_test.dart
git commit -m "feat(jira): add REST client for worklog CRUD and issue search"
```

---

### Task 6: `JiraSyncService` — reconciliation engine

**Files:**
- Create: `lib/features/jira/jira_sync_service.dart`
- Test: `test/features/jira/jira_sync_service_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (`jiraWorklogsDao`, `timeEntriesDao.getAllEntries()` — Tasks 1/3), `SyncedWrites.upsertJiraWorklogState`/`deleteJiraWorklogState` (Task 2), `JiraClient` (Task 5).
- Produces: `JiraSyncResult {created, updated, deleted, failed, total}`, `JiraSyncService(db:, client:, writes:).syncNow() → Future<JiraSyncResult>`. Consumed by Task 7 (providers) and Task 12 (Sync screen UI).

- [ ] **Step 1: Implement the service**

Create `lib/features/jira/jira_sync_service.dart`:

```dart
import 'package:drift/drift.dart' show Value;

import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../data/sync/synced_writes.dart';
import 'jira_client.dart';

/// Outcome of one [JiraSyncService.syncNow] run, for display in the UI.
class JiraSyncResult {
  const JiraSyncResult({
    required this.created,
    required this.updated,
    required this.deleted,
    required this.failed,
  });

  final int created;
  final int updated;
  final int deleted;
  final int failed;

  int get total => created + updated + deleted + failed;
}

enum _Outcome { created, updated, deleted, skipped, failed }

/// Reconciles every finished time entry's `jiraTicketKey` against Jira
/// worklogs, per the algorithm in
/// docs/superpowers/specs/2026-07-12-jira-ticket-booking-design.md. Pure
/// push: never reads worklogs Jira already knows about back into Hickory.
class JiraSyncService {
  JiraSyncService({required this.db, required this.client, required this.writes});

  final AppDatabase db;
  final JiraClient client;
  final SyncedWrites writes;

  Future<JiraSyncResult> syncNow() async {
    final worklogsByEntryId = {for (final w in await db.jiraWorklogsDao.getAll()) w.id: w};
    final counts = <_Outcome, int>{};

    for (final worklog in worklogsByEntryId.values) {
      if (worklog.status != JiraWorklogStatus.pendingDelete) continue;
      final outcome = await _reconcilePendingDelete(worklog);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    final entries = await db.timeEntriesDao.getAllEntries();
    for (final entry in entries) {
      if (entry.endAt == null) continue;
      final worklog = worklogsByEntryId[entry.id];
      if (worklog?.status == JiraWorklogStatus.pendingDelete) continue;
      final outcome = await _reconcileEntry(entry, worklog);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    return JiraSyncResult(
      created: counts[_Outcome.created] ?? 0,
      updated: counts[_Outcome.updated] ?? 0,
      deleted: counts[_Outcome.deleted] ?? 0,
      failed: counts[_Outcome.failed] ?? 0,
    );
  }

  /// Reduces any caught error to a message safe for `lastError`, which is
  /// stored locally AND propagated to every device via the synced event
  /// log: [JiraApiException]'s message is caller-safe by construction, but
  /// a raw transport exception's `toString()` (e.g. `SocketException`,
  /// `http.ClientException`) can embed the request URI — including the
  /// user's Jira base URL, one of the credential fields that must never
  /// leave this device (see the design doc's credentials-not-synced rule).
  String _safeErrorMessage(Object error) =>
      error is JiraApiException ? error.message : 'Network or connection error';

  Future<_Outcome> _reconcilePendingDelete(JiraWorklogRow worklog) async {
    try {
      if (worklog.jiraWorklogId != null && worklog.syncedTicketKey != null) {
        await client.deleteWorklog(
          issueKey: worklog.syncedTicketKey!,
          worklogId: worklog.jiraWorklogId!,
        );
      }
      await writes.deleteJiraWorklogState(worklog.id);
      return _Outcome.deleted;
    } catch (e) {
      // Deliberately does NOT change status away from pendingDelete: by the
      // time this row is reconciled, its TimeEntry is already gone (see
      // SyncedWrites.deleteEntry), so it's only ever revisited by the
      // pendingDelete branch above, never by _reconcileEntry's entries loop.
      // Flipping status to `error` here would orphan the row outside both
      // loops forever, leaking the Jira-side worklog and breaking the
      // "retried automatically on the next sync" guarantee.
      await writes.upsertJiraWorklogState(
        worklog.copyWith(lastError: Value(_safeErrorMessage(e))),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _reconcileEntry(TimeEntry entry, JiraWorklogRow? worklog) async {
    final ticketKey = entry.jiraTicketKey;

    if (ticketKey == null) {
      return _handleTicketRemoved(entry.id, worklog);
    }
    if (worklog == null) {
      return _pushCreate(entry: entry, ticketKey: ticketKey);
    }
    if (worklog.syncedTicketKey != null && worklog.syncedTicketKey != ticketKey) {
      return _pushMove(entry: entry, ticketKey: ticketKey, oldWorklog: worklog);
    }
    final needsUpdate = worklog.syncedAt == null || entry.updatedAt.isAfter(worklog.syncedAt!);
    if (!needsUpdate) return _Outcome.skipped;
    if (worklog.jiraWorklogId == null) {
      return _pushCreate(entry: entry, ticketKey: ticketKey);
    }
    return _pushUpdate(entry: entry, ticketKey: ticketKey, worklog: worklog);
  }

  Future<_Outcome> _handleTicketRemoved(String entryId, JiraWorklogRow? worklog) async {
    if (worklog == null) return _Outcome.skipped;
    if (worklog.jiraWorklogId == null) {
      await writes.deleteJiraWorklogState(entryId);
      return _Outcome.skipped;
    }
    await writes.upsertJiraWorklogState(worklog.copyWith(status: JiraWorklogStatus.pendingDelete));
    return _Outcome.skipped;
  }

  Future<_Outcome> _pushCreate({required TimeEntry entry, required String ticketKey}) async {
    try {
      final worklogId = await client.createWorklog(
        issueKey: ticketKey,
        timeSpent: entry.workedDuration,
        startedAt: entry.startAt,
        comment: entry.description,
      );
      await writes.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: ticketKey,
          jiraWorklogId: worklogId,
          status: JiraWorklogStatus.synced,
          lastError: null,
          syncedAt: DateTime.now().toUtc(),
        ),
      );
      return _Outcome.created;
    } catch (e) {
      await writes.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: null,
          jiraWorklogId: null,
          status: JiraWorklogStatus.error,
          lastError: _safeErrorMessage(e),
          syncedAt: null,
        ),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _pushMove({
    required TimeEntry entry,
    required String ticketKey,
    required JiraWorklogRow oldWorklog,
  }) async {
    if (oldWorklog.jiraWorklogId != null) {
      try {
        await client.deleteWorklog(
          issueKey: oldWorklog.syncedTicketKey!,
          worklogId: oldWorklog.jiraWorklogId!,
        );
      } catch (e) {
        // client.deleteWorklog already treats "already gone" (404) as
        // success, so anything reaching this catch is a genuine failure
        // (network/auth/500) — proceeding to create on the new ticket
        // regardless would leave the old worklog booked in Jira forever
        // with no record of it. Keep the old worklog's tracking as-is
        // (still `synced` to the OLD ticket) so this move is retried in
        // full on the next sync, instead of silently losing the old side.
        await writes.upsertJiraWorklogState(
          oldWorklog.copyWith(status: JiraWorklogStatus.error, lastError: Value(_safeErrorMessage(e))),
        );
        return _Outcome.failed;
      }
    }
    final outcome = await _pushCreate(entry: entry, ticketKey: ticketKey);
    return outcome == _Outcome.created ? _Outcome.updated : _Outcome.failed;
  }

  Future<_Outcome> _pushUpdate({
    required TimeEntry entry,
    required String ticketKey,
    required JiraWorklogRow worklog,
  }) async {
    try {
      await client.updateWorklog(
        issueKey: ticketKey,
        worklogId: worklog.jiraWorklogId!,
        timeSpent: entry.workedDuration,
        startedAt: entry.startAt,
        comment: entry.description,
      );
      await writes.upsertJiraWorklogState(
        worklog.copyWith(
          syncedTicketKey: Value(ticketKey),
          status: JiraWorklogStatus.synced,
          syncedAt: Value(DateTime.now().toUtc()),
          lastError: const Value(null),
        ),
      );
      return _Outcome.updated;
    } catch (e) {
      await writes.upsertJiraWorklogState(
        worklog.copyWith(status: JiraWorklogStatus.error, lastError: Value(_safeErrorMessage(e))),
      );
      return _Outcome.failed;
    }
  }
}
```

- [ ] **Step 2: Write the test**

Create `test/features/jira/jira_sync_service_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/jira/jira_client.dart';
import 'package:hickory/features/jira/jira_sync_service.dart';
import 'package:mocktail/mocktail.dart';

class MockJiraClient extends Mock implements JiraClient {}

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;
  late MockJiraClient client;
  late JiraSyncService service;

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026, 7, 7));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_jira_sync_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
    client = MockJiraClient();
    service = JiraSyncService(db: db, client: client, writes: writes);
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('creates a worklog for a finished entry with a ticket and no tracking row yet', () async {
    when(
      () => client.createWorklog(
        issueKey: any(named: 'issueKey'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async => '10001');

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
      description: 'Design review',
    );

    final result = await service.syncNow();

    expect(result.created, 1);
    expect(result.total, 1);
    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog!.jiraWorklogId, '10001');
    expect(worklog.syncedTicketKey, 'PROJ-1');
    verify(
      () => client.createWorklog(
        issueKey: 'PROJ-1',
        timeSpent: const Duration(hours: 1),
        startedAt: entry.startAt,
        comment: 'Design review',
      ),
    ).called(1);
  });

  test('running (unfinished) entries are skipped', () async {
    await writes.startEntry(deviceId: 'dev_a', jiraTicketKey: 'PROJ-1');

    final result = await service.syncNow();

    expect(result.total, 0);
    verifyNever(
      () => client.createWorklog(
        issueKey: any(named: 'issueKey'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    );
  });

  test('updates the worklog when the entry changed since the last sync', () async {
    when(
      () => client.updateWorklog(
        issueKey: any(named: 'issueKey'),
        worklogId: any(named: 'worklogId'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async {});

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
    );
    await writes.upsertJiraWorklogState(
      (await db.jiraWorklogsDao.getForEntry(entry.id))?.copyWith(
            jiraWorklogId: const Value('10001'),
            syncedTicketKey: const Value('PROJ-1'),
            status: const Value('synced'),
            syncedAt: Value(DateTime.utc(2020)),
          ) ??
          (throw StateError('expected a tracking row')),
    );

    final result = await service.syncNow();

    expect(result.updated, 1);
    verify(
      () => client.updateWorklog(
        issueKey: 'PROJ-1',
        worklogId: '10001',
        timeSpent: any(named: 'timeSpent'),
        startedAt: entry.startAt,
        comment: any(named: 'comment'),
      ),
    ).called(1);
  });

  test('moves the worklog to the new ticket when jiraTicketKey changes', () async {
    when(
      () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10001'),
    ).thenAnswer((_) async {});
    when(
      () => client.createWorklog(
        issueKey: 'PROJ-2',
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async => '10002');

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-2',
    );
    await writes.upsertJiraWorklogState(
      (await db.jiraWorklogsDao.getForEntry(entry.id))!.copyWith(
        jiraWorklogId: const Value('10001'),
        syncedTicketKey: const Value('PROJ-1'),
        status: const Value('synced'),
        syncedAt: Value(DateTime.utc(2020)),
      ),
    );

    final result = await service.syncNow();

    expect(result.updated, 1);
    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog!.syncedTicketKey, 'PROJ-2');
    expect(worklog.jiraWorklogId, '10002');
  });

  test('deletes the remote worklog and the tracking row for a pendingDelete entry', () async {
    when(
      () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10001'),
    ).thenAnswer((_) async {});

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
    );
    await writes.upsertJiraWorklogState(
      (await db.jiraWorklogsDao.getForEntry(entry.id))!.copyWith(
        jiraWorklogId: const Value('10001'),
        syncedTicketKey: const Value('PROJ-1'),
        status: const Value('pendingDelete'),
      ),
    );

    final result = await service.syncNow();

    expect(result.deleted, 1);
    expect(await db.jiraWorklogsDao.getForEntry(entry.id), isNull);
  });

  test('a failed create is recorded with status error and counted as failed', () async {
    when(
      () => client.createWorklog(
        issueKey: any(named: 'issueKey'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenThrow(JiraApiException('boom'));

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
    );

    final result = await service.syncNow();

    expect(result.failed, 1);
    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog!.status, 'error');
    expect(worklog.lastError, contains('boom'));
  });
}
```

Note: `Value` is used above without an explicit import because `synced_writes.dart`/`database.dart` re-export it transitively through `package:drift/drift.dart`; if `dart analyze` flags it as undefined, add `import 'package:drift/drift.dart' show Value;` to the top of the test file.

- [ ] **Step 3: Run the tests**

Run: `flutter test test/features/jira/jira_sync_service_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/features/jira/jira_sync_service.dart test/features/jira/jira_sync_service_test.dart
git commit -m "feat(jira): add sync reconciliation service"
```

---

### Task 7: Riverpod providers

**Files:**
- Create: `lib/core/di/jira_providers.dart`

**Interfaces:**
- Consumes: `SecureJiraCredentialsStore` (Task 4), `HttpJiraClient` (Task 5), `JiraSyncService` (Task 6), `appDatabaseProvider` and `syncedWritesProvider` (existing, `lib/core/di/database_provider.dart` and `lib/core/di/sync_providers.dart`).
- Produces: `jiraCredentialsStoreProvider`, `jiraCredentialsProvider` (`FutureProvider<JiraCredentials?>`), `jiraClientProvider` (`FutureProvider<JiraClient?>`, null until configured), `jiraSyncServiceProvider` (`FutureProvider<JiraSyncService?>`), `jiraWorklogsByEntryIdProvider` (`StreamProvider<Map<String, JiraWorklogRow>>`). Consumed by Tasks 8, 9, 10, 11, 12.

- [ ] **Step 1: Write the providers**

Create `lib/core/di/jira_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../features/jira/http_jira_client.dart';
import '../../features/jira/jira_client.dart';
import '../../features/jira/jira_credentials_store.dart';
import '../../features/jira/jira_sync_service.dart';
import '../../features/jira/secure_jira_credentials_store.dart';
import 'database_provider.dart';

// Plain (non-generated) providers — see timer_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final jiraCredentialsStoreProvider = Provider<JiraCredentialsStore>(
  (ref) => SecureJiraCredentialsStore(),
);

/// The configured Jira credentials, or null if Jira hasn't been set up on
/// this device yet. Invalidate this provider after writing new credentials
/// to pick them up immediately.
final jiraCredentialsProvider = FutureProvider<JiraCredentials?>((ref) async {
  final store = ref.watch(jiraCredentialsStoreProvider);
  return store.read();
});

/// The Jira API client, or null until credentials are configured.
final jiraClientProvider = FutureProvider<JiraClient?>((ref) async {
  final credentials = await ref.watch(jiraCredentialsProvider.future);
  if (credentials == null) return null;
  return HttpJiraClient(credentials: credentials);
});

/// The sync reconciliation service, or null until credentials are
/// configured.
final jiraSyncServiceProvider = FutureProvider<JiraSyncService?>((ref) async {
  final client = await ref.watch(jiraClientProvider.future);
  if (client == null) return null;
  final db = ref.watch(appDatabaseProvider);
  final writes = await ref.watch(syncedWritesProvider.future);
  return JiraSyncService(db: db, client: client, writes: writes);
});

/// All Jira worklog tracking rows keyed by time-entry id, for the entries
/// list's per-entry status indicator.
final jiraWorklogsByEntryIdProvider = StreamProvider<Map<String, JiraWorklogRow>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .jiraWorklogsDao
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row});
});
```

- [ ] **Step 2: Verify it compiles**

Run: `dart analyze lib/core/di/jira_providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/di/jira_providers.dart
git commit -m "feat(jira): wire riverpod providers for client, credentials, sync"
```

---

### Task 8: `JiraTicketField` — autocomplete widget

**Files:**
- Create: `lib/features/jira/widgets/jira_ticket_field.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`

**Interfaces:**
- Consumes: `jiraClientProvider` (Task 7), `JiraIssueSuggestion` (Task 5).
- Produces: `JiraTicketField({required String? initialValue, required ValueChanged<String?> onChanged})`. Consumed by Tasks 9 and 10.

- [ ] **Step 1: Add the ARB key**

Add to `lib/l10n/app_de.arb` (German is the template — pick any existing key as an anchor, e.g. right after `"timerNewProjectTooltip": "Neues Projekt",`):

```json
  "jiraTicketFieldLabel": "Jira-Ticket",
```

Add the same key to the other five locale files with these translations:

`lib/l10n/app_en.arb`: `"jiraTicketFieldLabel": "Jira ticket",`
`lib/l10n/app_es.arb`: `"jiraTicketFieldLabel": "Ticket de Jira",`
`lib/l10n/app_fr.arb`: `"jiraTicketFieldLabel": "Ticket Jira",`
`lib/l10n/app_it.arb`: `"jiraTicketFieldLabel": "Ticket Jira",`
`lib/l10n/app_nl.arb`: `"jiraTicketFieldLabel": "Jira-ticket",`

- [ ] **Step 2: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes without errors; `lib/l10n/app_localizations*.dart` now expose `jiraTicketFieldLabel`.

- [ ] **Step 3: Implement the widget**

Create `lib/features/jira/widgets/jira_ticket_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/jira_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../jira_client.dart';

/// A Jira ticket-key input: does a debounced Jira issue search as the user
/// types when Jira is configured, and always still accepts a manually
/// typed key — search failing, or Jira not being configured yet, must
/// never block entering or editing a time entry.
class JiraTicketField extends ConsumerStatefulWidget {
  const JiraTicketField({super.key, required this.initialValue, required this.onChanged});

  final String? initialValue;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<JiraTicketField> createState() => _JiraTicketFieldState();
}

class _JiraTicketFieldState extends ConsumerState<JiraTicketField> {
  /// RawAutocomplete's `optionsBuilder` is typed `FutureOr<Iterable<T>>`
  /// specifically so an async options source is supported natively:
  /// RawAutocomplete tracks the in-flight call itself and discards a result
  /// that resolves after a newer call has already started, so returning a
  /// Future here — rather than kicking off a search as a side effect and
  /// pushing results back in via a separate `setState`, which does NOT
  /// cause RawAutocomplete to re-run `optionsBuilder` or redraw the options
  /// list — is what actually gets fetched results displayed. The debounce
  /// is a plain delay at the start of the call; a query that goes stale
  /// during the delay is simply superseded by RawAutocomplete's own
  /// tracking once the newer call resolves, without extra bookkeeping here.
  Future<Iterable<JiraIssueSuggestion>> _search(TextEditingValue textValue) async {
    final query = textValue.text;
    if (query.trim().isEmpty) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      final client = await ref.read(jiraClientProvider.future);
      if (client == null) return const [];
      return await client.searchIssues(query);
    } catch (_) {
      // Search failing (network error, provider/credentials error) must
      // never block manual entry of a ticket key.
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RawAutocomplete<JiraIssueSuggestion>(
      initialValue: TextEditingValue(text: widget.initialValue ?? ''),
      displayStringForOption: (option) => option.key,
      optionsBuilder: _search,
      onSelected: (option) => widget.onChanged(option.key),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: l10n.jiraTicketFieldLabel),
          onChanged: (value) => widget.onChanged(value.trim().isEmpty ? null : value.trim()),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final option = list[index];
                  return ListTile(
                    title: Text(option.key),
                    subtitle: Text(option.summary),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `dart analyze lib/features/jira/widgets/jira_ticket_field.dart`
Expected: `No issues found!`

- [ ] **Step 5: Verify ARB completeness**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/jira/widgets/jira_ticket_field.dart
git commit -m "feat(jira): add ticket autocomplete field"
```

---

### Task 9: Wire the ticket field into the manual entry dialog

**Files:**
- Modify: `lib/features/entries/manual_entry_dialog.dart`

**Interfaces:**
- Consumes: `JiraTicketField` (Task 8), `SyncedWrites.createManualEntry`/`updateEntry` with `jiraTicketKey` (Task 3).

- [ ] **Step 1: Add the ticket field and wire it into save**

Edit `lib/features/entries/manual_entry_dialog.dart`. Add the import:

```dart
import '../jira/widgets/jira_ticket_field.dart';
```

Add a field to `_ManualEntryDialogState`, next to `_projectId`:

```dart
  String? _projectId;
  String? _jiraTicketKey;
```

Initialize it in `initState`, next to the `_projectId` line:

```dart
    _projectId = existing?.projectId;
    _jiraTicketKey = existing?.jiraTicketKey;
```

Pass it through in `_save`, for both the create and update branches:

```dart
    if (existing == null) {
      final deviceId = await ref.read(deviceIdProvider.future);
      await writes.createManualEntry(
        deviceId: deviceId,
        startAt: _startAt,
        endAt: _endAt,
        projectId: _projectId,
        description: description,
        jiraTicketKey: _jiraTicketKey,
      );
    } else {
      await writes.updateEntry(
        existing.id,
        startAt: Value(_startAt.toUtc()),
        endAt: Value(_endAt.toUtc()),
        projectId: Value(_projectId),
        description: Value(description),
        jiraTicketKey: Value(_jiraTicketKey),
      );
    }
```

Add the field to the dialog's `Column`, right after the project `DropdownButtonFormField` block (after its closing `),` and before the start-time `ListTile`):

```dart
            const SizedBox(height: 12),
            JiraTicketField(
              initialValue: _jiraTicketKey,
              onChanged: (value) => setState(() => _jiraTicketKey = value),
            ),
```

- [ ] **Step 2: Verify it compiles**

Run: `dart analyze lib/features/entries/manual_entry_dialog.dart`
Expected: `No issues found!`

- [ ] **Step 3: Manual smoke test**

Run: `flutter run -d windows`
Steps: open the app, tap the manual-entry FAB, confirm a "Jira-Ticket" field appears below the project dropdown, type a key, save, reopen the entry and confirm the value persisted.
Expected: field is present, editable, and round-trips.

- [ ] **Step 4: Commit**

```bash
git add lib/features/entries/manual_entry_dialog.dart
git commit -m "feat(entries): add jira ticket field to the manual entry dialog"
```

---

### Task 10: Wire the ticket field into the timer start card

**Files:**
- Modify: `lib/features/timer/timer_screen.dart`

**Interfaces:**
- Consumes: `JiraTicketField` (Task 8), `SyncedWrites.startEntry` with `jiraTicketKey` (Task 3).

- [ ] **Step 1: Add the ticket field and wire it into start**

Edit `lib/features/timer/timer_screen.dart`. Add the import:

```dart
import '../jira/widgets/jira_ticket_field.dart';
```

Add a field to `_TimerScreenState`, next to `_selectedProjectId`:

```dart
  String? _selectedProjectId;
  String? _selectedJiraTicketKey;
```

Update `_start`:

```dart
  Future<void> _start() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.startEntry(
      deviceId: deviceId,
      projectId: _selectedProjectId,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      jiraTicketKey: _selectedJiraTicketKey,
    );
    _descriptionController.clear();
    setState(() => _selectedJiraTicketKey = null);
  }
```

Update the `_StartCard` instantiation inside `build`:

```dart
                : _StartCard(
                    descriptionController: _descriptionController,
                    selectedProjectId: _selectedProjectId,
                    onProjectChanged: (id) => setState(() => _selectedProjectId = id),
                    selectedJiraTicketKey: _selectedJiraTicketKey,
                    onJiraTicketKeyChanged: (key) => setState(() => _selectedJiraTicketKey = key),
                    onStart: _start,
                  ),
```

Update `_StartCard` to accept and render the field:

```dart
class _StartCard extends ConsumerWidget {
  const _StartCard({
    required this.descriptionController,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.selectedJiraTicketKey,
    required this.onJiraTicketKeyChanged,
    required this.onStart,
  });

  final TextEditingController descriptionController;
  final String? selectedProjectId;
  final ValueChanged<String?> onProjectChanged;
  final String? selectedJiraTicketKey;
  final ValueChanged<String?> onJiraTicketKeyChanged;
  final VoidCallback onStart;
```

Add the field to the card's `Column`, right after the project `Row` block (after its closing `),` and before the `GradientPillButton`):

```dart
            const SizedBox(height: 12),
            JiraTicketField(
              initialValue: selectedJiraTicketKey,
              onChanged: onJiraTicketKeyChanged,
            ),
            const SizedBox(height: 12),
            GradientPillButton(
```

(remove the now-duplicate `const SizedBox(height: 12),` that previously preceded `GradientPillButton` so there's exactly one).

- [ ] **Step 2: Verify it compiles**

Run: `dart analyze lib/features/timer/timer_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Manual smoke test**

Run: `flutter run -d windows`
Steps: on the Timer tab, confirm the "Jira-Ticket" field appears under the project dropdown on the start card, type a key, start the timer, stop it, then open the entry from the list and confirm the ticket key is set.
Expected: field present and value carries into the created entry.

- [ ] **Step 4: Commit**

```bash
git add lib/features/timer/timer_screen.dart
git commit -m "feat(timer): add jira ticket field to the start card"
```

---

### Task 11: Jira status indicator in the entries list

**Files:**
- Modify: `lib/features/entries/entries_list.dart`
- Modify: all six `lib/l10n/app_*.arb` files

**Interfaces:**
- Consumes: `jiraWorklogsByEntryIdProvider` (Task 7), `JiraWorklogStatus` (Task 1).

- [ ] **Step 1: Add the ARB keys**

Add to `lib/l10n/app_de.arb`:

```json
  "entriesJiraStatusSynced": "In Jira gebucht",
  "entriesJiraStatusPending": "Jira-Buchung ausstehend",
  "entriesJiraStatusError": "Jira-Buchung fehlgeschlagen",
```

Add the same keys to the other locales:

`lib/l10n/app_en.arb`:
```json
  "entriesJiraStatusSynced": "Booked in Jira",
  "entriesJiraStatusPending": "Jira booking pending",
  "entriesJiraStatusError": "Jira booking failed",
```

`lib/l10n/app_es.arb`:
```json
  "entriesJiraStatusSynced": "Registrado en Jira",
  "entriesJiraStatusPending": "Registro en Jira pendiente",
  "entriesJiraStatusError": "Error al registrar en Jira",
```

`lib/l10n/app_fr.arb`:
```json
  "entriesJiraStatusSynced": "Enregistré dans Jira",
  "entriesJiraStatusPending": "Enregistrement Jira en attente",
  "entriesJiraStatusError": "Échec de l'enregistrement Jira",
```

`lib/l10n/app_it.arb`:
```json
  "entriesJiraStatusSynced": "Registrato su Jira",
  "entriesJiraStatusPending": "Registrazione Jira in sospeso",
  "entriesJiraStatusError": "Registrazione Jira non riuscita",
```

`lib/l10n/app_nl.arb`:
```json
  "entriesJiraStatusSynced": "Geboekt in Jira",
  "entriesJiraStatusPending": "Jira-boeking in behandeling",
  "entriesJiraStatusError": "Jira-boeking mislukt",
```

- [ ] **Step 2: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes without errors.

- [ ] **Step 3: Add the indicator**

Edit `lib/features/entries/entries_list.dart`. Add imports:

```dart
import '../../core/di/jira_providers.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
```

Watch the new provider in `build`, next to the existing `projectsAsync` watch:

```dart
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
```

Inside `itemBuilder`, after `final project = ...` line, resolve the worklog and build a small trailing icon:

```dart
            final project = entry.projectId == null ? null : projectsById[entry.projectId];
            final jiraWorklog = jiraWorklogsAsync.value?[entry.id];
            final jiraStatusIcon = _jiraStatusIcon(l10n, entry.jiraTicketKey, jiraWorklog);
```

Change the `ListTile`'s `trailing` to show both the duration and the status icon when present:

```dart
                  trailing: jiraStatusIcon == null
                      ? Text(formatDuration(duration))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            jiraStatusIcon,
                            const SizedBox(width: 6),
                            Text(formatDuration(duration)),
                          ],
                        ),
```

Add the helper as a top-level function at the bottom of the file, after the `EntriesList` class:

```dart
Widget? _jiraStatusIcon(AppLocalizations l10n, String? jiraTicketKey, JiraWorklogRow? worklog) {
  if (jiraTicketKey == null) return null;
  final status = worklog?.status;
  return switch (status) {
    JiraWorklogStatus.synced => Tooltip(
        message: l10n.entriesJiraStatusSynced,
        child: const Icon(Icons.cloud_done_outlined, size: 18, color: Colors.green),
      ),
    JiraWorklogStatus.error => Tooltip(
        message: l10n.entriesJiraStatusError,
        child: const Icon(Icons.cloud_off_outlined, size: 18, color: Colors.red),
      ),
    _ => Tooltip(
        message: l10n.entriesJiraStatusPending,
        child: Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.grey.shade600),
      ),
  };
}
```

- [ ] **Step 4: Verify it compiles**

Run: `dart analyze lib/features/entries/entries_list.dart`
Expected: `No issues found!`

- [ ] **Step 5: Verify ARB completeness**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 6: Manual smoke test**

Run: `flutter run -d windows`
Steps: create an entry with a Jira ticket key set (via Task 9's dialog), confirm a grey "pending" cloud icon appears next to its duration in the list; entries without a ticket key show no icon.
Expected: icon present only for entries with a ticket key, tooltip shows the right status text.

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/entries/entries_list.dart
git commit -m "feat(entries): show jira sync status next to booked entries"
```

---

### Task 12: "Jira Integration" card in the Sync screen

**Files:**
- Modify: `lib/features/sync/sync_screen.dart`
- Modify: all six `lib/l10n/app_*.arb` files

**Interfaces:**
- Consumes: `jiraCredentialsStoreProvider`, `jiraCredentialsProvider`, `jiraClientProvider`, `jiraSyncServiceProvider` (Task 7), `JiraSyncResult` (Task 6).

- [ ] **Step 1: Add the ARB keys**

Add to `lib/l10n/app_de.arb`:

```json
  "syncJiraSectionTitle": "Jira-Integration",
  "syncJiraBaseUrlLabel": "Jira-URL",
  "syncJiraEmailLabel": "E-Mail",
  "syncJiraApiTokenLabel": "API-Token",
  "syncJiraSaveCredentialsButton": "Zugangsdaten speichern",
  "syncJiraCredentialsSaved": "Zugangsdaten gespeichert.",
  "syncJiraTestConnectionButton": "Verbindung testen",
  "syncJiraTestConnectionSuccess": "Verbindung erfolgreich.",
  "syncJiraTestConnectionFailure": "Verbindung fehlgeschlagen. Bitte Zugangsdaten prüfen.",
  "syncJiraSyncButton": "Jetzt zu Jira synchronisieren",
  "syncJiraNotConfigured": "Jira ist noch nicht konfiguriert.",
  "syncJiraInvalidCredentials": "Bitte gib eine gültige Jira-URL sowie E-Mail und API-Token an.",
  "syncJiraUnexpectedError": "Es ist ein Fehler aufgetreten. Bitte versuche es erneut.",
  "syncJiraSyncResult": "{created} erstellt, {updated} aktualisiert, {deleted} gelöscht, {failed} fehlgeschlagen.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

Add the same keys to the other locales (placeholder metadata block is identical for every locale, omitted below for brevity but must be copied into each file too):

`lib/l10n/app_en.arb`:
```json
  "syncJiraSectionTitle": "Jira Integration",
  "syncJiraBaseUrlLabel": "Jira URL",
  "syncJiraEmailLabel": "Email",
  "syncJiraApiTokenLabel": "API token",
  "syncJiraSaveCredentialsButton": "Save credentials",
  "syncJiraCredentialsSaved": "Credentials saved.",
  "syncJiraTestConnectionButton": "Test connection",
  "syncJiraTestConnectionSuccess": "Connection successful.",
  "syncJiraTestConnectionFailure": "Connection failed. Please check your credentials.",
  "syncJiraSyncButton": "Sync to Jira now",
  "syncJiraNotConfigured": "Jira isn't configured yet.",
  "syncJiraInvalidCredentials": "Please enter a valid Jira URL, email, and API token.",
  "syncJiraUnexpectedError": "Something went wrong. Please try again.",
  "syncJiraSyncResult": "{created} created, {updated} updated, {deleted} deleted, {failed} failed.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

`lib/l10n/app_es.arb`:
```json
  "syncJiraSectionTitle": "Integración con Jira",
  "syncJiraBaseUrlLabel": "URL de Jira",
  "syncJiraEmailLabel": "Correo electrónico",
  "syncJiraApiTokenLabel": "Token de API",
  "syncJiraSaveCredentialsButton": "Guardar credenciales",
  "syncJiraCredentialsSaved": "Credenciales guardadas.",
  "syncJiraTestConnectionButton": "Probar conexión",
  "syncJiraTestConnectionSuccess": "Conexión correcta.",
  "syncJiraTestConnectionFailure": "Error de conexión. Comprueba tus credenciales.",
  "syncJiraSyncButton": "Sincronizar con Jira ahora",
  "syncJiraNotConfigured": "Jira aún no está configurado.",
  "syncJiraInvalidCredentials": "Introduce una URL de Jira, correo electrónico y token de API válidos.",
  "syncJiraUnexpectedError": "Se produjo un error. Inténtalo de nuevo.",
  "syncJiraSyncResult": "{created} creadas, {updated} actualizadas, {deleted} eliminadas, {failed} fallidas.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

`lib/l10n/app_fr.arb`:
```json
  "syncJiraSectionTitle": "Intégration Jira",
  "syncJiraBaseUrlLabel": "URL Jira",
  "syncJiraEmailLabel": "E-mail",
  "syncJiraApiTokenLabel": "Jeton API",
  "syncJiraSaveCredentialsButton": "Enregistrer les identifiants",
  "syncJiraCredentialsSaved": "Identifiants enregistrés.",
  "syncJiraTestConnectionButton": "Tester la connexion",
  "syncJiraTestConnectionSuccess": "Connexion réussie.",
  "syncJiraTestConnectionFailure": "Échec de la connexion. Vérifiez vos identifiants.",
  "syncJiraSyncButton": "Synchroniser avec Jira maintenant",
  "syncJiraNotConfigured": "Jira n'est pas encore configuré.",
  "syncJiraInvalidCredentials": "Veuillez saisir une URL Jira, un e-mail et un jeton API valides.",
  "syncJiraUnexpectedError": "Une erreur s'est produite. Veuillez réessayer.",
  "syncJiraSyncResult": "{created} créées, {updated} mises à jour, {deleted} supprimées, {failed} échouées.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

`lib/l10n/app_it.arb`:
```json
  "syncJiraSectionTitle": "Integrazione Jira",
  "syncJiraBaseUrlLabel": "URL Jira",
  "syncJiraEmailLabel": "Email",
  "syncJiraApiTokenLabel": "Token API",
  "syncJiraSaveCredentialsButton": "Salva credenziali",
  "syncJiraCredentialsSaved": "Credenziali salvate.",
  "syncJiraTestConnectionButton": "Verifica connessione",
  "syncJiraTestConnectionSuccess": "Connessione riuscita.",
  "syncJiraTestConnectionFailure": "Connessione non riuscita. Controlla le credenziali.",
  "syncJiraSyncButton": "Sincronizza ora con Jira",
  "syncJiraNotConfigured": "Jira non è ancora configurato.",
  "syncJiraInvalidCredentials": "Inserisci un URL Jira, un'email e un token API validi.",
  "syncJiraUnexpectedError": "Si è verificato un errore. Riprova.",
  "syncJiraSyncResult": "{created} create, {updated} aggiornate, {deleted} eliminate, {failed} non riuscite.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

`lib/l10n/app_nl.arb`:
```json
  "syncJiraSectionTitle": "Jira-integratie",
  "syncJiraBaseUrlLabel": "Jira-URL",
  "syncJiraEmailLabel": "E-mail",
  "syncJiraApiTokenLabel": "API-token",
  "syncJiraSaveCredentialsButton": "Gegevens opslaan",
  "syncJiraCredentialsSaved": "Gegevens opgeslagen.",
  "syncJiraTestConnectionButton": "Verbinding testen",
  "syncJiraTestConnectionSuccess": "Verbinding geslaagd.",
  "syncJiraTestConnectionFailure": "Verbinding mislukt. Controleer je gegevens.",
  "syncJiraSyncButton": "Nu synchroniseren met Jira",
  "syncJiraNotConfigured": "Jira is nog niet geconfigureerd.",
  "syncJiraInvalidCredentials": "Voer een geldige Jira-URL, e-mail en API-token in.",
  "syncJiraUnexpectedError": "Er is een fout opgetreden. Probeer het opnieuw.",
  "syncJiraSyncResult": "{created} aangemaakt, {updated} bijgewerkt, {deleted} verwijderd, {failed} mislukt.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

- [ ] **Step 2: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes without errors.

- [ ] **Step 3: Add the Jira card**

Edit `lib/features/sync/sync_screen.dart`. Add imports:

```dart
import '../../core/di/jira_providers.dart';
import '../jira/jira_credentials_store.dart';
```

Add state to `_SyncScreenState`:

```dart
  bool _busy = false;
  String? _statusMessage;
  final _jiraBaseUrlController = TextEditingController();
  final _jiraEmailController = TextEditingController();
  final _jiraApiTokenController = TextEditingController();
  bool _jiraBusy = false;
  String? _jiraStatusMessage;
```

Load any existing credentials into the controllers once, in `initState`:

```dart
  @override
  void initState() {
    super.initState();
    _loadJiraCredentials();
  }

  Future<void> _loadJiraCredentials() async {
    final credentials = await ref.read(jiraCredentialsProvider.future);
    if (!mounted || credentials == null) return;
    _jiraBaseUrlController.text = credentials.baseUrl;
    _jiraEmailController.text = credentials.email;
    _jiraApiTokenController.text = credentials.apiToken;
  }
```

Dispose the new controllers — add a `dispose()` override (this widget doesn't have one yet):

```dart
  @override
  void dispose() {
    _jiraBaseUrlController.dispose();
    _jiraEmailController.dispose();
    _jiraApiTokenController.dispose();
    super.dispose();
  }
```

Add the Jira action methods, next to `_syncNow`:

```dart
  /// Light client-side validation before writing credentials: catches empty
  /// fields and an obviously-malformed base URL early, so the far more
  /// common failure mode (a typo right after first setup) surfaces as an
  /// immediate, specific message instead of a confusing "not configured" or
  /// unhandled error the first time the URL is actually used.
  bool _hasValidJiraCredentialsInput() {
    final email = _jiraEmailController.text.trim();
    final apiToken = _jiraApiTokenController.text.trim();
    if (email.isEmpty || apiToken.isEmpty) return false;
    final uri = Uri.tryParse(_jiraBaseUrlController.text.trim());
    return uri != null && uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _saveJiraCredentials() async {
    final l10n = AppLocalizations.of(context);
    if (!_hasValidJiraCredentialsInput()) {
      setState(() => _jiraStatusMessage = l10n.syncJiraInvalidCredentials);
      return;
    }
    setState(() {
      _jiraBusy = true;
      _jiraStatusMessage = null;
    });
    try {
      final store = ref.read(jiraCredentialsStoreProvider);
      await store.write(
        JiraCredentials(
          baseUrl: _jiraBaseUrlController.text.trim(),
          email: _jiraEmailController.text.trim(),
          apiToken: _jiraApiTokenController.text.trim(),
        ),
      );
      ref.invalidate(jiraCredentialsProvider);
      if (mounted) setState(() => _jiraStatusMessage = l10n.syncJiraCredentialsSaved);
    } catch (_) {
      if (mounted) setState(() => _jiraStatusMessage = l10n.syncJiraUnexpectedError);
    } finally {
      if (mounted) setState(() => _jiraBusy = false);
    }
  }

  Future<void> _testJiraConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _jiraBusy = true;
      _jiraStatusMessage = null;
    });
    try {
      final client = await ref.read(jiraClientProvider.future);
      if (client == null) {
        if (mounted) setState(() => _jiraStatusMessage = l10n.syncJiraNotConfigured);
        return;
      }
      final ok = await client.testConnection();
      if (!mounted) return;
      setState(
        () => _jiraStatusMessage = ok
            ? l10n.syncJiraTestConnectionSuccess
            : l10n.syncJiraTestConnectionFailure,
      );
    } catch (_) {
      // testConnection() throws for transport-level errors (e.g. a
      // malformed URL, DNS failure) — the single most likely error right
      // after first configuring credentials, so this must not be left to
      // propagate unhandled.
      if (mounted) setState(() => _jiraStatusMessage = l10n.syncJiraTestConnectionFailure);
    } finally {
      if (mounted) setState(() => _jiraBusy = false);
    }
  }

  Future<void> _syncJiraNow() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _jiraBusy = true;
      _jiraStatusMessage = null;
    });
    try {
      final service = await ref.read(jiraSyncServiceProvider.future);
      if (service == null) {
        if (mounted) setState(() => _jiraStatusMessage = l10n.syncJiraNotConfigured);
        return;
      }
      final result = await service.syncNow();
      if (!mounted) return;
      setState(
        () => _jiraStatusMessage = l10n.syncJiraSyncResult(
          result.created,
          result.updated,
          result.deleted,
          result.failed,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _jiraStatusMessage = l10n.syncJiraUnexpectedError);
    } finally {
      if (mounted) setState(() => _jiraBusy = false);
    }
  }
```

Add the card to `build`, right after the existing sync `Card` block (after its closing `),` and before the closing `],` of the outer `Column`):

```dart
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.syncJiraSectionTitle, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _jiraBaseUrlController,
                    decoration: InputDecoration(labelText: l10n.syncJiraBaseUrlLabel),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _jiraEmailController,
                    decoration: InputDecoration(labelText: l10n.syncJiraEmailLabel),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _jiraApiTokenController,
                    decoration: InputDecoration(labelText: l10n.syncJiraApiTokenLabel),
                    obscureText: true,
                  ),
                  if (_jiraStatusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_jiraStatusMessage!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: _jiraBusy ? null : _saveJiraCredentials,
                        child: Text(l10n.syncJiraSaveCredentialsButton),
                      ),
                      OutlinedButton(
                        onPressed: _jiraBusy ? null : _testJiraConnection,
                        child: Text(l10n.syncJiraTestConnectionButton),
                      ),
                      OutlinedButton(
                        onPressed: _jiraBusy ? null : _syncJiraNow,
                        child: Text(l10n.syncJiraSyncButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
```

- [ ] **Step 4: Verify it compiles**

Run: `dart analyze lib/features/sync/sync_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Verify ARB completeness**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 6: Manual smoke test**

Run: `flutter run -d windows`
Steps: open the Sync tab, confirm the "Jira-Integration" card appears below the existing sync card; enter a base URL/email/API token and save, reopen the screen and confirm the fields are pre-filled; click "Verbindung testen" against a real or intentionally-wrong token and confirm success/failure messages differ; book a couple of entries with ticket keys (Tasks 9/10) and click "Jetzt zu Jira synchronisieren", confirming the result summary and the entries-list status icons (Task 11) update.
Expected: full round trip works end-to-end against a real Jira Cloud instance.

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart lib/features/sync/sync_screen.dart
git commit -m "feat(sync): add jira credentials and manual sync-to-jira UI"
```

---

### Task 13: Final verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: all tests pass, including every test added in Tasks 1–8.

- [ ] **Step 2: Run static analysis over the whole project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Confirm the build still produces a runnable app**

Run: `flutter build windows --debug`
Expected: build succeeds.

- [ ] **Step 4: Commit (only if any of the above required fixes)**

```bash
git add -A
git commit -m "chore(jira): fix issues found during full verification pass"
```

If nothing needed fixing, skip this step — there's nothing to commit.

---

## Self-Review Notes

- **Spec coverage:** §2 data model → Task 1; §2 cross-device sync + credentials-not-synced → Tasks 2, 4; §3 API client → Task 5; §4 sync algorithm → Task 6; §5 UI (ticket field, entries list, sync screen) → Tasks 8–12; §6 error handling → built into Task 6's `status`/`lastError` fields and surfaced in Task 11; §7 localization → every UI task carries its own ARB updates; §8 out-of-scope items are simply not built anywhere in this plan.
- **Placeholder scan:** no TBD/TODO markers; every step has complete, runnable code; the one place testing is deliberately skipped (Task 4) has an explicit, precedented reason rather than a vague omission.
- **Type consistency:** `JiraWorklogRow`, `JiraWorklogStatus`, `JiraCredentials`, `JiraClient`, `JiraIssueSuggestion`, `JiraSyncResult`, and every provider name are used identically across all tasks that reference them.
