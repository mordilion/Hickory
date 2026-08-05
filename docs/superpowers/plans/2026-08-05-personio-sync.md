# Personio Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user manually push finished time entries to Personio as `WORK`
attendance periods, via a date-range-scoped "Push" button in a new "Personio
Integration" section of the Sync screen.

**Architecture:** A synced tracking table (`PersonioAttendances`, one row per time
entry) records push status, mirroring the existing `JiraWorklogs`/`JiraSyncService`
architecture end-to-end: credentials store → API client → sync service → Riverpod
providers → Settings UI. The two structural differences from Jira: every finished
entry in the selected date range is a push candidate (no per-entry opt-in field),
and the Personio API needs OAuth2 client-credentials token caching (Jira's client
uses stateless Basic auth).

**Tech Stack:** Flutter, Riverpod (plain providers — drift-generated types must not
go through `@riverpod` codegen, see Global Constraints), Drift, `http` (already a
dependency, same package `HttpJiraClient` uses), `mocktail` (already a dev
dependency, used by `jira_sync_service_test.dart`).

**Full design:** `docs/superpowers/specs/2026-08-05-personio-sync-design.md`

## Global Constraints

- English only in code, comments, and commit messages.
- Every new file mirrors an existing Jira-integration file 1:1 in shape and
  location — when in doubt, read the Jira equivalent named in that task.
- ARB template locale is **German** (`lib/l10n/app_de.arb`,
  `template-arb-file: app_de.arb` in `l10n.yaml`). `test/l10n/arb_completeness_test.dart`
  fails the build if any of the 6 locale files' key sets diverge. This codebase's
  convention (confirmed against `syncJiraSyncResult`) is to include a message's
  `@key` placeholder-type metadata block in **every** locale file, not just the
  template — follow that for `syncPersonioPushResult`. After editing ARB files,
  run `flutter gen-l10n` before running any test that uses the new keys.
- Providers touching Drift-generated row classes (`PersonioAttendanceRow`, ...)
  must be **plain** `Provider`/`FutureProvider`/`StreamProvider`, not `@riverpod`
  codegen — mixing riverpod_generator with drift's generator on the same type trips
  `rrousselGit/riverpod#4323` (see `lib/core/di/jira_providers.dart` for the
  existing precedent this plan's `personio_providers.dart` follows).
- This plan **adds a new Drift table** (`PersonioAttendances`) — unlike the
  project-editing and resizable-window plans, this DOES require running
  `dart run build_runner build --delete-conflicting-outputs` after Task 1's table/DAO
  are created (`PersonioAttendancesDao`'s generated `_$PersonioAttendancesDaoMixin`
  and `database.g.dart`'s `Project`-equivalent for the new table don't exist until
  codegen runs).
- Every new synced entity follows the exact existing pattern: Drift table → DAO →
  `EntityTypes` constant → `SyncedWrites` write-through method(s) →
  `SyncIngestor._applyMaterializedEntity` case → `SyncIngestor.rebuildFromScratch`
  gets the new table added to its delete list → round-trip test in
  `test/data/sync_round_trip_test.dart`.
- `PersonioAttendances` has **no** `.references(TimeEntries, #id)` foreign key —
  same reasoning as `JiraWorklogs`: the tracking row must be able to outlive its
  time entry so a delete can still be pushed to Personio after the entry itself is
  gone locally.
- Personio v2 API `[verified against developer.personio.de]`: auth is OAuth2
  client-credentials at `POST https://api.personio.de/v2/auth/token`
  (`application/x-www-form-urlencoded`, fields `grant_type=client_credentials`,
  `client_id`, `client_secret`); attendance periods are
  `POST/PATCH/DELETE https://api.personio.de/v2/attendance-periods[/{id}]`, create/
  update use `?skip_approval=true` (confirmed product decision — pushed periods are
  immediately final, no manager approval step), body fields `person` (object),
  `type` (`"WORK"`/`"BREAK"`, always `"WORK"` here), `start`/`end` (objects),
  `comment` (string, optional). **`[inferred, not verified against a live call]`**:
  the exact nesting of the `person`/`start`/`end` objects — this plan uses
  `{"id": employeeId}` for `person` and `{"date_time": <ISO8601>}` for
  `start`/`end` as the most REST-conventional shape; per explicit instruction this
  is not being verified against a real Personio account before implementation. The
  first real "Test connection" / push against a live account is what actually
  confirms or corrects this — if it's wrong, `HttpPersonioClient`'s request-body
  construction (`_attendanceBody`) is the only place that needs to change.
- Only `WORK` periods are pushed; no `BREAK` periods, no project mapping (Personio's
  optional `project` field is never sent) — explicit design decisions.
- No dedicated widget test for the Sync screen — matches this codebase's existing
  convention exactly: the Jira section in `sync_screen.dart` has zero test coverage
  today (no `test/features/sync/` directory exists). Task 6 is verified via
  `flutter analyze` + the full `flutter test` suite, not a new widget test file.
- Date-range comparison is by **local calendar date only** (year/month/day),
  ignoring time-of-day — a push range is "which days", not "which instants".

---

### Task 1: `PersonioAttendances` table, DAO, migration, sync wiring

**Files:**
- Create: `lib/data/drift/tables/personio_attendances_table.dart`
- Create: `lib/data/drift/daos/personio_attendances_dao.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/sync/entity_types.dart`
- Modify: `lib/data/sync/sync_ingestor.dart`
- Test: `test/data/drift/personio_attendances_dao_test.dart`

**Interfaces:**
- Produces: `PersonioAttendances` table with `@DataClassName('PersonioAttendanceRow')`,
  columns `id` (text, PK, same id as the tracked `TimeEntry`), `personioAttendanceId`
  (text, nullable), `status` (text, default `PersonioAttendanceStatus.pending`),
  `lastError` (text, nullable), `syncedAt` (datetime, nullable).
  `PersonioAttendanceStatus` constants: `pending`, `synced`, `error`,
  `pendingDelete`. `PersonioAttendancesDao` with `watchAll()`, `getAll()`,
  `getForEntry(String)`, `upsert(Insertable<PersonioAttendanceRow>)`,
  `deleteForEntry(String)`, `latestSyncedAt() -> Future<DateTime?>`.
  `EntityTypes.personioAttendance = 'personio_attendance'`. `AppDatabase.schemaVersion == 8`.

- [ ] **Step 1: Create the table**

Create `lib/data/drift/tables/personio_attendances_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Values used in [PersonioAttendanceRow.status].
abstract final class PersonioAttendanceStatus {
  static const pending = 'pending';
  static const synced = 'synced';
  static const error = 'error';
  static const pendingDelete = 'pendingDelete';
}

/// Tracks the Personio attendance-period push state for one time entry (1:1,
/// keyed by the entry's own id). Deliberately has no `.references(TimeEntries,
/// #id)` -- this row must be able to outlive its time entry so a delete can
/// still be pushed to Personio after the entry itself is gone locally (see
/// [PersonioAttendanceStatus.pendingDelete]).
///
/// Synced across the user's own devices via the event log (see
/// EntityTypes.personioAttendance) -- otherwise a second device wouldn't know
/// an entry was already pushed and would create a duplicate attendance period
/// on its own next push. See
/// docs/superpowers/specs/2026-08-05-personio-sync-design.md.
@DataClassName('PersonioAttendanceRow')
class PersonioAttendances extends Table {
  TextColumn get id => text()();
  // Personio-assigned attendance-period id; null until the first successful push.
  TextColumn get personioAttendanceId => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant(PersonioAttendanceStatus.pending))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Create the DAO**

Create `lib/data/drift/daos/personio_attendances_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/personio_attendances_table.dart';

part 'personio_attendances_dao.g.dart';

@DriftAccessor(tables: [PersonioAttendances])
class PersonioAttendancesDao extends DatabaseAccessor<AppDatabase>
    with _$PersonioAttendancesDaoMixin {
  PersonioAttendancesDao(super.db);

  Stream<List<PersonioAttendanceRow>> watchAll() => select(personioAttendances).watch();

  Future<List<PersonioAttendanceRow>> getAll() => select(personioAttendances).get();

  Future<PersonioAttendanceRow?> getForEntry(String timeEntryId) {
    return (select(personioAttendances)..where((a) => a.id.equals(timeEntryId)))
        .getSingleOrNull();
  }

  Future<void> upsert(Insertable<PersonioAttendanceRow> row) {
    return into(personioAttendances).insertOnConflictUpdate(row);
  }

  Future<void> deleteForEntry(String timeEntryId) {
    return (delete(personioAttendances)..where((a) => a.id.equals(timeEntryId))).go();
  }

  /// Latest [PersonioAttendanceRow.syncedAt] among rows with
  /// `status == synced`, or null if nothing has ever been pushed. Used to
  /// default the Sync screen's push-range picker to "the day after the last
  /// successful push".
  Future<DateTime?> latestSyncedAt() async {
    final rows = await (select(personioAttendances)
          ..where((a) => a.status.equals(PersonioAttendanceStatus.synced)))
        .get();
    if (rows.isEmpty) return null;
    return rows.map((r) => r.syncedAt!).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
```

- [ ] **Step 3: Register the table/DAO, bump schema version, add the migration**

Edit `lib/data/drift/database.dart`. Find:

```dart
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
  int get schemaVersion => 7;

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
      if (from < 7) {
        await m.addColumn(appSettings, appSettings.countPausedTimeAsBreak);
      }
    },
  );
```

Replace it with:

```dart
import 'daos/activity_samples_dao.dart';
import 'daos/app_settings_dao.dart';
import 'daos/break_rule_tiers_dao.dart';
import 'daos/events_dao.dart';
import 'daos/jira_worklogs_dao.dart';
import 'daos/personio_attendances_dao.dart';
import 'daos/projects_dao.dart';
import 'daos/time_entries_dao.dart';
import 'tables/activity_samples_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/break_rule_tiers_table.dart';
import 'tables/clients_table.dart';
import 'tables/events_table.dart';
import 'tables/jira_worklogs_table.dart';
import 'tables/personio_attendances_table.dart';
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
    PersonioAttendances,
  ],
  daos: [
    ProjectsDao,
    TimeEntriesDao,
    EventsDao,
    ActivitySamplesDao,
    AppSettingsDao,
    JiraWorklogsDao,
    BreakRuleTiersDao,
    PersonioAttendancesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 8;

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
      if (from < 7) {
        await m.addColumn(appSettings, appSettings.countPausedTimeAsBreak);
      }
      if (from < 8) {
        await m.createTable(personioAttendances);
      }
    },
  );
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors; `lib/data/drift/database.g.dart` and
`lib/data/drift/daos/personio_attendances_dao.g.dart` are generated/updated.

- [ ] **Step 5: Register the entity type**

Edit `lib/data/sync/entity_types.dart`. Find:

```dart
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

Replace it with:

```dart
abstract final class EntityTypes {
  static const project = 'project';
  static const timeEntry = 'time_entry';
  static const client = 'client';
  static const tag = 'tag';
  static const activitySample = 'activity_sample';
  static const appSettings = 'app_settings';
  static const jiraWorklog = 'jira_worklog';
  static const breakRuleTier = 'break_rule_tier';
  static const personioAttendance = 'personio_attendance';
}
```

- [ ] **Step 6: Wire the ingestor**

Edit `lib/data/sync/sync_ingestor.dart`. Find:

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

Replace it with:

```dart
  Future<void> rebuildFromScratch() async {
    await db.eventsDao.clearAll();
    await db.transaction(() async {
      await db.delete(db.timeEntries).go();
      await db.delete(db.projects).go();
      await db.delete(db.jiraWorklogs).go();
      await db.delete(db.breakRuleTiers).go();
      await db.delete(db.personioAttendances).go();
    });
    await syncNow();
  }
```

Find:

```dart
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

Replace it with:

```dart
      case EntityTypes.breakRuleTier:
        if (entity.isDeleted) {
          await (db.delete(db.breakRuleTiers)..where((t) => t.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.breakRuleTiers)
              .insertOnConflictUpdate(BreakRuleTier.fromJson(entity.payload!).toCompanion(true));
        }
      case EntityTypes.personioAttendance:
        if (entity.isDeleted) {
          await (db.delete(db.personioAttendances)..where((a) => a.id.equals(entity.entityId))).go();
        } else {
          await db
              .into(db.personioAttendances)
              .insertOnConflictUpdate(
                PersonioAttendanceRow.fromJson(entity.payload!).toCompanion(true),
              );
        }
      default:
```

- [ ] **Step 7: Write the DAO test**

Create `test/data/drift/personio_attendances_dao_test.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert creates a pending row with no personioAttendanceId yet', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));

    final row = await db.personioAttendancesDao.getForEntry('entry_1');
    expect(row, isNotNull);
    expect(row!.status, PersonioAttendanceStatus.pending);
    expect(row.personioAttendanceId, isNull);
  });

  test('upsert on an existing id updates it in place', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_1',
        personioAttendanceId: const Value('period-1'),
        status: const Value(PersonioAttendanceStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 12)),
      ),
    );

    final rows = await db.personioAttendancesDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.personioAttendanceId, 'period-1');
    expect(rows.single.status, PersonioAttendanceStatus.synced);
  });

  test('deleteForEntry removes the tracking row', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));
    await db.personioAttendancesDao.deleteForEntry('entry_1');

    expect(await db.personioAttendancesDao.getForEntry('entry_1'), isNull);
  });

  test('latestSyncedAt returns null when nothing has been synced', () async {
    await db.personioAttendancesDao.upsert(PersonioAttendancesCompanion.insert(id: 'entry_1'));

    expect(await db.personioAttendancesDao.latestSyncedAt(), isNull);
  });

  test('latestSyncedAt returns the newest syncedAt among synced rows only', () async {
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_1',
        status: const Value(PersonioAttendanceStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 10)),
      ),
    );
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_2',
        status: const Value(PersonioAttendanceStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 15)),
      ),
    );
    // An error row with a later syncedAt-looking value must not win -- only
    // `synced` rows count.
    await db.personioAttendancesDao.upsert(
      PersonioAttendancesCompanion.insert(
        id: 'entry_3',
        status: const Value(PersonioAttendanceStatus.error),
        syncedAt: Value(DateTime.utc(2026, 7, 20)),
      ),
    );

    expect(await db.personioAttendancesDao.latestSyncedAt(), DateTime.utc(2026, 7, 15));
  });
}
```

- [ ] **Step 8: Run the test**

Run: `flutter test test/data/drift/personio_attendances_dao_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 9: Commit**

```bash
git add lib/data/drift/tables/personio_attendances_table.dart lib/data/drift/daos/personio_attendances_dao.dart lib/data/drift/daos/personio_attendances_dao.g.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/sync/entity_types.dart lib/data/sync/sync_ingestor.dart test/data/drift/personio_attendances_dao_test.dart
git commit -m "feat(personio): add PersonioAttendances table and sync wiring"
```

---

### Task 2: Personio credentials and API client

**Files:**
- Create: `lib/features/personio/personio_credentials_store.dart`
- Create: `lib/features/personio/secure_personio_credentials_store.dart`
- Create: `lib/features/personio/personio_client.dart`
- Create: `lib/features/personio/http_personio_client.dart`
- Test: `test/features/personio/http_personio_client_test.dart`

**Interfaces:**
- Produces: `PersonioCredentials({required clientId, required clientSecret, required
  employeeId})`. `PersonioCredentialsStore` abstract (`read()`, `write(...)`,
  `clear()`) + `SecurePersonioCredentialsStore` implementation. `PersonioApiException`
  (message-only). `PersonioClient` abstract: `testConnection() -> Future<bool>`,
  `createAttendance({required DateTime start, required DateTime end, String?
  comment}) -> Future<String>`, `updateAttendance({required String periodId,
  required DateTime start, required DateTime end, String? comment}) -> Future<void>`,
  `deleteAttendance({required String periodId}) -> Future<void>`.
  `HttpPersonioClient({required PersonioCredentials credentials, http.Client?
  httpClient})` implements it.

- [ ] **Step 1: Create the credentials type and store interface**

Create `lib/features/personio/personio_credentials_store.dart`:

```dart
/// Personio API credentials needed to authenticate and identify the user's
/// own employee record.
class PersonioCredentials {
  const PersonioCredentials({
    required this.clientId,
    required this.clientSecret,
    required this.employeeId,
  });

  final String clientId;
  final String clientSecret;
  final String employeeId;
}

/// Reads/writes the Personio connection details this device uses to talk to
/// Personio. Deliberately per-device and never synced -- same reasoning as
/// JiraCredentialsStore: secrets must not enter the synced event log.
abstract class PersonioCredentialsStore {
  Future<PersonioCredentials?> read();
  Future<void> write(PersonioCredentials credentials);
  Future<void> clear();
}
```

- [ ] **Step 2: Create the secure storage implementation**

Create `lib/features/personio/secure_personio_credentials_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'personio_credentials_store.dart';

class SecurePersonioCredentialsStore implements PersonioCredentialsStore {
  SecurePersonioCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _clientIdKey = 'personio_client_id';
  static const _clientSecretKey = 'personio_client_secret';
  static const _employeeIdKey = 'personio_employee_id';

  @override
  Future<PersonioCredentials?> read() async {
    final clientId = await _storage.read(key: _clientIdKey);
    final clientSecret = await _storage.read(key: _clientSecretKey);
    final employeeId = await _storage.read(key: _employeeIdKey);
    if (clientId == null || clientSecret == null || employeeId == null) return null;
    return PersonioCredentials(clientId: clientId, clientSecret: clientSecret, employeeId: employeeId);
  }

  @override
  Future<void> write(PersonioCredentials credentials) async {
    await _storage.write(key: _clientIdKey, value: credentials.clientId);
    await _storage.write(key: _clientSecretKey, value: credentials.clientSecret);
    await _storage.write(key: _employeeIdKey, value: credentials.employeeId);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _clientIdKey);
    await _storage.delete(key: _clientSecretKey);
    await _storage.delete(key: _employeeIdKey);
  }
}
```

- [ ] **Step 3: Create the client interface**

Create `lib/features/personio/personio_client.dart`:

```dart
/// Raised for any non-2xx Personio response, or a response Personio couldn't
/// parse. Carries a caller-safe message (no tokens, no full response bodies)
/// suitable for surfacing in the UI.
class PersonioApiException implements Exception {
  PersonioApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the Personio v2 API to push attendance periods. Implementations
/// must throw [PersonioApiException] on failure -- callers rely on that to
/// decide whether a push succeeded.
abstract class PersonioClient {
  /// Returns true if the configured credentials can authenticate against
  /// Personio, false otherwise. Never throws for an auth failure -- only for
  /// transport-level errors.
  Future<bool> testConnection();

  /// Creates a WORK attendance period and returns its Personio-assigned id.
  Future<String> createAttendance({
    required DateTime start,
    required DateTime end,
    String? comment,
  });

  Future<void> updateAttendance({
    required String periodId,
    required DateTime start,
    required DateTime end,
    String? comment,
  });

  /// Deleting a period that's already gone (404) is treated as success --
  /// the end state the caller wants is "no period", which already holds.
  Future<void> deleteAttendance({required String periodId});
}
```

- [ ] **Step 4: Write the failing client test**

Create `test/features/personio/http_personio_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/personio/http_personio_client.dart';
import 'package:hickory/features/personio/personio_client.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const credentials = PersonioCredentials(
    clientId: 'client-123',
    clientSecret: 'secret-456',
    employeeId: '789',
  );

  http.Response tokenResponse({int expiresIn = 3600}) => http.Response(
        jsonEncode({'access_token': 'token-abc', 'token_type': 'Bearer', 'expires_in': expiresIn}),
        200,
      );

  test('testConnection returns true when a token can be obtained', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v2/auth/token');
        return tokenResponse();
      }),
    );

    expect(await client.testConnection(), isTrue);
  });

  test('testConnection returns false when authentication fails', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('{}', 400)),
    );

    expect(await client.testConnection(), isFalse);
  });

  test('createAttendance obtains a token, then posts the expected body', () async {
    late Map<String, dynamic> sentBody;
    var tokenRequests = 0;
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') {
          tokenRequests++;
          expect(request.headers['Content-Type'], contains('application/x-www-form-urlencoded'));
          return tokenResponse();
        }
        expect(request.method, 'POST');
        expect(request.url.path, '/v2/attendance-periods');
        expect(request.url.queryParameters['skip_approval'], 'true');
        expect(request.headers['Authorization'], 'Bearer token-abc');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'period-1'}), 201);
      }),
    );

    final id = await client.createAttendance(
      start: DateTime.utc(2026, 7, 7, 9),
      end: DateTime.utc(2026, 7, 7, 10),
      comment: 'Design review',
    );

    expect(id, 'period-1');
    expect(tokenRequests, 1);
    expect(sentBody['person'], {'id': '789'});
    expect(sentBody['type'], 'WORK');
    expect(sentBody['comment'], 'Design review');
  });

  test('createAttendance throws PersonioApiException on a non-201 response', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        return http.Response('bad request', 400);
      }),
    );

    expect(
      () => client.createAttendance(
        start: DateTime.utc(2026, 7, 7, 9),
        end: DateTime.utc(2026, 7, 7, 10),
      ),
      throwsA(isA<PersonioApiException>()),
    );
  });

  test('a cached token is reused across multiple calls instead of re-authenticating', () async {
    var tokenRequests = 0;
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') {
          tokenRequests++;
          return tokenResponse();
        }
        return http.Response(jsonEncode({'id': 'period-1'}), 201);
      }),
    );

    await client.createAttendance(start: DateTime.utc(2026, 7, 7, 9), end: DateTime.utc(2026, 7, 7, 10));
    await client.createAttendance(start: DateTime.utc(2026, 7, 8, 9), end: DateTime.utc(2026, 7, 8, 10));

    expect(tokenRequests, 1);
  });

  test('a token whose expiry falls within the safety margin is refreshed', () async {
    var tokenRequests = 0;
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') {
          tokenRequests++;
          // expiresIn (1s) is smaller than the client's safety margin, so
          // the cached token is already considered unsafe the moment it's
          // stored -- the very next call must re-authenticate.
          return tokenResponse(expiresIn: 1);
        }
        return http.Response(jsonEncode({'id': 'period-1'}), 201);
      }),
    );

    await client.createAttendance(start: DateTime.utc(2026, 7, 7, 9), end: DateTime.utc(2026, 7, 7, 10));
    await client.createAttendance(start: DateTime.utc(2026, 7, 8, 9), end: DateTime.utc(2026, 7, 8, 10));

    expect(tokenRequests, 2);
  });

  test('updateAttendance patches the period id path', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v2/attendance-periods/period-1');
        return http.Response('{}', 200);
      }),
    );

    await client.updateAttendance(
      periodId: 'period-1',
      start: DateTime.utc(2026, 7, 7, 9),
      end: DateTime.utc(2026, 7, 7, 10),
    );
  });

  test('deleteAttendance treats 404 as success', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        expect(request.method, 'DELETE');
        return http.Response('', 404);
      }),
    );

    await client.deleteAttendance(periodId: 'period-1');
  });

  test('deleteAttendance throws on other error codes', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        return http.Response('', 500);
      }),
    );

    expect(
      () => client.deleteAttendance(periodId: 'period-1'),
      throwsA(isA<PersonioApiException>()),
    );
  });
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `flutter test test/features/personio/http_personio_client_test.dart`
Expected: FAIL — `HttpPersonioClient` doesn't exist yet.

- [ ] **Step 6: Implement `HttpPersonioClient`**

Create `lib/features/personio/http_personio_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'personio_client.dart';
import 'personio_credentials_store.dart';

/// A cached OAuth2 access token plus the UTC instant it stops being safe to
/// use (see [HttpPersonioClient._safetyMargin] for why the raw expiry isn't
/// used verbatim).
class _CachedToken {
  const _CachedToken({required this.accessToken, required this.safeUntil});

  final String accessToken;
  final DateTime safeUntil;
}

class HttpPersonioClient implements PersonioClient {
  HttpPersonioClient({required PersonioCredentials credentials, http.Client? httpClient})
    : _credentials = credentials,
      _httpClient = httpClient ?? http.Client();

  static const _baseUrl = 'https://api.personio.de';

  /// Re-authenticate this long before actual token expiry so a token that's
  /// valid when checked doesn't expire mid-request.
  static const _safetyMargin = Duration(seconds: 30);

  final PersonioCredentials _credentials;
  final http.Client _httpClient;
  _CachedToken? _cachedToken;

  @override
  Future<bool> testConnection() async {
    try {
      await _accessToken();
      return true;
    } on PersonioApiException {
      return false;
    }
  }

  @override
  Future<String> createAttendance({
    required DateTime start,
    required DateTime end,
    String? comment,
  }) async {
    final response = await _authorizedRequest(
      (headers) => _httpClient.post(
        Uri.parse('$_baseUrl/v2/attendance-periods?skip_approval=true'),
        headers: headers,
        body: jsonEncode(_attendanceBody(start: start, end: end, comment: comment)),
      ),
    );
    if (response.statusCode != 201) {
      throw PersonioApiException(
        'Failed to create attendance period (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['id'] as String;
  }

  @override
  Future<void> updateAttendance({
    required String periodId,
    required DateTime start,
    required DateTime end,
    String? comment,
  }) async {
    final response = await _authorizedRequest(
      (headers) => _httpClient.patch(
        Uri.parse('$_baseUrl/v2/attendance-periods/$periodId?skip_approval=true'),
        headers: headers,
        body: jsonEncode(_attendanceBody(start: start, end: end, comment: comment)),
      ),
    );
    if (response.statusCode != 200) {
      throw PersonioApiException(
        'Failed to update attendance period $periodId (HTTP ${response.statusCode}).',
      );
    }
  }

  @override
  Future<void> deleteAttendance({required String periodId}) async {
    final response = await _authorizedRequest(
      (headers) => _httpClient.delete(
        Uri.parse('$_baseUrl/v2/attendance-periods/$periodId'),
        headers: headers,
      ),
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw PersonioApiException(
        'Failed to delete attendance period $periodId (HTTP ${response.statusCode}).',
      );
    }
  }

  Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    final token = await _accessToken();
    return send({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });
  }

  Future<String> _accessToken() async {
    final cached = _cachedToken;
    if (cached != null && DateTime.now().toUtc().isBefore(cached.safeUntil)) {
      return cached.accessToken;
    }
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/v2/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': _credentials.clientId,
        'client_secret': _credentials.clientSecret,
      },
    );
    if (response.statusCode != 200) {
      throw PersonioApiException('Personio authentication failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = decoded['access_token'] as String;
    final expiresIn = (decoded['expires_in'] as num).toInt();
    final token = _CachedToken(
      accessToken: accessToken,
      safeUntil: DateTime.now().toUtc().add(Duration(seconds: expiresIn) - _safetyMargin),
    );
    _cachedToken = token;
    return token.accessToken;
  }

  Map<String, dynamic> _attendanceBody({
    required DateTime start,
    required DateTime end,
    String? comment,
  }) {
    return {
      'person': {'id': _credentials.employeeId},
      'type': 'WORK',
      'start': {'date_time': start.toUtc().toIso8601String()},
      'end': {'date_time': end.toUtc().toIso8601String()},
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    };
  }
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/features/personio/http_personio_client_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/features/personio/personio_credentials_store.dart lib/features/personio/secure_personio_credentials_store.dart lib/features/personio/personio_client.dart lib/features/personio/http_personio_client.dart test/features/personio/http_personio_client_test.dart
git commit -m "feat(personio): add credentials store and API client"
```

---

### Task 3: `SyncedWrites` write-through methods and `deleteEntry` integration

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `test/data/sync_round_trip_test.dart`
- Test: `test/data/synced_writes_personio_test.dart`

**Interfaces:**
- Consumes: `PersonioAttendancesDao` (Task 1), `EntityTypes.personioAttendance`
  (Task 1).
- Produces: `SyncedWrites.upsertPersonioAttendanceState(PersonioAttendanceRow row)`
  → `Future<void>`; `SyncedWrites.deletePersonioAttendanceState(String
  timeEntryId)` → `Future<void>`. `SyncedWrites.deleteEntry` additionally
  reconciles any `PersonioAttendances` tracking row for the deleted entry (same
  two-branch shape as its existing Jira handling).

- [ ] **Step 1: Write the failing test**

Create `test/data/synced_writes_personio_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_personio_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('deleteEntry marks a pushed attendance pendingDelete instead of removing it', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: 'period-1',
        status: PersonioAttendanceStatus.synced,
        lastError: null,
        syncedAt: DateTime.utc(2026, 7, 7, 10),
      ),
    );

    await writes.deleteEntry(entry.id);

    final remainingEntry =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    expect(remainingEntry, isNull);

    final attendance = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(attendance, isNotNull);
    expect(attendance!.status, PersonioAttendanceStatus.pendingDelete);
  });

  test('deleteEntry removes the tracking row outright if it was never pushed', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: null,
        status: PersonioAttendanceStatus.error,
        lastError: 'network error',
        syncedAt: null,
      ),
    );

    await writes.deleteEntry(entry.id);

    expect(await db.personioAttendancesDao.getForEntry(entry.id), isNull);
  });

  test('deleteEntry with no Personio tracking row at all still deletes the entry', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );

    await writes.deleteEntry(entry.id);

    final remainingEntry =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    expect(remainingEntry, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/synced_writes_personio_test.dart`
Expected: FAIL — `upsertPersonioAttendanceState` is not defined on `SyncedWrites`.

- [ ] **Step 3: Implement the SyncedWrites methods and deleteEntry integration**

Edit `lib/data/sync/synced_writes.dart`. Find:

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

Replace it with:

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

  /// Writes the given Personio attendance sync-tracking row and logs it, so
  /// the state (e.g. "this entry now has a Personio attendance period")
  /// propagates to the user's other devices the same way every other entity
  /// does.
  Future<void> upsertPersonioAttendanceState(PersonioAttendanceRow row) async {
    await db.personioAttendancesDao.upsert(row.toCompanion(true));
    await logWriter.appendEvent(
      entityType: EntityTypes.personioAttendance,
      entityId: row.id,
      op: EventOp.update,
      payload: row.toJson(),
    );
  }

  /// Removes a Personio attendance sync-tracking row (used once a pending
  /// delete has been pushed to Personio, or when a row was never pushed and
  /// no longer needs tracking) and logs the tombstone.
  Future<void> deletePersonioAttendanceState(String timeEntryId) async {
    await db.personioAttendancesDao.deleteForEntry(timeEntryId);
    await logWriter.appendEvent(
      entityType: EntityTypes.personioAttendance,
      entityId: timeEntryId,
      op: EventOp.delete,
      payload: null,
    );
  }
```

Find:

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

Replace it with:

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
    final attendance = await db.personioAttendancesDao.getForEntry(id);
    if (attendance != null) {
      if (attendance.personioAttendanceId == null) {
        await deletePersonioAttendanceState(id);
      } else {
        await upsertPersonioAttendanceState(
          attendance.copyWith(status: PersonioAttendanceStatus.pendingDelete),
        );
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

Add the import this needs. Find (top of file):

```dart
import 'package:drift/drift.dart' show Value;
import 'package:sync_engine/sync_engine.dart';
import 'package:uuid/uuid.dart';

import '../drift/database.dart';
import '../drift/tables/app_settings_table.dart' show appSettingsRowId;
import '../drift/tables/jira_worklogs_table.dart' show JiraWorklogStatus;
import 'entity_types.dart';
import 'sync_log_writer.dart';
```

Replace it with:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:sync_engine/sync_engine.dart';
import 'package:uuid/uuid.dart';

import '../drift/database.dart';
import '../drift/tables/app_settings_table.dart' show appSettingsRowId;
import '../drift/tables/jira_worklogs_table.dart' show JiraWorklogStatus;
import '../drift/tables/personio_attendances_table.dart' show PersonioAttendanceStatus;
import 'entity_types.dart';
import 'sync_log_writer.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/synced_writes_personio_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Add the sync round-trip case**

Edit `test/data/sync_round_trip_test.dart`. Find:

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

Replace it with:

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

  test(
    'a personio attendance tracking row syncs to a second device, including a later update',
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
      );
      await writerWrites.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: 'period-1',
          status: PersonioAttendanceStatus.synced,
          lastError: null,
          syncedAt: DateTime.utc(2026, 7, 7, 10),
        ),
      );

      final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(readerDb.close);
      final ingestor = SyncIngestor(db: readerDb, syncRoot: syncRoot);
      await ingestor.syncNow();

      final attendances = await readerDb.personioAttendancesDao.getAll();
      expect(attendances, hasLength(1));
      expect(attendances.single.personioAttendanceId, 'period-1');
      expect(attendances.single.status, PersonioAttendanceStatus.synced);

      // Same correctness property as the Jira worklog case above: a second
      // device only knows an entry was already pushed if the tracking row
      // itself synced.
      await writerWrites.deletePersonioAttendanceState(entry.id);
      await ingestor.syncNow();

      expect(await readerDb.personioAttendancesDao.getAll(), isEmpty);
    },
  );
```

Add the import this needs. Find:

```dart
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
```

Replace it with:

```dart
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/data/sync_round_trip_test.dart`
Expected: PASS (all cases, including the two new/touched ones).

- [ ] **Step 7: Commit**

```bash
git add lib/data/sync/synced_writes.dart test/data/synced_writes_personio_test.dart test/data/sync_round_trip_test.dart
git commit -m "feat(sync): add Personio attendance write-through and deleteEntry handling"
```

---

### Task 4: `PersonioSyncService`

**Files:**
- Create: `lib/features/personio/personio_sync_service.dart`
- Test: `test/features/personio/personio_sync_service_test.dart`

**Interfaces:**
- Consumes: `PersonioAttendancesDao.getAll()` (Task 1), `SyncedWrites.
  upsertPersonioAttendanceState`/`deletePersonioAttendanceState` (Task 3),
  `PersonioClient.createAttendance`/`updateAttendance`/`deleteAttendance` (Task 2),
  `TimeEntriesDao.getAllEntries()` (existing).
- Produces: `PersonioSyncResult(created, updated, deleted, failed)` (with a `total`
  getter). `PersonioSyncService({required db, required client, required writes})`
  with `Future<PersonioSyncResult> pushRange({required DateTime from, required
  DateTime to})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/personio/personio_sync_service_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/personio/personio_client.dart';
import 'package:hickory/features/personio/personio_sync_service.dart';
import 'package:mocktail/mocktail.dart';

class MockPersonioClient extends Mock implements PersonioClient {}

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;
  late MockPersonioClient client;
  late PersonioSyncService service;

  final from = DateTime.utc(2026, 7, 1);
  final to = DateTime.utc(2026, 7, 31);

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026, 7, 7));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_personio_sync_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
    client = MockPersonioClient();
    service = PersonioSyncService(db: db, client: client, writes: writes);
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('creates an attendance for a finished entry in range with no tracking row yet', () async {
    when(
      () => client.createAttendance(
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async => 'period-1');

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      description: 'Design review',
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.created, 1);
    final attendance = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(attendance!.personioAttendanceId, 'period-1');
    verify(
      () => client.createAttendance(start: entry.startAt, end: entry.endAt!, comment: 'Design review'),
    ).called(1);
  });

  test('entries outside the selected range are skipped', () async {
    await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 8, 7, 9),
      endAt: DateTime.utc(2026, 8, 7, 10),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.total, 0);
    verifyNever(
      () => client.createAttendance(
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    );
  });

  test('running (unfinished) entries are skipped', () async {
    await writes.startEntry(deviceId: 'dev_a');

    final result = await service.pushRange(from: from, to: to);

    expect(result.total, 0);
  });

  test('updates the attendance when the entry changed since the last sync', () async {
    when(
      () => client.updateAttendance(
        periodId: any(named: 'periodId'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async {});

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: 'period-1',
        status: PersonioAttendanceStatus.synced,
        lastError: null,
        syncedAt: DateTime.utc(2020),
      ),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.updated, 1);
    verify(
      () => client.updateAttendance(
        periodId: 'period-1',
        start: entry.startAt,
        end: entry.endAt!,
        comment: any(named: 'comment'),
      ),
    ).called(1);
  });

  test('an up-to-date attendance is skipped', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: 'period-1',
        status: PersonioAttendanceStatus.synced,
        lastError: null,
        syncedAt: DateTime.utc(2027),
      ),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.total, 0);
  });

  test(
    'deletes the remote attendance and the tracking row for a pendingDelete entry, regardless of range',
    () async {
      when(() => client.deleteAttendance(periodId: 'period-1')).thenAnswer((_) async {});

      final entry = await writes.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 1, 1, 9),
        endAt: DateTime.utc(2026, 1, 1, 10),
      );
      await writes.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: 'period-1',
          status: PersonioAttendanceStatus.pendingDelete,
          lastError: null,
          syncedAt: null,
        ),
      );

      // entry.startAt (January) is outside [from, to] (July) -- the delete
      // must still be reconciled, proving pendingDelete isn't date-filtered.
      final result = await service.pushRange(from: from, to: to);

      expect(result.deleted, 1);
      expect(await db.personioAttendancesDao.getForEntry(entry.id), isNull);
    },
  );

  test('a failed create is recorded with status error and counted as failed', () async {
    when(
      () => client.createAttendance(
        start: any(named: 'start'),
        end: any(named: 'end'),
        comment: any(named: 'comment'),
      ),
    ).thenThrow(PersonioApiException('boom'));

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );

    final result = await service.pushRange(from: from, to: to);

    expect(result.failed, 1);
    final attendance = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(attendance!.status, PersonioAttendanceStatus.error);
    expect(attendance.lastError, contains('boom'));
  });

  test('a failed pendingDelete stays pendingDelete and is retried on the next push', () async {
    when(
      () => client.deleteAttendance(periodId: 'period-1'),
    ).thenThrow(PersonioApiException('unreachable'));

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
    );
    await writes.upsertPersonioAttendanceState(
      PersonioAttendanceRow(
        id: entry.id,
        personioAttendanceId: 'period-1',
        status: PersonioAttendanceStatus.pendingDelete,
        lastError: null,
        syncedAt: null,
      ),
    );

    final firstResult = await service.pushRange(from: from, to: to);

    expect(firstResult.failed, 1);
    final afterFailure = await db.personioAttendancesDao.getForEntry(entry.id);
    expect(afterFailure!.status, PersonioAttendanceStatus.pendingDelete);

    when(() => client.deleteAttendance(periodId: 'period-1')).thenAnswer((_) async {});

    final secondResult = await service.pushRange(from: from, to: to);

    expect(secondResult.deleted, 1);
    expect(await db.personioAttendancesDao.getForEntry(entry.id), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/personio/personio_sync_service_test.dart`
Expected: FAIL — `PersonioSyncService` doesn't exist yet.

- [ ] **Step 3: Implement `PersonioSyncService`**

Create `lib/features/personio/personio_sync_service.dart`:

```dart
import 'package:drift/drift.dart' show Value;

import '../../data/drift/database.dart';
import '../../data/drift/tables/personio_attendances_table.dart';
import '../../data/sync/synced_writes.dart';
import 'personio_client.dart';

/// Outcome of one [PersonioSyncService.pushRange] run, for display in the UI.
class PersonioSyncResult {
  const PersonioSyncResult({
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

/// Pushes finished time entries to Personio as WORK attendance periods.
/// Unlike JiraSyncService, every finished entry in the caller-selected date
/// range is a candidate (no per-entry opt-in field), and pending deletes are
/// always reconciled regardless of the selected range -- see
/// docs/superpowers/specs/2026-08-05-personio-sync-design.md.
class PersonioSyncService {
  PersonioSyncService({required this.db, required this.client, required this.writes});

  final AppDatabase db;
  final PersonioClient client;
  final SyncedWrites writes;

  Future<PersonioSyncResult> pushRange({required DateTime from, required DateTime to}) async {
    final attendancesByEntryId = {
      for (final a in await db.personioAttendancesDao.getAll()) a.id: a,
    };
    final counts = <_Outcome, int>{};

    for (final attendance in attendancesByEntryId.values) {
      if (attendance.status != PersonioAttendanceStatus.pendingDelete) continue;
      final outcome = await _reconcilePendingDelete(attendance);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    final entries = await db.timeEntriesDao.getAllEntries();
    for (final entry in entries) {
      if (entry.endAt == null) continue;
      if (!_isInRange(entry.startAt, from: from, to: to)) continue;
      final attendance = attendancesByEntryId[entry.id];
      if (attendance?.status == PersonioAttendanceStatus.pendingDelete) continue;
      final outcome = await _reconcileEntry(entry, attendance);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    return PersonioSyncResult(
      created: counts[_Outcome.created] ?? 0,
      updated: counts[_Outcome.updated] ?? 0,
      deleted: counts[_Outcome.deleted] ?? 0,
      failed: counts[_Outcome.failed] ?? 0,
    );
  }

  /// [from]/[to] are inclusive local calendar days; [entryStart] is compared
  /// by its local calendar date only, ignoring time-of-day.
  bool _isInRange(DateTime entryStart, {required DateTime from, required DateTime to}) {
    final local = entryStart.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return !date.isBefore(fromDate) && !date.isAfter(toDate);
  }

  String _safeErrorMessage(Object error) =>
      error is PersonioApiException ? error.message : 'Network or connection error';

  Future<_Outcome> _reconcilePendingDelete(PersonioAttendanceRow attendance) async {
    try {
      if (attendance.personioAttendanceId != null) {
        await client.deleteAttendance(periodId: attendance.personioAttendanceId!);
      }
      await writes.deletePersonioAttendanceState(attendance.id);
      return _Outcome.deleted;
    } catch (e) {
      await writes.upsertPersonioAttendanceState(
        attendance.copyWith(lastError: Value(_safeErrorMessage(e))),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _reconcileEntry(TimeEntry entry, PersonioAttendanceRow? attendance) async {
    if (attendance == null) {
      return _pushCreate(entry);
    }
    final needsUpdate = attendance.syncedAt == null || entry.updatedAt.isAfter(attendance.syncedAt!);
    if (!needsUpdate) return _Outcome.skipped;
    if (attendance.personioAttendanceId == null) {
      return _pushCreate(entry);
    }
    return _pushUpdate(entry, attendance);
  }

  Future<_Outcome> _pushCreate(TimeEntry entry) async {
    try {
      final periodId = await client.createAttendance(
        start: entry.startAt,
        end: entry.endAt!,
        comment: entry.description,
      );
      await writes.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: periodId,
          status: PersonioAttendanceStatus.synced,
          lastError: null,
          syncedAt: DateTime.now().toUtc(),
        ),
      );
      return _Outcome.created;
    } catch (e) {
      await writes.upsertPersonioAttendanceState(
        PersonioAttendanceRow(
          id: entry.id,
          personioAttendanceId: null,
          status: PersonioAttendanceStatus.error,
          lastError: _safeErrorMessage(e),
          syncedAt: null,
        ),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _pushUpdate(TimeEntry entry, PersonioAttendanceRow attendance) async {
    try {
      await client.updateAttendance(
        periodId: attendance.personioAttendanceId!,
        start: entry.startAt,
        end: entry.endAt!,
        comment: entry.description,
      );
      await writes.upsertPersonioAttendanceState(
        attendance.copyWith(
          status: PersonioAttendanceStatus.synced,
          syncedAt: Value(DateTime.now().toUtc()),
          lastError: const Value(null),
        ),
      );
      return _Outcome.updated;
    } catch (e) {
      await writes.upsertPersonioAttendanceState(
        attendance.copyWith(
          status: PersonioAttendanceStatus.error,
          lastError: Value(_safeErrorMessage(e)),
        ),
      );
      return _Outcome.failed;
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/personio/personio_sync_service_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/personio/personio_sync_service.dart test/features/personio/personio_sync_service_test.dart
git commit -m "feat(personio): add PersonioSyncService date-ranged push reconciliation"
```

---

### Task 5: Localization strings

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`,
  `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Generated (via `flutter gen-l10n`, not hand-edited): `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `AppLocalizations` getters `syncPersonioSectionTitle`,
  `syncPersonioClientIdLabel`, `syncPersonioClientSecretLabel`,
  `syncPersonioEmployeeIdLabel`, `syncPersonioSaveCredentialsButton`,
  `syncPersonioCredentialsSaved`, `syncPersonioTestConnectionButton`,
  `syncPersonioTestConnectionSuccess`, `syncPersonioTestConnectionFailure`,
  `syncPersonioNotConfigured`, `syncPersonioInvalidCredentials`,
  `syncPersonioUnexpectedError`, `syncPersonioFromLabel`, `syncPersonioToLabel`,
  `syncPersonioPushButton`, and `syncPersonioPushResult(int created, int updated,
  int deleted, int failed)` — consumed by Task 6.

- [ ] **Step 1: Add the new keys to all 6 ARB files**

Edit `lib/l10n/app_de.arb`. Find:

```json
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

Replace it with:

```json
  "syncJiraSyncResult": "{created} erstellt, {updated} aktualisiert, {deleted} gelöscht, {failed} fehlgeschlagen.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
  "syncPersonioSectionTitle": "Personio-Integration",
  "syncPersonioClientIdLabel": "Client ID",
  "syncPersonioClientSecretLabel": "Client Secret",
  "syncPersonioEmployeeIdLabel": "Mitarbeiter-ID",
  "syncPersonioSaveCredentialsButton": "Zugangsdaten speichern",
  "syncPersonioCredentialsSaved": "Zugangsdaten gespeichert.",
  "syncPersonioTestConnectionButton": "Verbindung testen",
  "syncPersonioTestConnectionSuccess": "Verbindung erfolgreich.",
  "syncPersonioTestConnectionFailure": "Verbindung fehlgeschlagen. Bitte Zugangsdaten prüfen.",
  "syncPersonioNotConfigured": "Personio ist noch nicht konfiguriert.",
  "syncPersonioInvalidCredentials": "Bitte gib Client ID, Client Secret und Mitarbeiter-ID an.",
  "syncPersonioUnexpectedError": "Es ist ein Fehler aufgetreten. Bitte versuche es erneut.",
  "syncPersonioFromLabel": "Von",
  "syncPersonioToLabel": "Bis",
  "syncPersonioPushButton": "Zeiten nach Personio pushen",
  "syncPersonioPushResult": "{created} erstellt, {updated} aktualisiert, {deleted} gelöscht, {failed} fehlgeschlagen.",
  "@syncPersonioPushResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

Edit `lib/l10n/app_en.arb`. Find:

```json
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

Replace it with:

```json
  "syncJiraSyncResult": "{created} created, {updated} updated, {deleted} deleted, {failed} failed.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
  "syncPersonioSectionTitle": "Personio Integration",
  "syncPersonioClientIdLabel": "Client ID",
  "syncPersonioClientSecretLabel": "Client Secret",
  "syncPersonioEmployeeIdLabel": "Employee ID",
  "syncPersonioSaveCredentialsButton": "Save credentials",
  "syncPersonioCredentialsSaved": "Credentials saved.",
  "syncPersonioTestConnectionButton": "Test connection",
  "syncPersonioTestConnectionSuccess": "Connection successful.",
  "syncPersonioTestConnectionFailure": "Connection failed. Please check your credentials.",
  "syncPersonioNotConfigured": "Personio isn't configured yet.",
  "syncPersonioInvalidCredentials": "Please enter a Client ID, Client Secret, and Employee ID.",
  "syncPersonioUnexpectedError": "Something went wrong. Please try again.",
  "syncPersonioFromLabel": "From",
  "syncPersonioToLabel": "To",
  "syncPersonioPushButton": "Push to Personio",
  "syncPersonioPushResult": "{created} created, {updated} updated, {deleted} deleted, {failed} failed.",
  "@syncPersonioPushResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

Edit `lib/l10n/app_es.arb`. Find:

```json
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

Replace it with:

```json
  "syncJiraSyncResult": "{created} creadas, {updated} actualizadas, {deleted} eliminadas, {failed} fallidas.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
  "syncPersonioSectionTitle": "Integración con Personio",
  "syncPersonioClientIdLabel": "Client ID",
  "syncPersonioClientSecretLabel": "Client Secret",
  "syncPersonioEmployeeIdLabel": "ID de empleado",
  "syncPersonioSaveCredentialsButton": "Guardar credenciales",
  "syncPersonioCredentialsSaved": "Credenciales guardadas.",
  "syncPersonioTestConnectionButton": "Probar conexión",
  "syncPersonioTestConnectionSuccess": "Conexión exitosa.",
  "syncPersonioTestConnectionFailure": "Conexión fallida. Por favor, verifica tus credenciales.",
  "syncPersonioNotConfigured": "Personio aún no está configurado.",
  "syncPersonioInvalidCredentials": "Introduce el Client ID, el Client Secret y el ID de empleado.",
  "syncPersonioUnexpectedError": "Algo salió mal. Por favor, inténtalo de nuevo.",
  "syncPersonioFromLabel": "Desde",
  "syncPersonioToLabel": "Hasta",
  "syncPersonioPushButton": "Enviar a Personio",
  "syncPersonioPushResult": "{created} creado(s), {updated} actualizado(s), {deleted} eliminado(s), {failed} fallido(s).",
  "@syncPersonioPushResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

Edit `lib/l10n/app_fr.arb`. Find:

```json
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

Replace it with:

```json
  "syncJiraSyncResult": "{created} créées, {updated} mises à jour, {deleted} supprimées, {failed} échouées.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
  "syncPersonioSectionTitle": "Intégration Personio",
  "syncPersonioClientIdLabel": "Client ID",
  "syncPersonioClientSecretLabel": "Client Secret",
  "syncPersonioEmployeeIdLabel": "ID employé",
  "syncPersonioSaveCredentialsButton": "Enregistrer les identifiants",
  "syncPersonioCredentialsSaved": "Identifiants enregistrés.",
  "syncPersonioTestConnectionButton": "Tester la connexion",
  "syncPersonioTestConnectionSuccess": "Connexion réussie.",
  "syncPersonioTestConnectionFailure": "Échec de la connexion. Veuillez vérifier vos identifiants.",
  "syncPersonioNotConfigured": "Personio n'est pas encore configuré.",
  "syncPersonioInvalidCredentials": "Veuillez saisir le Client ID, le Client Secret et l'ID employé.",
  "syncPersonioUnexpectedError": "Une erreur s'est produite. Veuillez réessayer.",
  "syncPersonioFromLabel": "Du",
  "syncPersonioToLabel": "Au",
  "syncPersonioPushButton": "Envoyer vers Personio",
  "syncPersonioPushResult": "{created} créé(s), {updated} mis à jour, {deleted} supprimé(s), {failed} échoué(s).",
  "@syncPersonioPushResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

Edit `lib/l10n/app_it.arb`. Find:

```json
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

Replace it with:

```json
  "syncJiraSyncResult": "{created} create, {updated} aggiornate, {deleted} eliminate, {failed} non riuscite.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
  "syncPersonioSectionTitle": "Integrazione Personio",
  "syncPersonioClientIdLabel": "Client ID",
  "syncPersonioClientSecretLabel": "Client Secret",
  "syncPersonioEmployeeIdLabel": "ID dipendente",
  "syncPersonioSaveCredentialsButton": "Salva credenziali",
  "syncPersonioCredentialsSaved": "Credenziali salvate.",
  "syncPersonioTestConnectionButton": "Verifica connessione",
  "syncPersonioTestConnectionSuccess": "Connessione riuscita.",
  "syncPersonioTestConnectionFailure": "Connessione fallita. Controlla le credenziali.",
  "syncPersonioNotConfigured": "Personio non è ancora configurato.",
  "syncPersonioInvalidCredentials": "Inserisci Client ID, Client Secret e ID dipendente.",
  "syncPersonioUnexpectedError": "Si è verificato un errore. Riprova.",
  "syncPersonioFromLabel": "Da",
  "syncPersonioToLabel": "A",
  "syncPersonioPushButton": "Invia a Personio",
  "syncPersonioPushResult": "{created} creati, {updated} aggiornati, {deleted} eliminati, {failed} falliti.",
  "@syncPersonioPushResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

Edit `lib/l10n/app_nl.arb`. Find:

```json
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

Replace it with:

```json
  "syncJiraSyncResult": "{created} aangemaakt, {updated} bijgewerkt, {deleted} verwijderd, {failed} mislukt.",
  "@syncJiraSyncResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
  "syncPersonioSectionTitle": "Personio-integratie",
  "syncPersonioClientIdLabel": "Client ID",
  "syncPersonioClientSecretLabel": "Client Secret",
  "syncPersonioEmployeeIdLabel": "Werknemers-ID",
  "syncPersonioSaveCredentialsButton": "Gegevens opslaan",
  "syncPersonioCredentialsSaved": "Gegevens opgeslagen.",
  "syncPersonioTestConnectionButton": "Verbinding testen",
  "syncPersonioTestConnectionSuccess": "Verbinding gelukt.",
  "syncPersonioTestConnectionFailure": "Verbinding mislukt. Controleer je gegevens.",
  "syncPersonioNotConfigured": "Personio is nog niet geconfigureerd.",
  "syncPersonioInvalidCredentials": "Voer Client ID, Client Secret en werknemers-ID in.",
  "syncPersonioUnexpectedError": "Er is iets misgegaan. Probeer het opnieuw.",
  "syncPersonioFromLabel": "Van",
  "syncPersonioToLabel": "Tot",
  "syncPersonioPushButton": "Naar Personio pushen",
  "syncPersonioPushResult": "{created} aangemaakt, {updated} bijgewerkt, {deleted} verwijderd, {failed} mislukt.",
  "@syncPersonioPushResult": {
    "placeholders": {
      "created": { "type": "int" },
      "updated": { "type": "int" },
      "deleted": { "type": "int" },
      "failed": { "type": "int" }
    }
  },
```

- [ ] **Step 2: Verify key parity across locales**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes with no errors; `lib/l10n/app_localizations*.dart` are updated
with the 16 new getters.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart
git commit -m "feat(l10n): add Personio integration strings"
```

---

### Task 6: Riverpod providers and Sync screen UI

**Files:**
- Create: `lib/core/di/personio_providers.dart`
- Modify: `lib/features/sync/sync_screen.dart`

**Interfaces:**
- Consumes: `PersonioCredentialsStore`/`SecurePersonioCredentialsStore` (Task 2),
  `HttpPersonioClient` (Task 2), `PersonioSyncService` (Task 4),
  `PersonioAttendancesDao.latestSyncedAt()` (Task 1), all `syncPersonio*`
  `AppLocalizations` getters (Task 5).
- Produces: `personioCredentialsStoreProvider`, `personioCredentialsProvider`,
  `personioClientProvider`, `personioSyncServiceProvider`,
  `personioLatestSyncedAtProvider` — no other file depends on these (this is the
  final task).

- [ ] **Step 1: Create the providers**

Create `lib/core/di/personio_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/personio/http_personio_client.dart';
import '../../features/personio/personio_client.dart';
import '../../features/personio/personio_credentials_store.dart';
import '../../features/personio/personio_sync_service.dart';
import '../../features/personio/secure_personio_credentials_store.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

// Plain (non-generated) providers -- see jira_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final personioCredentialsStoreProvider = Provider<PersonioCredentialsStore>(
  (ref) => SecurePersonioCredentialsStore(),
);

/// The configured Personio credentials, or null if Personio hasn't been set
/// up on this device yet. Invalidate this provider after writing new
/// credentials to pick them up immediately.
final personioCredentialsProvider = FutureProvider<PersonioCredentials?>((ref) async {
  final store = ref.watch(personioCredentialsStoreProvider);
  return store.read();
});

/// The Personio API client, or null until credentials are configured.
final personioClientProvider = FutureProvider<PersonioClient?>((ref) async {
  final credentials = await ref.watch(personioCredentialsProvider.future);
  if (credentials == null) return null;
  return HttpPersonioClient(credentials: credentials);
});

/// The push reconciliation service, or null until credentials are
/// configured.
final personioSyncServiceProvider = FutureProvider<PersonioSyncService?>((ref) async {
  final client = await ref.watch(personioClientProvider.future);
  if (client == null) return null;
  final db = ref.watch(appDatabaseProvider);
  final writes = await ref.watch(syncedWritesProvider.future);
  return PersonioSyncService(db: db, client: client, writes: writes);
});

/// The latest successful push's timestamp across all tracked attendances, or
/// null if nothing has been pushed yet -- used to default the Sync screen's
/// push-range picker to "the day after the last successful push".
final personioLatestSyncedAtProvider = FutureProvider<DateTime?>((ref) {
  return ref.watch(appDatabaseProvider).personioAttendancesDao.latestSyncedAt();
});
```

- [ ] **Step 2: Wire the Sync screen**

Edit `lib/features/sync/sync_screen.dart`. Find:

```dart
// lib/features/sync/sync_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../jira/jira_credentials_store.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _statusMessage;
  final _jiraBaseUrlController = TextEditingController();
  final _jiraEmailController = TextEditingController();
  final _jiraApiTokenController = TextEditingController();
  bool _jiraBusy = false;
  String? _jiraStatusMessage;

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

  @override
  void dispose() {
    _jiraBaseUrlController.dispose();
    _jiraEmailController.dispose();
    _jiraApiTokenController.dispose();
    super.dispose();
  }
```

Replace it with:

```dart
// lib/features/sync/sync_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/personio_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../jira/jira_credentials_store.dart';
import '../personio/personio_credentials_store.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _statusMessage;
  final _jiraBaseUrlController = TextEditingController();
  final _jiraEmailController = TextEditingController();
  final _jiraApiTokenController = TextEditingController();
  bool _jiraBusy = false;
  String? _jiraStatusMessage;

  final _personioClientIdController = TextEditingController();
  final _personioClientSecretController = TextEditingController();
  final _personioEmployeeIdController = TextEditingController();
  bool _personioBusy = false;
  String? _personioStatusMessage;
  DateTime _personioFrom = DateTime.now();
  DateTime _personioTo = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadJiraCredentials();
    _loadPersonioCredentials();
    _initPersonioRange();
  }

  Future<void> _loadJiraCredentials() async {
    final credentials = await ref.read(jiraCredentialsProvider.future);
    if (!mounted || credentials == null) return;
    _jiraBaseUrlController.text = credentials.baseUrl;
    _jiraEmailController.text = credentials.email;
    _jiraApiTokenController.text = credentials.apiToken;
  }

  Future<void> _loadPersonioCredentials() async {
    final credentials = await ref.read(personioCredentialsProvider.future);
    if (!mounted || credentials == null) return;
    _personioClientIdController.text = credentials.clientId;
    _personioClientSecretController.text = credentials.clientSecret;
    _personioEmployeeIdController.text = credentials.employeeId;
  }

  /// Defaults the push range to "the day after the last successful push"
  /// through today, per the design's push-range default.
  Future<void> _initPersonioRange() async {
    final latest = await ref.read(personioLatestSyncedAtProvider.future);
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _personioFrom = latest == null
          ? DateTime(now.year, now.month, now.day)
          : DateTime(latest.year, latest.month, latest.day).add(const Duration(days: 1));
      _personioTo = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  void dispose() {
    _jiraBaseUrlController.dispose();
    _jiraEmailController.dispose();
    _jiraApiTokenController.dispose();
    _personioClientIdController.dispose();
    _personioClientSecretController.dispose();
    _personioEmployeeIdController.dispose();
    super.dispose();
  }
```

- [ ] **Step 3: Add the Personio action methods**

Edit `lib/features/sync/sync_screen.dart`. Find:

```dart
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

  @override
  Widget build(BuildContext context) {
```

Replace it with:

```dart
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

  bool _hasValidPersonioCredentialsInput() {
    return _personioClientIdController.text.trim().isNotEmpty &&
        _personioClientSecretController.text.trim().isNotEmpty &&
        _personioEmployeeIdController.text.trim().isNotEmpty;
  }

  Future<void> _savePersonioCredentials() async {
    final l10n = AppLocalizations.of(context);
    if (!_hasValidPersonioCredentialsInput()) {
      setState(() => _personioStatusMessage = l10n.syncPersonioInvalidCredentials);
      return;
    }
    setState(() {
      _personioBusy = true;
      _personioStatusMessage = null;
    });
    try {
      final store = ref.read(personioCredentialsStoreProvider);
      await store.write(
        PersonioCredentials(
          clientId: _personioClientIdController.text.trim(),
          clientSecret: _personioClientSecretController.text.trim(),
          employeeId: _personioEmployeeIdController.text.trim(),
        ),
      );
      ref.invalidate(personioCredentialsProvider);
      if (mounted) setState(() => _personioStatusMessage = l10n.syncPersonioCredentialsSaved);
    } catch (_) {
      if (mounted) setState(() => _personioStatusMessage = l10n.syncPersonioUnexpectedError);
    } finally {
      if (mounted) setState(() => _personioBusy = false);
    }
  }

  Future<void> _testPersonioConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _personioBusy = true;
      _personioStatusMessage = null;
    });
    try {
      final client = await ref.read(personioClientProvider.future);
      if (client == null) {
        if (mounted) setState(() => _personioStatusMessage = l10n.syncPersonioNotConfigured);
        return;
      }
      final ok = await client.testConnection();
      if (!mounted) return;
      setState(
        () => _personioStatusMessage = ok
            ? l10n.syncPersonioTestConnectionSuccess
            : l10n.syncPersonioTestConnectionFailure,
      );
    } catch (_) {
      // testConnection() throws for transport-level errors (e.g. a
      // malformed URL, DNS failure) -- the single most likely error right
      // after first configuring credentials, so this must not be left to
      // propagate unhandled.
      if (mounted) setState(() => _personioStatusMessage = l10n.syncPersonioTestConnectionFailure);
    } finally {
      if (mounted) setState(() => _personioBusy = false);
    }
  }

  Future<void> _pushPersonio() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _personioBusy = true;
      _personioStatusMessage = null;
    });
    try {
      final service = await ref.read(personioSyncServiceProvider.future);
      if (service == null) {
        if (mounted) setState(() => _personioStatusMessage = l10n.syncPersonioNotConfigured);
        return;
      }
      final result = await service.pushRange(from: _personioFrom, to: _personioTo);
      ref.invalidate(personioLatestSyncedAtProvider);
      if (!mounted) return;
      setState(
        () => _personioStatusMessage = l10n.syncPersonioPushResult(
          result.created,
          result.updated,
          result.deleted,
          result.failed,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _personioStatusMessage = l10n.syncPersonioUnexpectedError);
    } finally {
      if (mounted) setState(() => _personioBusy = false);
    }
  }

  Future<void> _pickPersonioFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _personioFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _personioFrom = picked);
  }

  Future<void> _pickPersonioTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _personioTo,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _personioTo = picked);
  }

  /// Plain `YYYY-MM-DD`, deliberately not the app's locale-aware date
  /// format (`core/format/date_format.dart`) -- this label is a compact
  /// picker-button caption, not user-facing report content, so pulling in
  /// the full date-format settings dependency here isn't worth it.
  String _formatPersonioDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  @override
  Widget build(BuildContext context) {
```

- [ ] **Step 4: Add the Personio card to the build method**

Edit `lib/features/sync/sync_screen.dart`. Find:

```dart
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
        ],
      ),
    );
  }
}
```

Replace it with:

```dart
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
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.syncPersonioSectionTitle, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _personioClientIdController,
                    decoration: InputDecoration(labelText: l10n.syncPersonioClientIdLabel),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _personioClientSecretController,
                    decoration: InputDecoration(labelText: l10n.syncPersonioClientSecretLabel),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _personioEmployeeIdController,
                    decoration: InputDecoration(labelText: l10n.syncPersonioEmployeeIdLabel),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: _personioBusy ? null : _savePersonioCredentials,
                        child: Text(l10n.syncPersonioSaveCredentialsButton),
                      ),
                      OutlinedButton(
                        onPressed: _personioBusy ? null : _testPersonioConnection,
                        child: Text(l10n.syncPersonioTestConnectionButton),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _personioBusy ? null : _pickPersonioFrom,
                          child: Text(
                            '${l10n.syncPersonioFromLabel}: ${_formatPersonioDate(_personioFrom)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _personioBusy ? null : _pickPersonioTo,
                          child: Text(
                            '${l10n.syncPersonioToLabel}: ${_formatPersonioDate(_personioTo)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_personioStatusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_personioStatusMessage!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _personioBusy ? null : _pushPersonio,
                    child: Text(l10n.syncPersonioPushButton),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Verify**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: PASS (all tests — this task adds no new test file per the Global
Constraints, but the full suite must still show no regressions).

- [ ] **Step 6: Commit**

```bash
git add lib/core/di/personio_providers.dart lib/features/sync/sync_screen.dart
git commit -m "feat(personio): add providers and Sync screen push UI"
```

- [ ] **Step 7: Manual verification (not automatable — note for the user)**

The exact Personio API request-body shape (`person`/`start`/`end` nesting) is
`[inferred]`, not verified against a live account (see Global Constraints). Before
relying on this feature:
1. Enter real Personio Client ID / Client Secret / Employee ID and tap "Test
   connection" — this exercises the OAuth2 token exchange against the real API.
2. Push a single, disposable time entry and check in Personio's UI whether an
   attendance period actually appears with the right start/end/comment. If it
   doesn't, or the API returns a 400/422, the field shapes in
   `HttpPersonioClient._attendanceBody` are the only thing that needs correcting —
   the rest of the pipeline (tracking, sync, UI) doesn't change.
