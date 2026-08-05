# Project Deletion & Full App Reset — Design

Date: 2026-08-05
Status: Approved for planning

## 1. Goal & Scope

Two additions to Settings' project manager and Settings screen:

1. **Hard-delete a project** (active or archived) when no `TimeEntries` row references it.
   Archiving (`ProjectsEditor`, `ProjectsDao.archiveProject`) already exists and stays the
   default removal path for projects that have history; this adds a real delete for
   projects that don't.
2. **A full local reset** ("Komplett zurücksetzen") button in Settings that returns the app
   to a fresh-install state on this device: all data, all settings, all third-party
   credentials.

Out of scope: Client (`Kunde`) hard-delete (no client-picker UI exists anywhere yet — same
gap noted in `2026-08-04-project-editing-design.md`), bulk/multi-select delete, partial
reset (data-only vs. settings-only — user chose full reset), and any reset action that
touches other devices' data in a shared sync folder (user chose device-local reset only).

## 2. Project Deletion

### 2.1 Data layer

**`lib/data/drift/daos/time_entries_dao.dart`** — new query:

```dart
Future<bool> hasEntriesForProject(String projectId) async {
  final row = await (select(timeEntries)
        ..where((t) => t.projectId.equals(projectId))
        ..limit(1))
      .getSingleOrNull();
  return row != null;
}
```

**`lib/data/drift/daos/projects_dao.dart`** — new plain delete (no guard; the business rule
lives in `SyncedWrites`, matching `deleteBreakRuleTier`'s DAO being a pure delete):

```dart
Future<void> deleteProject(String id) =>
    (delete(projects)..where((p) => p.id.equals(id))).go();
```

**`lib/data/sync/synced_writes.dart`** — new exception type and method:

```dart
/// Thrown by [SyncedWrites.deleteProject] when the project still has at
/// least one time entry pointing at it -- archiving is the removal path
/// for projects with history, deletion is only for projects with none.
class ProjectHasTimeEntriesException implements Exception {}

Future<void> deleteProject(String id) async {
  final hasEntries = await db.timeEntriesDao.hasEntriesForProject(id);
  if (hasEntries) throw ProjectHasTimeEntriesException();
  await db.projectsDao.deleteProject(id);
  await logWriter.appendEvent(
    entityType: EntityTypes.project,
    entityId: id,
    op: EventOp.delete,
    payload: null,
  );
}
```

No `SyncIngestor` changes: `_applyMaterializedEntity`'s `EntityTypes.project` case already
deletes the row when `entity.isDeleted` (confirmed in `sync_ingestor.dart`).

### 2.2 UI (`lib/features/projects/projects_editor.dart`)

- Active-project rows: add a delete `IconButton` (`Icons.delete_outline`, tooltip
  `projectsDeleteTooltip`) to the existing `Row` of trailing actions, after edit and
  archive.
- Archived-project rows: add the same delete `IconButton` after unarchive.
- `_delete(String id)` handler: shows a confirm `AlertDialog` first (same shape as
  `_ManualEntryDialog._delete` in `manual_entry_dialog.dart` — title
  `projectsDeleteConfirmTitle`, message `projectsDeleteConfirmMessage`, actions
  `commonCancel` / `commonDelete`). If confirmed, runs inside the existing `_guardedWrite`:
  calls `SyncedWrites.deleteProject`, and specifically catches
  `ProjectHasTimeEntriesException` inside the write callback (so it doesn't fall through to
  `_guardedWrite`'s generic catch) to show a dedicated snackbar
  (`projectsDeleteHasEntriesError`) instead of the generic save-error one.
- No proactive per-row "does this project have entries" query/stream — consistent with how
  every other action on this screen already surfaces failures reactively via snackbar
  rather than disabling controls ahead of time.

### 2.3 i18n

New ARB keys (all 6 locale files — `test/l10n/arb_completeness_test.dart` enforces parity):

`projectsDeleteTooltip`, `projectsDeleteConfirmTitle`, `projectsDeleteConfirmMessage`,
`projectsDeleteHasEntriesError`.

Reused as-is: `commonDelete`, `commonCancel`.

### 2.4 Testing

- `test/data/drift/time_entries_dao_test.dart`: `hasEntriesForProject` true when an entry
  references the project, false otherwise.
- `test/data/drift/projects_dao_test.dart`: `deleteProject` removes the row.
- `test/data/synced_writes_projects_test.dart`: `deleteProject` deletes + logs an
  `EventOp.delete` event when the project has no entries; throws
  `ProjectHasTimeEntriesException` and leaves the row + log untouched when it does.
- `test/features/projects/projects_editor_test.dart`: delete action present on both active
  and archived rows; confirming removes the project from the list; attempting to delete a
  project with entries shows the has-entries error snackbar and leaves the project in
  place.

## 3. Full App Reset

### 3.1 Why "wipe the local DB" isn't enough

Hickory's sync is a per-device append-only JSONL event log
(`entries/<deviceId>/*.jsonl`) under a sync root — either a user-configured shared folder,
or (if none is configured, the common single-device case) a local default root that
`sync_paths.dart#defaultSyncRoot()` always creates. `SyncIngestor.syncNow()` treats a log
file as "already known" only via a cached `(mtime, size)` row in the local `sync_file_states`
table. If a reset clears the drift DB (including that cache) but leaves the device's own log
files on disk, the very next sync pass sees every one of that device's own files as
"changed", re-ingests every event in them, and re-materializes every entity the device ever
wrote — silently undoing the reset. So a reset that stays reset must also stop the device
from re-feeding itself its own history, not just clear the DB.

### 3.2 `AppResetService` (`lib/data/reset/app_reset_service.dart`, new)

```dart
class AppResetService {
  AppResetService({
    required this.db,
    required this.deviceId,
    required this.effectiveSyncRoot,
    required this.defaultSyncRoot,
    required this.syncFolderProvider,
    required this.jiraCredentialsStore,
    required this.personioCredentialsStore,
    required this.localeStore,
  });

  final AppDatabase db;
  final String deviceId;
  final Directory effectiveSyncRoot;
  final Directory defaultSyncRoot;
  final SyncFolderProvider syncFolderProvider;
  final JiraCredentialsStore jiraCredentialsStore;
  final PersonioCredentialsStore personioCredentialsStore;
  final LocaleStore localeStore;

  Future<void> resetEverything() async {
    await db.transaction(() async {
      for (final table in db.allTables) {
        await db.delete(table).go();
      }
    });
    await _deleteDeviceLogDir(effectiveSyncRoot);
    await _deleteDeviceLogDir(defaultSyncRoot);
    await syncFolderProvider.clearPersistedFolder();
    await jiraCredentialsStore.clear();
    await personioCredentialsStore.clear();
    await localeStore.clear();
  }

  Future<void> _deleteDeviceLogDir(Directory root) async {
    final dir = deviceLogDir(root, deviceId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
```

Notes:
- Looping `db.allTables` (drift's generated list of every registered table) instead of a
  hardcoded table list — stays correct as the schema grows, no maintenance burden.
- `_deleteDeviceLogDir` runs against both `effectiveSyncRoot` (wherever the device is
  currently pointed — a configured folder, or the default root if none is configured) and
  `defaultSyncRoot` unconditionally, since the default root always exists and always holds
  this device's pre-configuration history even when a folder is configured today. If both
  resolve to the same directory the second call is a no-op (`exists()` is false the second
  time).
- Forgetting the sync folder (`clearPersistedFolder`) only removes *this device's* pointer
  to the folder and deletes only *this device's own* subdirectory inside it — nothing
  belonging to other devices in a shared folder is read, modified, or deleted. Reconnecting
  to the same folder later re-ingests its full current contents from scratch, the same way
  connecting to any folder for the first time already works today.
- Not a `SyncedWrites` method: this is deliberately local-only and bypasses the event log
  entirely (it is the thing being cleared), so it doesn't belong in the write-then-log
  wrapper.

### 3.3 Provider wiring

**`lib/core/di/reset_providers.dart`** (new):

```dart
final appResetServiceProvider = FutureProvider<AppResetService>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final deviceId = await ref.watch(deviceIdProvider.future);
  final effectiveRoot = await ref.watch(effectiveSyncRootProvider.future);
  return AppResetService(
    db: db,
    deviceId: deviceId,
    effectiveSyncRoot: effectiveRoot,
    defaultSyncRoot: await defaultSyncRoot(),
    syncFolderProvider: ref.watch(syncFolderProviderProvider),
    jiraCredentialsStore: ref.watch(jiraCredentialsStoreProvider),
    personioCredentialsStore: ref.watch(personioCredentialsStoreProvider),
    localeStore: await ref.watch(localeStoreProvider.future),
  );
});
```

**Settings call site**, after `await service.resetEverything()` completes:

```dart
ref.invalidate(configuredSyncFolderPathProvider);
ref.invalidate(jiraCredentialsProvider);
ref.invalidate(personioCredentialsProvider);
ref.invalidate(localeControllerProvider);
```

`configuredSyncFolderPathProvider`'s invalidation cascades through `effectiveSyncRootProvider`
→ `syncLogWriterProvider` / `syncIngestorProvider` / `syncedWritesProvider` /
`syncWatcherProvider` (each `ref.watch`es the one before it in `sync_providers.dart`), so the
filesystem watcher on the old folder is disposed and a fresh one starts on the (now default)
root. Every DB-backed provider (`activeProjectsProvider`, `appSettingsProvider`, break-rule
tiers, quick-add durations, entries) is already a live drift `Stream` reading from the same
`AppDatabase` instance, so those reflect the reset the moment the transaction commits — no
invalidation needed, and no app restart needed anywhere.

### 3.4 UI

New **`lib/features/settings/app_reset_section.dart`**: `AppResetSection extends
ConsumerStatefulWidget`, same structural pattern as `BreakRuleTiersEditor`/`ProjectsEditor`
(a `_busy` guard disabling the button while the reset runs).

- Title `settingsResetTitle`, description `settingsResetDescription` explaining this only
  affects this device's local data.
- A destructively-styled button (`FilledButton` with
  `backgroundColor: Theme.of(context).colorScheme.error`), label `settingsResetButton`.
- Tapping opens a confirm `AlertDialog`: title `settingsResetConfirmTitle`, message
  `settingsResetConfirmMessage` (spells out what gets deleted: projects, clients, time
  entries, settings, Jira/Personio links, the configured sync folder), actions
  `commonCancel` / `settingsResetConfirmButton` (also error-colored).
- On confirm: run `resetEverything()` + the provider invalidations above; success snackbar
  `settingsResetSuccess`; failure snackbar `settingsResetError` (generic — this is a
  best-effort local filesystem/DB operation, same error-handling shape as every other write
  in Settings).

**`lib/features/settings/settings_screen.dart`**: new `Card(child: Padding(...,
child: AppResetSection()))`, appended as the last card (after the update card), purely
additive.

### 3.5 i18n

New ARB keys (all 6 locale files): `settingsResetTitle`, `settingsResetDescription`,
`settingsResetButton`, `settingsResetConfirmTitle`, `settingsResetConfirmMessage`,
`settingsResetConfirmButton`, `settingsResetSuccess`, `settingsResetError`.

Reused as-is: `commonCancel`.

### 3.6 Testing

- `test/data/reset/app_reset_service_test.dart` (new): seed an in-memory `AppDatabase` with
  a project, a time entry, app settings, a break-rule tier, a Jira worklog row, and a
  Personio attendance row; write fake `entries/<deviceId>/*.jsonl` files under both a fake
  "effective" (configured-folder) root and a fake default root, plus a fake
  `entries/<otherDeviceId>/*.jsonl` file under the configured root. After
  `resetEverything()`: every drift table is empty; the device's own log directories are
  gone from both roots; the other device's log file is untouched on disk; fake
  `SyncFolderProvider`/`JiraCredentialsStore`/`PersonioCredentialsStore`/`LocaleStore`
  doubles each record their `clear()` call.
- `test/features/settings/app_reset_section_test.dart` (new): confirm dialog appears on
  button tap and lists the consequences; confirming invokes the reset service and shows the
  success snackbar; cancelling performs no action.

## 4. Out of Scope

Client hard-delete UI, bulk project delete, partial/selective reset, resetting or
touching other devices' data in a shared sync folder, undo/trash for either deleted
projects or a full reset.
