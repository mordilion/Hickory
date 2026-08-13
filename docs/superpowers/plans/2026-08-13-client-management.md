# Client Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up the already-existing but unused `Clients` table into a full CRUD feature — DAO, sync (write + ingest), and a Settings-based editor — plus an optional client picker on the project form dialog.

**Architecture:** Mirrors the existing `Projects` CRUD stack exactly at every layer (DAO → `SyncedWrites` → `SyncIngestor` → Riverpod provider → editor widget → Settings sub-page), per `docs/superpowers/specs/2026-08-13-client-management-design.md`.

**Tech Stack:** Flutter, Drift (SQLite), Riverpod (plain `StreamProvider`, not code-gen — see Global Constraints), `sync_engine` (event log), `flutter_test` + `mocktail`.

## Global Constraints

- No schema/migration changes: `Clients` and `Projects.clientId` already exist in `lib/data/drift/tables/clients_table.dart` / `projects_table.dart` and are already registered in `AppDatabase`'s `tables:` list (`lib/data/drift/database.dart`) — every installed copy already has an empty `clients` table from its very first `onCreate`. Do not touch `schemaVersion` or add an `onUpgrade` step for this.
- New Riverpod providers in `lib/features/clients/clients_providers.dart` MUST be plain `StreamProvider`, not `@riverpod` code-gen — `lib/features/projects/projects_providers.dart` already documents why: a generated provider returning a drift row type can trip `riverpod_generator`'s `InvalidTypeException` (rrousselGit/riverpod#4323). Copy that file's structure exactly.
- `lib/l10n/app_de.arb` is the l10n **template** (`l10n.yaml`: `template-arb-file: app_de.arb`) — `test/l10n/arb_completeness_test.dart` diffs every other locale file against `de`, not `en`. Every new key must exist, with a real translation (not a placeholder), in all six files: `app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`.
- Every DB mutation goes through `SyncedWrites`, never the DAO directly from UI/provider code — the DAO alone doesn't append to the sync event log.
- Commit messages: Conventional Commits, imperative mood, lowercase, no trailing period, under 72 chars for the summary line.
- Run `dart run build_runner build --delete-conflicting-outputs` after any change to a `@DriftAccessor`/`@DriftDatabase`-annotated class, before running tests that touch it.

---

### Task 1: `ClientsDao`

**Files:**
- Create: `lib/data/drift/daos/clients_dao.dart`
- Modify: `lib/data/drift/database.dart` (register the DAO)
- Test: `test/data/drift/clients_dao_test.dart`

**Interfaces:**
- Produces: `ClientsDao` with `watchActiveClients() -> Stream<List<Client>>`, `watchArchivedClients() -> Stream<List<Client>>`, `createClient({required String name}) -> Future<Client>`, `updateClient(String id, {Value<String> name}) -> Future<void>`, `archiveClient(String id) -> Future<void>`, `unarchiveClient(String id) -> Future<void>`, `deleteClient(String id) -> Future<void>`. Exposed on `AppDatabase` as `db.clientsDao` once registered.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/drift/clients_dao_test.dart
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

  test('createClient inserts a row with archived defaulting to false', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');

    expect(client.name, 'Acme Inc');
    expect(client.archived, isFalse);
  });

  test('updateClient updates only the fields passed', () async {
    final client = await db.clientsDao.createClient(name: 'Old Name');

    await db.clientsDao.updateClient(client.id, name: const Value('New Name'));

    final updated = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(updated.name, 'New Name');
  });

  test('archiveClient sets archived to true', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');

    await db.clientsDao.archiveClient(client.id);

    final updated = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(updated.archived, isTrue);
  });

  test('unarchiveClient sets archived back to false', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    await db.clientsDao.archiveClient(client.id);

    await db.clientsDao.unarchiveClient(client.id);

    final updated = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(updated.archived, isFalse);
  });

  test('watchActiveClients only returns non-archived clients, ordered by name', () async {
    final active = await db.clientsDao.createClient(name: 'Active Client');
    final archivedB = await db.clientsDao.createClient(name: 'Zeta');
    final archivedA = await db.clientsDao.createClient(name: 'Alpha');
    await db.clientsDao.archiveClient(archivedB.id);
    await db.clientsDao.archiveClient(archivedA.id);

    final result = await db.clientsDao.watchActiveClients().first;

    expect(result.map((c) => c.name), ['Active Client']);
    expect(result.any((c) => c.id == active.id), isTrue);
  });

  test('watchArchivedClients only returns archived clients, ordered by name', () async {
    final archivedB = await db.clientsDao.createClient(name: 'Zeta');
    final archivedA = await db.clientsDao.createClient(name: 'Alpha');
    await db.clientsDao.archiveClient(archivedB.id);
    await db.clientsDao.archiveClient(archivedA.id);

    final result = await db.clientsDao.watchArchivedClients().first;

    expect(result.map((c) => c.name), ['Alpha', 'Zeta']);
  });

  test('deleteClient removes the row', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');

    await db.clientsDao.deleteClient(client.id);

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/drift/clients_dao_test.dart`
Expected: FAIL — compile error, `db.clientsDao` doesn't exist yet.

- [ ] **Step 3: Write `ClientsDao`**

```dart
// lib/data/drift/daos/clients_dao.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/clients_table.dart';

part 'clients_dao.g.dart';

@DriftAccessor(tables: [Clients])
class ClientsDao extends DatabaseAccessor<AppDatabase> with _$ClientsDaoMixin {
  ClientsDao(super.db);

  static const _uuid = Uuid();

  Stream<List<Client>> watchActiveClients() {
    return (select(clients)
          ..where((c) => c.archived.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Stream<List<Client>> watchArchivedClients() {
    return (select(clients)
          ..where((c) => c.archived.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<Client> createClient({required String name}) async {
    final now = DateTime.now().toUtc();
    final entry = ClientsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await into(clients).insert(entry);
    return (select(clients)..where((c) => c.id.equals(entry.id.value))).getSingle();
  }

  /// Partial update -- every parameter left as [Value.absent] keeps that
  /// column's current value, same shape as [ProjectsDao.updateProject].
  Future<void> updateClient(String id, {Value<String> name = const Value.absent()}) {
    return (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(name: name, updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> archiveClient(String id) {
    return (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> unarchiveClient(String id) {
    return (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(archived: const Value(false), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> deleteClient(String id) => (delete(clients)..where((c) => c.id.equals(id))).go();
}
```

- [ ] **Step 4: Register `ClientsDao` on `AppDatabase`**

In `lib/data/drift/database.dart`, add the import and register the DAO:

```dart
import 'daos/clients_dao.dart';
```

(add alphabetically among the other `daos/*.dart` imports, i.e. before `import 'daos/events_dao.dart';`)

```dart
  daos: [
    ClientsDao,
    ProjectsDao,
    TimeEntriesDao,
    EventsDao,
    ActivitySamplesDao,
    AppSettingsDao,
    JiraWorklogsDao,
    BreakRuleTiersDao,
    PersonioAttendancesDao,
  ],
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes without error; `lib/data/drift/daos/clients_dao.g.dart` and an updated `lib/data/drift/database.g.dart` are generated/modified.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/data/drift/clients_dao_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 7: Commit**

```bash
git add lib/data/drift/daos/clients_dao.dart lib/data/drift/daos/clients_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart test/data/drift/clients_dao_test.dart
git commit -m "feat(clients): add ClientsDao"
```

---

### Task 2: `ProjectsDao.hasProjectsForClient` and `clientId` in `updateProject`

**Files:**
- Modify: `lib/data/drift/daos/projects_dao.dart`
- Test: `test/data/drift/projects_dao_test.dart`

**Interfaces:**
- Consumes: `Client` from Task 1 (only for test setup, via `db.clientsDao.createClient`).
- Produces: `ProjectsDao.hasProjectsForClient(String clientId) -> Future<bool>`; `ProjectsDao.updateProject` gains `Value<String?> clientId = const Value.absent()`.

- [ ] **Step 1: Write the failing tests**

Append to `test/data/drift/projects_dao_test.dart` (inside the existing `main()`, after the last test):

```dart
  test('updateProject can set and clear clientId', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await db.projectsDao.updateProject(project.id, clientId: Value(client.id));
    var updated = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.clientId, client.id);

    await db.projectsDao.updateProject(project.id, clientId: const Value(null));
    updated = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.clientId, isNull);
  });

  test('hasProjectsForClient is true only when a project references the client', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    expect(await db.projectsDao.hasProjectsForClient(client.id), isFalse);

    await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF', clientId: client.id);

    expect(await db.projectsDao.hasProjectsForClient(client.id), isTrue);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/drift/projects_dao_test.dart`
Expected: FAIL — `updateProject` has no `clientId` parameter, `hasProjectsForClient` doesn't exist.

- [ ] **Step 3: Implement**

In `lib/data/drift/daos/projects_dao.dart`, change `updateProject`'s signature and body:

```dart
  /// Partial update: every parameter left as [Value.absent] keeps that
  /// column's current value -- same shape as [TimeEntriesDao.updateEntry].
  Future<void> updateProject(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String> colorHex = const Value.absent(),
    Value<String?> clientId = const Value.absent(),
    Value<bool> billable = const Value.absent(),
    Value<int?> hourlyRateCents = const Value.absent(),
    Value<String?> currency = const Value.absent(),
  }) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: name,
        colorHex: colorHex,
        clientId: clientId,
        billable: billable,
        hourlyRateCents: hourlyRateCents,
        currency: currency,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
```

Add a new method (place after `deleteProject`):

```dart
  Future<bool> hasProjectsForClient(String clientId) async {
    final row = await (select(projects)..where((p) => p.clientId.equals(clientId))..limit(1)).getSingleOrNull();
    return row != null;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/drift/projects_dao_test.dart`
Expected: PASS (all tests, including the 2 new ones)

- [ ] **Step 5: Commit**

```bash
git add lib/data/drift/daos/projects_dao.dart test/data/drift/projects_dao_test.dart
git commit -m "feat(projects): support clientId in updateProject"
```

---

### Task 3: `SyncedWrites` client methods

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Test: Create `test/data/synced_writes_client_test.dart`; modify `test/data/synced_writes_projects_test.dart`

**Interfaces:**
- Consumes: `ClientsDao` (Task 1), `ProjectsDao.hasProjectsForClient`/`updateProject` (Task 2), `EntityTypes.client` (already exists in `lib/data/sync/entity_types.dart`).
- Produces: `SyncedWrites.createClient({required String name}) -> Future<Client>`, `.updateClient(String id, {Value<String> name}) -> Future<Client>`, `.archiveClient(String id) -> Future<void>`, `.unarchiveClient(String id) -> Future<void>`, `.deleteClient(String id) -> Future<void>` (throws `ClientHasProjectsException`), `.updateProject(...)` gains `Value<String?> clientId`. New exception class `ClientHasProjectsException implements Exception {}`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/synced_writes_client_test.dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/entity_types.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/sync_paths.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_synced_writes_client_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  SyncEvent lastLoggedEvent(String entityId) {
    final file = currentMonthLogFile(syncRoot, 'dev_a');
    final result = decodeJsonl(file.readAsStringSync());
    return result.events.lastWhere((e) => e.entityId == entityId);
  }

  test('createClient persists the row, returns it, and logs a create event', () async {
    final client = await writes.createClient(name: 'Acme Inc');

    expect(client.name, 'Acme Inc');
    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.name, 'Acme Inc');

    final event = lastLoggedEvent(client.id);
    expect(event.entityType, EntityTypes.client);
    expect(event.op, EventOp.create);
    expect(event.payload?['name'], 'Acme Inc');
  });

  test('updateClient persists the given fields, returns the updated row, and logs the event', () async {
    final client = await writes.createClient(name: 'Old Name');

    final updated = await writes.updateClient(client.id, name: const Value('New Name'));

    expect(updated.name, 'New Name');
    final event = lastLoggedEvent(client.id);
    expect(event.op, EventOp.update);
    expect(event.payload?['name'], 'New Name');
  });

  test('archiveClient marks the client archived and logs the event', () async {
    final client = await writes.createClient(name: 'Acme Inc');

    await writes.archiveClient(client.id);

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isTrue);
    final event = lastLoggedEvent(client.id);
    expect(event.op, EventOp.update);
    expect(event.payload?['archived'], isTrue);
  });

  test('unarchiveClient clears the archived flag and logs the event', () async {
    final client = await writes.createClient(name: 'Acme Inc');
    await writes.archiveClient(client.id);

    await writes.unarchiveClient(client.id);

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isFalse);
  });

  test('deleteClient removes the client and logs a delete event when it has no projects', () async {
    final client = await writes.createClient(name: 'Acme Inc');

    await writes.deleteClient(client.id);

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, isEmpty);
    final event = lastLoggedEvent(client.id);
    expect(event.entityType, EntityTypes.client);
    expect(event.op, EventOp.delete);
    expect(event.payload, isNull);
  });

  test('deleteClient throws and leaves the client untouched when a project references it', () async {
    final client = await writes.createClient(name: 'Acme Inc');
    await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF', clientId: client.id);

    await expectLater(writes.deleteClient(client.id), throwsA(isA<ClientHasProjectsException>()));

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, hasLength(1));
  });
}
```

Also append to `test/data/synced_writes_projects_test.dart` (inside `main()`, after the last test):

```dart
  test('updateProject persists clientId and logs it', () async {
    final client = await writes.createClient(name: 'Acme Inc');
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    final updated = await writes.updateProject(project.id, clientId: Value(client.id));

    expect(updated.clientId, client.id);
    final event = lastLoggedEvent(project.id);
    expect(event.payload?['clientId'], client.id);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/synced_writes_client_test.dart test/data/synced_writes_projects_test.dart`
Expected: FAIL — compile errors (`writes.createClient` etc. don't exist).

- [ ] **Step 3: Implement**

In `lib/data/sync/synced_writes.dart`, add the exception class near `ProjectHasTimeEntriesException`:

```dart
/// Thrown by [SyncedWrites.deleteClient] when the client still has at least
/// one project referencing it -- archiving is the removal path for clients
/// with active projects, deletion is only for clients with none.
class ClientHasProjectsException implements Exception {}
```

Add `clientId` to `updateProject`'s signature and forward it to the DAO (find the existing `updateProject` method and replace it):

```dart
  Future<Project> updateProject(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String> colorHex = const Value.absent(),
    Value<String?> clientId = const Value.absent(),
    Value<bool> billable = const Value.absent(),
    Value<int?> hourlyRateCents = const Value.absent(),
    Value<String?> currency = const Value.absent(),
  }) async {
    await db.projectsDao.updateProject(
      id,
      name: name,
      colorHex: colorHex,
      clientId: clientId,
      billable: billable,
      hourlyRateCents: hourlyRateCents,
      currency: currency,
    );
    return _logCurrentProjectState(id);
  }
```

Add the new client methods (place after `_logCurrentProjectState`, before `startEntry`):

```dart
  Future<Client> createClient({required String name}) async {
    final client = await db.clientsDao.createClient(name: name);
    await logWriter.appendEvent(
      entityType: EntityTypes.client,
      entityId: client.id,
      op: EventOp.create,
      payload: client.toJson(),
    );
    return client;
  }

  Future<Client> updateClient(String id, {Value<String> name = const Value.absent()}) async {
    await db.clientsDao.updateClient(id, name: name);
    return _logCurrentClientState(id);
  }

  Future<void> archiveClient(String id) async {
    await db.clientsDao.archiveClient(id);
    await _logCurrentClientState(id);
  }

  Future<void> unarchiveClient(String id) async {
    await db.clientsDao.unarchiveClient(id);
    await _logCurrentClientState(id);
  }

  Future<void> deleteClient(String id) async {
    final hasProjects = await db.projectsDao.hasProjectsForClient(id);
    if (hasProjects) throw ClientHasProjectsException();
    await db.clientsDao.deleteClient(id);
    await logWriter.appendEvent(
      entityType: EntityTypes.client,
      entityId: id,
      op: EventOp.delete,
      payload: null,
    );
  }

  /// Re-reads the client's current row and appends it as an [EventOp.update]
  /// log entry -- mirrors [_logCurrentProjectState] for clients.
  Future<Client> _logCurrentClientState(String id) async {
    final current = await (db.select(db.clients)..where((c) => c.id.equals(id))).getSingle();
    await logWriter.appendEvent(
      entityType: EntityTypes.client,
      entityId: id,
      op: EventOp.update,
      payload: current.toJson(),
    );
    return current;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/synced_writes_client_test.dart test/data/synced_writes_projects_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS (existing `updateProject` call sites don't pass `clientId`, so `Value.absent()` default keeps their behavior unchanged)

- [ ] **Step 6: Commit**

```bash
git add lib/data/sync/synced_writes.dart test/data/synced_writes_client_test.dart test/data/synced_writes_projects_test.dart
git commit -m "feat(clients): add SyncedWrites client CRUD methods"
```

---

### Task 4: `SyncIngestor` client materialization

**Files:**
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: Append to `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Consumes: `EntityTypes.client`, `Client.fromJson`/`.toCompanion` (Task 1), `SyncedWrites.createClient`/`.archiveClient`/`.deleteClient` (Task 3).
- Produces: no new public API — `SyncIngestor` now actually applies `client` events instead of silently dropping them.

- [ ] **Step 1: Write the failing test**

Append to `test/data/sync_round_trip_test.dart` (inside `main()`, after the last test, before the closing `}`):

```dart
  test(
    'a client syncs to a second device, including archive and delete',
    () async {
      final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(writerDb.close);
      final writerWrites = SyncedWrites(
        db: writerDb,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final client = await writerWrites.createClient(name: 'Acme Inc');
      await writerWrites.archiveClient(client.id);

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final clients = await readerDb.select(readerDb.clients).get();
      expect(clients, hasLength(1));
      expect(clients.single.name, 'Acme Inc');
      expect(clients.single.archived, isTrue);

      await writerWrites.deleteClient(client.id);
      await ingestor.syncNow();

      expect(await readerDb.select(readerDb.clients).get(), isEmpty);
    },
  );

  test(
    'rebuildFromScratch clears and re-derives clients too',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final writes = SyncedWrites(
        db: db,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );
      final ingestor = SyncIngestor(db: db, syncRoot: syncRoot);

      final client = await writes.createClient(name: 'Acme Inc');

      await ingestor.rebuildFromScratch();

      final clients = await db.select(db.clients).get();
      expect(clients, hasLength(1));
      expect(clients.single.id, client.id);
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: FAIL — client events aren't materialized (first new test fails on the `hasLength(1)` expectation, getting `0` instead), and `rebuildFromScratch` wipes but never re-derives (or, since it's not deleted at all yet, may pass the second test by accident — the important failing one is the first).

- [ ] **Step 3: Implement**

In `lib/data/sync/sync_ingestor.dart`:

Add `db.delete(db.clients)` to `rebuildFromScratch`'s transaction:

```dart
  Future<void> rebuildFromScratch() async {
    await db.eventsDao.clearAll();
    await db.transaction(() async {
      await db.delete(db.timeEntries).go();
      await db.delete(db.projects).go();
      await db.delete(db.clients).go();
      await db.delete(db.jiraWorklogs).go();
      await db.delete(db.breakRuleTiers).go();
      await db.delete(db.personioAttendances).go();
    });
    await syncNow();
  }
```

Add a `case EntityTypes.client:` branch to `_applyMaterializedEntity`, right after the existing `case EntityTypes.project:` branch:

```dart
      case EntityTypes.client:
        if (entity.isDeleted) {
          await (db.delete(db.clients)..where((c) => c.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.clients)
              .insertOnConflictUpdate(Client.fromJson(entity.payload!).toCompanion(true));
        }
```

Update the comment on the `default:` fallback (it currently says "Client/Tag aren't wired into the app yet"; client now is):

```dart
      default:
        // Tag isn't wired into the app yet (no DAO to apply it to) --
        // ignored until a later milestone adds it.
        break;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/data/sync/sync_ingestor.dart test/data/sync_round_trip_test.dart
git commit -m "feat(clients): materialize client sync events"
```

---

### Task 5: `clients_providers.dart`

**Files:**
- Create: `lib/features/clients/clients_providers.dart`

**Interfaces:**
- Consumes: `appDatabaseProvider` (`lib/core/di/database_provider.dart`), `ClientsDao` (Task 1).
- Produces: `activeClientsProvider` and `archivedClientsProvider`, both `StreamProvider<List<Client>>`.

- [ ] **Step 1: Write the file**

No test for this task — it's a one-line-per-provider wrapper with no branching logic, exercised indirectly by every widget test in Tasks 7-10 that overrides it. Matches `projects_providers.dart`, which also has no dedicated test file.

```dart
// lib/features/clients/clients_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';

// Plain (non-generated) provider -- see projects_providers.dart for why: a
// generated @riverpod provider returning a drift row type can trip
// riverpod_generator's InvalidTypeException (rrousselGit/riverpod#4323).

final activeClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(appDatabaseProvider).clientsDao.watchActiveClients();
});

final archivedClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(appDatabaseProvider).clientsDao.watchArchivedClients();
});
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/clients/clients_providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/clients/clients_providers.dart
git commit -m "feat(clients): add active/archived client providers"
```

---

### Task 6: i18n keys

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`

**Interfaces:**
- Produces: 18 new ARB keys, used by Tasks 7-10 via the generated `AppLocalizations`.

- [ ] **Step 1: Write the failing test expectation**

`test/l10n/arb_completeness_test.dart` already exists and already enforces parity — no new test needed. Confirm it currently passes before this task (baseline):

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS (baseline, before any edits)

- [ ] **Step 2: Add the keys to `lib/l10n/app_de.arb`**

Insert after the `"projectsInvalidRateError"` line (end of the existing Projects block):

```json
  "settingsClientsTitle": "Kunden",
  "settingsClientsDescription": "Kunden anlegen, bearbeiten und archivieren.",
  "settingsClientsAddLabel": "Kunde hinzufügen",
  "settingsClientsArchivedSection": "Archivierte Kunden",
  "settingsClientsSaveError": "Änderung konnte nicht gespeichert werden.",
  "clientsNewClientTitle": "Neuer Kunde",
  "clientsNameLabel": "Name",
  "clientsCreateButton": "Erstellen",
  "clientsEditTitle": "Kunde bearbeiten",
  "clientsEditTooltip": "Bearbeiten",
  "clientsArchiveTooltip": "Archivieren",
  "clientsUnarchiveTooltip": "Reaktivieren",
  "clientsDeleteTooltip": "Löschen",
  "clientsDeleteConfirmTitle": "Kunde löschen?",
  "clientsDeleteConfirmMessage": "Dieser Kunde wird endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.",
  "clientsDeleteHasProjectsError": "Dieser Kunde hat noch zugewiesene Projekte und kann nicht gelöscht werden.",
  "projectsClientLabel": "Kunde",
  "projectsClientNone": "Kein Kunde",
  "projectsClientCreateNew": "+ Neuer Kunde…",
```

- [ ] **Step 3: Add the keys to `lib/l10n/app_en.arb`**

Insert after `"projectsInvalidRateError"`:

```json
  "settingsClientsTitle": "Clients",
  "settingsClientsDescription": "Create, edit, and archive clients.",
  "settingsClientsAddLabel": "Add client",
  "settingsClientsArchivedSection": "Archived clients",
  "settingsClientsSaveError": "Could not save the change.",
  "clientsNewClientTitle": "New client",
  "clientsNameLabel": "Name",
  "clientsCreateButton": "Create",
  "clientsEditTitle": "Edit client",
  "clientsEditTooltip": "Edit",
  "clientsArchiveTooltip": "Archive",
  "clientsUnarchiveTooltip": "Reactivate",
  "clientsDeleteTooltip": "Delete",
  "clientsDeleteConfirmTitle": "Delete client?",
  "clientsDeleteConfirmMessage": "This client will be permanently deleted. This cannot be undone.",
  "clientsDeleteHasProjectsError": "This client still has projects assigned and can't be deleted.",
  "projectsClientLabel": "Client",
  "projectsClientNone": "No client",
  "projectsClientCreateNew": "+ New client…",
```

- [ ] **Step 4: Add the keys to `lib/l10n/app_es.arb`**

Insert after `"projectsInvalidRateError"`:

```json
  "settingsClientsTitle": "Clientes",
  "settingsClientsDescription": "Crea, edita y archiva clientes.",
  "settingsClientsAddLabel": "Añadir cliente",
  "settingsClientsArchivedSection": "Clientes archivados",
  "settingsClientsSaveError": "No se pudo guardar el cambio.",
  "clientsNewClientTitle": "Nuevo cliente",
  "clientsNameLabel": "Nombre",
  "clientsCreateButton": "Crear",
  "clientsEditTitle": "Editar cliente",
  "clientsEditTooltip": "Editar",
  "clientsArchiveTooltip": "Archivar",
  "clientsUnarchiveTooltip": "Reactivar",
  "clientsDeleteTooltip": "Eliminar",
  "clientsDeleteConfirmTitle": "¿Eliminar cliente?",
  "clientsDeleteConfirmMessage": "Este cliente se eliminará permanentemente. Esta acción no se puede deshacer.",
  "clientsDeleteHasProjectsError": "Este cliente todavía tiene proyectos asignados y no se puede eliminar.",
  "projectsClientLabel": "Cliente",
  "projectsClientNone": "Sin cliente",
  "projectsClientCreateNew": "+ Nuevo cliente…",
```

- [ ] **Step 5: Add the keys to `lib/l10n/app_fr.arb`**

Insert after `"projectsInvalidRateError"`:

```json
  "settingsClientsTitle": "Clients",
  "settingsClientsDescription": "Créer, modifier et archiver des clients.",
  "settingsClientsAddLabel": "Ajouter un client",
  "settingsClientsArchivedSection": "Clients archivés",
  "settingsClientsSaveError": "Impossible d'enregistrer la modification.",
  "clientsNewClientTitle": "Nouveau client",
  "clientsNameLabel": "Nom",
  "clientsCreateButton": "Créer",
  "clientsEditTitle": "Modifier le client",
  "clientsEditTooltip": "Modifier",
  "clientsArchiveTooltip": "Archiver",
  "clientsUnarchiveTooltip": "Réactiver",
  "clientsDeleteTooltip": "Supprimer",
  "clientsDeleteConfirmTitle": "Supprimer le client ?",
  "clientsDeleteConfirmMessage": "Ce client sera définitivement supprimé. Cette action est irréversible.",
  "clientsDeleteHasProjectsError": "Ce client a encore des projets associés et ne peut pas être supprimé.",
  "projectsClientLabel": "Client",
  "projectsClientNone": "Aucun client",
  "projectsClientCreateNew": "+ Nouveau client…",
```

- [ ] **Step 6: Add the keys to `lib/l10n/app_it.arb`**

Insert after `"projectsInvalidRateError"`:

```json
  "settingsClientsTitle": "Clienti",
  "settingsClientsDescription": "Crea, modifica e archivia clienti.",
  "settingsClientsAddLabel": "Aggiungi cliente",
  "settingsClientsArchivedSection": "Clienti archiviati",
  "settingsClientsSaveError": "Impossibile salvare la modifica.",
  "clientsNewClientTitle": "Nuovo cliente",
  "clientsNameLabel": "Nome",
  "clientsCreateButton": "Crea",
  "clientsEditTitle": "Modifica cliente",
  "clientsEditTooltip": "Modifica",
  "clientsArchiveTooltip": "Archivia",
  "clientsUnarchiveTooltip": "Riattiva",
  "clientsDeleteTooltip": "Elimina",
  "clientsDeleteConfirmTitle": "Eliminare il cliente?",
  "clientsDeleteConfirmMessage": "Questo cliente verrà eliminato definitivamente. Questa azione non può essere annullata.",
  "clientsDeleteHasProjectsError": "Questo cliente ha ancora progetti assegnati e non può essere eliminato.",
  "projectsClientLabel": "Cliente",
  "projectsClientNone": "Nessun cliente",
  "projectsClientCreateNew": "+ Nuovo cliente…",
```

- [ ] **Step 7: Add the keys to `lib/l10n/app_nl.arb`**

Insert after `"projectsInvalidRateError"`:

```json
  "settingsClientsTitle": "Klanten",
  "settingsClientsDescription": "Klanten aanmaken, bewerken en archiveren.",
  "settingsClientsAddLabel": "Klant toevoegen",
  "settingsClientsArchivedSection": "Gearchiveerde klanten",
  "settingsClientsSaveError": "Wijziging kon niet worden opgeslagen.",
  "clientsNewClientTitle": "Nieuwe klant",
  "clientsNameLabel": "Naam",
  "clientsCreateButton": "Aanmaken",
  "clientsEditTitle": "Klant bewerken",
  "clientsEditTooltip": "Bewerken",
  "clientsArchiveTooltip": "Archiveren",
  "clientsUnarchiveTooltip": "Heractiveren",
  "clientsDeleteTooltip": "Verwijderen",
  "clientsDeleteConfirmTitle": "Klant verwijderen?",
  "clientsDeleteConfirmMessage": "Deze klant wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.",
  "clientsDeleteHasProjectsError": "Deze klant heeft nog gekoppelde projecten en kan niet worden verwijderd.",
  "projectsClientLabel": "Klant",
  "projectsClientNone": "Geen klant",
  "projectsClientCreateNew": "+ Nieuwe klant…",
```

- [ ] **Step 8: Regenerate localizations and verify**

Run: `flutter gen-l10n`
Expected: completes without error, `lib/l10n/app_localizations*.dart` updated with the new getters.

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/l10n/
git commit -m "feat(clients): add client management i18n strings"
```

---

### Task 7: `client_form_dialog.dart`

**Files:**
- Create: `lib/features/clients/client_form_dialog.dart`
- Test: `test/features/clients/client_form_dialog_test.dart`

**Interfaces:**
- Consumes: `SyncedWrites.createClient`/`.updateClient` (Task 3), `syncedWritesProvider` (`lib/core/di/sync_providers.dart`), `Client` (Task 1), l10n keys from Task 6.
- Produces: `Future<Client?> showClientFormDialog(BuildContext context, WidgetRef ref, {Client? client})` — returns the created/updated `Client` so `project_form_dialog.dart` (Task 10) can select it immediately; returns `null` if cancelled.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/clients/client_form_dialog_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/clients/client_form_dialog.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_client_form_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp({Client? client}) => ProviderScope(
        overrides: [
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
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showClientFormDialog(context, ref, client: client),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('create mode: submitting with a name creates a client', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Acme Inc');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.clients).get()).isNotEmpty);
    });

    final clients = await db.select(db.clients).get();
    expect(clients, hasLength(1));
    expect(clients.single.name, 'Acme Inc');
  });

  testWidgets('create mode: submitting with an empty name does not create a client', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    expect(await db.select(db.clients).get(), isEmpty);
  });

  testWidgets('edit mode: field is pre-filled from the passed client', (tester) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    await tester.pumpWidget(makeApp(client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit client'), findsOneWidget);
    expect(find.text('Acme Inc'), findsOneWidget);
  });

  testWidgets('edit mode: submitting updates the existing client rather than creating a new one', (
    tester,
  ) async {
    final client = await db.clientsDao.createClient(name: 'Old Name');
    await tester.pumpWidget(makeApp(client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Name');

    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await pumpUntilTrue(tester, () async {
        final rows = await db.select(db.clients).get();
        return rows.length == 1 && rows.single.name == 'New Name';
      });
    });

    final clients = await db.select(db.clients).get();
    expect(clients, hasLength(1));
    expect(clients.single.name, 'New Name');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/clients/client_form_dialog_test.dart`
Expected: FAIL — `lib/features/clients/client_form_dialog.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

```dart
// lib/features/clients/client_form_dialog.dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';

/// Shows the create/edit dialog for a client. Pass [client] to edit an
/// existing one (field pre-filled, submit calls SyncedWrites.updateClient);
/// omit it to create a new one (submit calls SyncedWrites.createClient).
/// Resolves to the created/updated [Client] on submit, or `null` if the
/// dialog is cancelled -- callers that need the result (e.g. the project
/// form's inline "create client" picker entry) can await it directly.
Future<Client?> showClientFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Client? client,
}) {
  final nameController = TextEditingController(text: client?.name ?? '');
  return showDialog<Client?>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(client == null ? l10n.clientsNewClientTitle : l10n.clientsEditTitle),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.clientsNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final writes = await ref.read(syncedWritesProvider.future);
              final Client saved;
              if (client == null) {
                saved = await writes.createClient(name: name);
              } else {
                saved = await writes.updateClient(client.id, name: Value(name));
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop(saved);
            },
            child: Text(client == null ? l10n.clientsCreateButton : l10n.commonSave),
          ),
        ],
      );
    },
  ).whenComplete(nameController.dispose);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/clients/client_form_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/client_form_dialog.dart test/features/clients/client_form_dialog_test.dart
git commit -m "feat(clients): add client create/edit dialog"
```

---

### Task 8: `clients_editor.dart`

**Files:**
- Create: `lib/features/clients/clients_editor.dart`
- Test: `test/features/clients/clients_editor_test.dart`

**Interfaces:**
- Consumes: `activeClientsProvider`/`archivedClientsProvider` (Task 5), `showClientFormDialog` (Task 7), `SyncedWrites.archiveClient`/`.unarchiveClient`/`.deleteClient` (Task 3), `ClientHasProjectsException` (Task 3), l10n keys from Task 6.
- Produces: `ClientsEditor extends ConsumerStatefulWidget` — no constructor params.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/clients/clients_editor_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/clients/clients_editor.dart';
import 'package:hickory/features/clients/clients_providers.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_clients_editor_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // Same static-stream-override technique as projects_editor_test.dart --
  // avoids a known flutter_test false positive with live drift QueryStreams.
  Widget makeApp({
    List<Client> active = const [],
    List<Client> archived = const [],
  }) => ProviderScope(
        overrides: [
          activeClientsProvider.overrideWith((ref) => Stream.value(active)),
          archivedClientsProvider.overrideWith((ref) => Stream.value(archived)),
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
          home: const Scaffold(body: SingleChildScrollView(child: ClientsEditor())),
        ),
      );

  Future<Client> seedClient({bool archived = false}) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    if (archived) await db.clientsDao.archiveClient(client.id);
    return (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
  }

  testWidgets('renders active clients with edit, archive, and delete actions', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    expect(find.text('Acme Inc'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('archived section is hidden when there are no archived clients', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Archived clients'), findsNothing);
  });

  testWidgets('tapping archive marks the client archived in the database', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.archive_outlined));
      await pumpUntilTrue(tester, () async {
        final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
        return row.archived;
      });
    });

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isTrue);
  });

  testWidgets('archived clients render under the collapsible section with a reactivate action', (
    tester,
  ) async {
    final client = await seedClient(archived: true);
    await tester.pumpWidget(makeApp(archived: [client]));
    await tester.pumpAndSettle();

    expect(find.text('Archived clients'), findsOneWidget);
    await tester.tap(find.text('Archived clients'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Inc'), findsOneWidget);
    expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
  });

  testWidgets('tapping "Add client" opens the create dialog', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add client'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
  });

  testWidgets('confirming delete removes a client with no projects from the database', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete client?'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntilTrue(tester, () async {
        final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
        return remaining.isEmpty;
      });
    });

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, isEmpty);
  });

  testWidgets('attempting to delete a client with projects shows the blocked-delete error', (
    tester,
  ) async {
    final client = await seedClient();
    await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF', clientId: client.id);
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntilTrue(tester, () async {
        await tester.pump();
        return find.text("This client still has projects assigned and can't be deleted.").evaluate().isNotEmpty;
      });
    });

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, hasLength(1));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/clients/clients_editor_test.dart`
Expected: FAIL — `lib/features/clients/clients_editor.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

```dart
// lib/features/clients/clients_editor.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart' show ClientHasProjectsException;
import '../../l10n/app_localizations.dart';
import 'client_form_dialog.dart';
import 'clients_providers.dart';

/// Settings-screen client manager: create/edit/archive active clients,
/// reactivate archived ones, delete unused ones. Lives in the `clients`
/// feature (not `settings/`), same placement rationale as `ProjectsEditor` --
/// see docs/superpowers/specs/2026-08-13-client-management-design.md.
class ClientsEditor extends ConsumerStatefulWidget {
  const ClientsEditor({super.key});

  @override
  ConsumerState<ClientsEditor> createState() => _ClientsEditorState();
}

class _ClientsEditorState extends ConsumerState<ClientsEditor> {
  bool _busy = false;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save client change: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsClientsSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.archiveClient(id);
      });

  Future<void> _unarchive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.unarchiveClient(id);
      });

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clientsDeleteConfirmTitle),
        content: Text(l10n.clientsDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      try {
        await writes.deleteClient(id);
      } on ClientHasProjectsException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.clientsDeleteHasProjectsError)),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeClients = ref.watch(activeClientsProvider).value ?? const <Client>[];
    final archivedClients = ref.watch(archivedClientsProvider).value ?? const <Client>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsClientsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsClientsDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final client in activeClients)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(client.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.clientsEditTooltip,
                  onPressed: _busy
                      ? null
                      : () => showClientFormDialog(context, ref, client: client),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  tooltip: l10n.clientsArchiveTooltip,
                  onPressed: _busy ? null : () => _archive(client.id),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.clientsDeleteTooltip,
                  onPressed: _busy ? null : () => _delete(client.id),
                ),
              ],
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsClientsAddLabel),
          onPressed: _busy ? null : () => showClientFormDialog(context, ref),
        ),
        if (archivedClients.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.settingsClientsArchivedSection),
            children: [
              for (final client in archivedClients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    client.name,
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.unarchive_outlined),
                        tooltip: l10n.clientsUnarchiveTooltip,
                        onPressed: _busy ? null : () => _unarchive(client.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.clientsDeleteTooltip,
                        onPressed: _busy ? null : () => _delete(client.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/clients/clients_editor_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/clients_editor.dart test/features/clients/clients_editor_test.dart
git commit -m "feat(clients): add clients editor widget"
```

---

### Task 9: Settings wiring (`ClientsSettingsScreen` + home screen row)

**Files:**
- Create: `lib/features/settings/clients_settings_screen.dart`
- Modify: `lib/features/settings/settings_home_screen.dart`
- Modify: `test/features/settings/settings_home_screen_test.dart`

**Interfaces:**
- Consumes: `ClientsEditor` (Task 8), `SettingsSubPage` (`lib/features/settings/settings_sub_page.dart`, existing).
- Produces: `ClientsSettingsScreen extends StatelessWidget`.

- [ ] **Step 1: Write the failing test changes**

In `test/features/settings/settings_home_screen_test.dart`:

Add imports (alongside the existing `hickory/features/projects/projects_providers.dart` and `hickory/features/settings/projects_settings_screen.dart` lines):

```dart
import 'package:hickory/features/clients/clients_providers.dart';
import 'package:hickory/features/settings/clients_settings_screen.dart';
```

Add provider overrides in `makeApp()`'s `overrides:` list, next to the existing `activeProjectsProvider`/`archivedProjectsProvider` overrides:

```dart
      activeClientsProvider.overrideWith((ref) => Stream.value(const [])),
      archivedClientsProvider.overrideWith((ref) => Stream.value(const [])),
```

In the `'shows all category rows'` test, add after the `expect(find.text('Projects'), findsOneWidget);` line:

```dart
    expect(find.text('Clients'), findsOneWidget);
```

In the `'tapping each category row navigates...'` test, add after `await tapAndVerify('Projects', ProjectsSettingsScreen);`:

```dart
      await tapAndVerify('Clients', ClientsSettingsScreen);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/settings_home_screen_test.dart`
Expected: FAIL — compile error (`ClientsSettingsScreen`, `activeClientsProvider` don't exist as imported), or a `findsOneWidget` failure for `'Clients'`.

- [ ] **Step 3: Implement `ClientsSettingsScreen`**

```dart
// lib/features/settings/clients_settings_screen.dart
import 'package:flutter/material.dart';

import '../clients/clients_editor.dart';
import 'settings_sub_page.dart';

/// No page title -- ClientsEditor already renders l10n.settingsClientsTitle
/// as its own heading (see settings_sub_page.dart's doc comment).
class ClientsSettingsScreen extends StatelessWidget {
  const ClientsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubPage(
      child: SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(padding: EdgeInsets.all(16), child: ClientsEditor()),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire the new category row into `settings_home_screen.dart`**

Add the import:

```dart
import 'clients_settings_screen.dart';
```

(alongside the other `import '...screen.dart';` lines, alphabetically before `general_settings_screen.dart`)

Add a new `ListTile` + `Divider` right after the existing "Projects" `ListTile` block (i.e. right after its closing `),` and before the `if (Platform.isMacOS || Platform.isWindows) ...[` block):

```dart
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(l10n.settingsClientsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ClientsSettingsScreen(),
                    ),
                  ),
                ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/settings/settings_home_screen_test.dart`
Expected: PASS

- [ ] **Step 6: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/clients_settings_screen.dart lib/features/settings/settings_home_screen.dart test/features/settings/settings_home_screen_test.dart
git commit -m "feat(clients): add Clients settings category"
```

---

### Task 10: Client picker in `project_form_dialog.dart`

**Files:**
- Modify: `lib/features/projects/project_form_dialog.dart`
- Modify: `test/features/projects/project_form_dialog_test.dart`

**Interfaces:**
- Consumes: `activeClientsProvider` (Task 5), `showClientFormDialog` (Task 7), `SyncedWrites.createProject`/`.updateProject` with `clientId` (Tasks 2-3).
- Produces: no new public API — `showProjectFormDialog`'s existing signature is unchanged; it now also lets the user pick/create a client.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/projects/project_form_dialog_test.dart`: an import and three new tests.

Add import (alongside the existing `hickory/data/drift/database.dart` import):

```dart
import 'package:hickory/features/clients/clients_providers.dart';
```

Change `makeApp` to also override the client providers (find the existing `Widget makeApp({Project? project}) => ProviderScope(overrides: [` block and add to its `overrides:` list):

```dart
          activeClientsProvider.overrideWith((ref) => Stream.value(const <Client>[])),
```

Append these tests inside `main()`, after the last existing test:

```dart
  testWidgets('create mode: selecting an existing client sets clientId on submit', (tester) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          activeClientsProvider.overrideWith((ref) => Stream.value([client])),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showProjectFormDialog(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Inc').last);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final projects = await db.select(db.projects).get();
    expect(projects.single.clientId, client.id);
  });

  testWidgets('create mode: creating a client inline via the picker selects it, and it stays selected', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New client…').last);
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Acme Inc');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create').last);
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.clients).get()).isNotEmpty);
    });
    await tester.pumpAndSettle();

    // The dropdown must show the freshly-created client without re-opening
    // it -- this is the regression the ValueKey(selectedClientId) fix in
    // Step 3 guards against.
    expect(find.text('Acme Inc'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Create').first);
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final client = (await db.select(db.clients).get()).single;
    final project = (await db.select(db.projects).get()).single;
    expect(project.clientId, client.id);
  });

  testWidgets('create mode: leaving the client picker on "No client" submits a null clientId', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final projects = await db.select(db.projects).get();
    expect(projects.single.clientId, isNull);
  });

  testWidgets('edit mode: pre-selects the project\'s existing client', (tester) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    final project = await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#5B8DEF',
      clientId: client.id,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          activeClientsProvider.overrideWith((ref) => Stream.value([client])),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showProjectFormDialog(context, ref, project: project),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Inc'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/projects/project_form_dialog_test.dart`
Expected: FAIL — compile error (`activeClientsProvider` not imported by the dialog yet / no dropdown widget present).

- [ ] **Step 3: Implement the picker**

In `lib/features/projects/project_form_dialog.dart`:

Add imports:

```dart
import '../clients/client_form_dialog.dart';
import '../clients/clients_providers.dart';
```

Add a sentinel constant near `projectColorPalette`:

```dart
const _createNewClientSentinel = '__create_new_client__';
```

Change `showProjectFormDialog` to accept `WidgetRef ref` for reading `activeClientsProvider` inside the dialog (it already receives `ref` as a parameter) and add client-selection state. Insert `var selectedClientId = project?.clientId;` alongside the existing `var selectedColor = ...` / `var billable = ...` declarations:

```dart
  var selectedColor = project?.colorHex ?? projectColorPalette.first;
  var selectedClientId = project?.clientId;
  var billable = project?.billable ?? true;
```

Insert the picker in the dialog's `content` `Column`, between the Name `TextField` and the color palette `Wrap` (i.e. right after the Name field's `const SizedBox(height: 12),` and before `Wrap(`):

```dart
                  Consumer(
                    builder: (context, ref, _) {
                      final clients = ref.watch(activeClientsProvider).value ?? const <Client>[];
                      final validIds = clients.map((c) => c.id).toSet();
                      return DropdownButtonFormField<String?>(
                        // DropdownButtonFormField only reads initialValue when its
                        // State is first created, not on every rebuild -- without
                        // this key, picking "+ New client..." updates
                        // selectedClientId (used correctly on submit) but the
                        // dropdown itself would keep showing the old selection.
                        // Keying on selectedClientId forces a fresh State (and
                        // therefore a fresh initialValue read) whenever it changes.
                        key: ValueKey(selectedClientId),
                        initialValue: validIds.contains(selectedClientId) ? selectedClientId : null,
                        decoration: InputDecoration(labelText: l10n.projectsClientLabel),
                        items: [
                          DropdownMenuItem(value: null, child: Text(l10n.projectsClientNone)),
                          for (final client in clients)
                            DropdownMenuItem(value: client.id, child: Text(client.name)),
                          DropdownMenuItem(
                            value: _createNewClientSentinel,
                            child: Text(l10n.projectsClientCreateNew),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value != _createNewClientSentinel) {
                            setDialogState(() => selectedClientId = value);
                            return;
                          }
                          final created = await showClientFormDialog(context, ref);
                          if (created != null) {
                            setDialogState(() => selectedClientId = created.id);
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
```

Change the submit handler (`FilledButton`'s `onPressed`) to pass `clientId`. In the `if (project == null)` branch, add `clientId: selectedClientId,` to the `writes.createProject(...)` call; in the `else` branch, add `clientId: Value(selectedClientId),` to the `writes.updateProject(...)` call:

```dart
                  if (project == null) {
                    await writes.createProject(
                      name: name,
                      colorHex: selectedColor,
                      clientId: selectedClientId,
                      billable: billable,
                      hourlyRateCents: rateCents,
                      currency: currency.isEmpty ? null : currency,
                    );
                  } else {
                    await writes.updateProject(
                      project.id,
                      name: Value(name),
                      colorHex: Value(selectedColor),
                      clientId: Value(selectedClientId),
                      billable: Value(billable),
                      hourlyRateCents: Value(rateCents),
                      currency: Value(currency.isEmpty ? null : currency),
                    );
                  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/projects/project_form_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 6: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/projects/project_form_dialog.dart test/features/projects/project_form_dialog_test.dart
git commit -m "feat(clients): add client picker to the project form dialog"
```

---

## Final Verification

- [ ] Run the full suite one more time: `flutter test`
- [ ] Run `flutter analyze` with zero issues
- [ ] Manually smoke-test: Settings → Clients → add a client → Settings → Projects → new project → select that client → save → edit the project again and confirm the client is still selected → go back to Settings → Clients → try deleting the client (should be blocked with the error message) → archive the project's... actually delete the project first, then delete the client (should now succeed).
