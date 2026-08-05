# Project Deletion & Full App Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user hard-delete a project (active or archived) once it has no time entries, and add a device-local "reset everything" button to Settings that returns the app to a fresh-install state without touching other devices' data in a shared sync folder.

**Architecture:** Project deletion follows the existing DAO → `SyncedWrites` (write + append event) → `SyncIngestor` (already handles deletes generically) pipeline used by every other entity. The full reset is deliberately *not* part of that pipeline — it's a new `AppResetService` that clears the local drift DB and this device's own sync event-log files directly, bypassing the synced-write path entirely (since the sync state is exactly what's being cleared).

**Tech Stack:** Flutter, Riverpod (mix of `@riverpod` codegen and plain top-level providers), Drift (SQLite), `flutter_secure_storage`, ARB-based i18n (`flutter gen-l10n`).

## Global Constraints

- Dart SDK per `pubspec.yaml`'s `environment.sdk` (`^3.12.2`) — don't hardcode a different version anywhere.
- German (`lib/l10n/app_de.arb`) is the l10n template; every other locale (`en`, `fr`, `es`, `it`, `nl`) must define exactly the same keys, or `test/l10n/arb_completeness_test.dart` fails.
- After editing any `.arb` file, run `flutter gen-l10n` before compiling/testing anything that uses the new getters (it regenerates `lib/l10n/app_localizations*.dart`, which are committed to the repo).
- Providers whose type touches a Drift-generated class (`AppDatabase`, `Project`, etc.) must be plain top-level `Provider`/`FutureProvider`/`StreamProvider`, not `@riverpod`-codegen — see the existing comment in `lib/core/di/sync_providers.dart` (riverpod_generator issue rrousselGit/riverpod#4323).
- Widget tests that trigger a `SyncedWrites` call (real file I/O in `SyncLogWriter`) or any other real file I/O must wrap the tap + wait in `tester.runAsync`, and poll with real `Future.delayed`, not `tester.pump` — see the header comment in `test/features/settings/break_rule_tiers_editor_test.dart`.
- Follow existing code style exactly: `final` over `var`, early returns, no added comments beyond one-line non-obvious-only notes (matches the rest of this codebase).

---

### Task 1: `TimeEntriesDao.hasEntriesForProject`

**Files:**
- Modify: `lib/data/drift/daos/time_entries_dao.dart` (end of class, after `deleteEntry`, line 150)
- Test: `test/data/drift/time_entries_dao_test.dart` (append new `test()` blocks at the end of `main()`, before the closing `}`)

**Interfaces:**
- Produces: `Future<bool> TimeEntriesDao.hasEntriesForProject(String projectId)` — `true` if at least one `TimeEntries` row has that `projectId`, `false` otherwise (including when `projectId` doesn't exist at all).

- [ ] **Step 1: Write the failing tests**

Add to `test/data/drift/time_entries_dao_test.dart`, inside `main()`, before the final `}`:

```dart
  test('hasEntriesForProject returns true when an entry references the project', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.timeEntriesDao.startEntry(deviceId: 'dev_a', projectId: project.id);

    final result = await db.timeEntriesDao.hasEntriesForProject(project.id);

    expect(result, isTrue);
  });

  test('hasEntriesForProject returns false when no entry references the project', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.timeEntriesDao.startEntry(deviceId: 'dev_a', projectId: null);

    final result = await db.timeEntriesDao.hasEntriesForProject(project.id);

    expect(result, isFalse);
  });

  test('hasEntriesForProject returns false for a project id that has no rows at all', () async {
    final result = await db.timeEntriesDao.hasEntriesForProject('missing-project-id');

    expect(result, isFalse);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/drift/time_entries_dao_test.dart`
Expected: FAIL — `The method 'hasEntriesForProject' isn't defined for the type 'TimeEntriesDao'`

- [ ] **Step 3: Implement `hasEntriesForProject`**

In `lib/data/drift/daos/time_entries_dao.dart`, add before the closing `}` of the class (after `deleteEntry`):

```dart
  /// Used by [SyncedWrites.deleteProject] to block hard-deleting a project
  /// that still has history -- archiving is the removal path once a
  /// project has entries.
  Future<bool> hasEntriesForProject(String projectId) async {
    final row = await (select(timeEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/drift/time_entries_dao_test.dart`
Expected: PASS (all tests in the file, including the 3 new ones)

- [ ] **Step 5: Commit**

```bash
git add lib/data/drift/daos/time_entries_dao.dart test/data/drift/time_entries_dao_test.dart
git commit -m "feat(projects): add hasEntriesForProject query"
```

---

### Task 2: `ProjectsDao.deleteProject`

**Files:**
- Modify: `lib/data/drift/daos/projects_dao.dart` (end of class, after `watchArchivedProjects`, line 93)
- Test: `test/data/drift/projects_dao_test.dart` (append new `test()` block at the end of `main()`, before the closing `}`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Future<void> ProjectsDao.deleteProject(String id)` — deletes the row. No guard (the "no entries" rule lives in `SyncedWrites`, Task 3).

- [ ] **Step 1: Write the failing test**

Add to `test/data/drift/projects_dao_test.dart`, inside `main()`, before the final `}`:

```dart
  test('deleteProject removes the row', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await db.projectsDao.deleteProject(project.id);

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/drift/projects_dao_test.dart`
Expected: FAIL — `The method 'deleteProject' isn't defined for the type 'ProjectsDao'`

- [ ] **Step 3: Implement `deleteProject`**

In `lib/data/drift/daos/projects_dao.dart`, add before the closing `}` of the class (after `watchArchivedProjects`):

```dart
  Future<void> deleteProject(String id) => (delete(projects)..where((p) => p.id.equals(id))).go();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/drift/projects_dao_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/drift/daos/projects_dao.dart test/data/drift/projects_dao_test.dart
git commit -m "feat(projects): add deleteProject to ProjectsDao"
```

---

### Task 3: `SyncedWrites.deleteProject` + `ProjectHasTimeEntriesException`

**Files:**
- Modify: `lib/data/sync/synced_writes.dart` (add exception class near the top, near `BreakRuleTierValues`; add method after `unarchiveProject`, before `_logCurrentProjectState`)
- Test: `test/data/synced_writes_projects_test.dart` (append new `test()` blocks at the end of `main()`, before the closing `}`)

**Interfaces:**
- Consumes: `TimeEntriesDao.hasEntriesForProject` (Task 1), `ProjectsDao.deleteProject` (Task 2).
- Produces: `class ProjectHasTimeEntriesException implements Exception {}` and `Future<void> SyncedWrites.deleteProject(String id)` — throws `ProjectHasTimeEntriesException` if the project has entries (row untouched, no log event); otherwise deletes the row and appends an `EntityTypes.project` / `EventOp.delete` event with `payload: null`.

- [ ] **Step 1: Write the failing tests**

Add to `test/data/synced_writes_projects_test.dart`, inside `main()`, before the final `}`:

```dart
  test('deleteProject removes the project and logs a delete event when it has no entries', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await writes.deleteProject(project.id);

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, isEmpty);
    final event = lastLoggedEvent(project.id);
    expect(event.entityType, EntityTypes.project);
    expect(event.op, EventOp.delete);
    expect(event.payload, isNull);
  });

  test('deleteProject throws and leaves the project untouched when it has entries', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.timeEntriesDao.startEntry(deviceId: 'dev_a', projectId: project.id);

    await expectLater(writes.deleteProject(project.id), throwsA(isA<ProjectHasTimeEntriesException>()));

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, hasLength(1));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/synced_writes_projects_test.dart`
Expected: FAIL — `The method 'deleteProject' isn't defined for the type 'SyncedWrites'` / `ProjectHasTimeEntriesException` undefined

- [ ] **Step 3: Implement the exception and method**

In `lib/data/sync/synced_writes.dart`, add after the `BreakRuleTierValues` class (before `class SyncedWrites`):

```dart
/// Thrown by [SyncedWrites.deleteProject] when the project still has at
/// least one time entry pointing at it -- archiving is the removal path
/// for projects with history, deletion is only for projects with none.
class ProjectHasTimeEntriesException implements Exception {}
```

Add inside `class SyncedWrites`, after `unarchiveProject` and before `_logCurrentProjectState`:

```dart
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/synced_writes_projects_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/synced_writes.dart test/data/synced_writes_projects_test.dart
git commit -m "feat(projects): add SyncedWrites.deleteProject"
```

---

### Task 4: i18n keys for project deletion

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- (generated, do not hand-edit) `lib/l10n/app_localizations.dart` and the 6 `app_localizations_<lang>.dart` files

**Interfaces:**
- Produces: `AppLocalizations` getters `projectsDeleteTooltip`, `projectsDeleteConfirmTitle`, `projectsDeleteConfirmMessage`, `projectsDeleteHasEntriesError`, used by Task 5.

- [ ] **Step 1: Add the keys to every ARB file**

In `lib/l10n/app_de.arb`, immediately after the existing `"projectsEditTooltip": "Bearbeiten",` line:

```json
  "projectsDeleteTooltip": "Löschen",
  "projectsDeleteConfirmTitle": "Projekt löschen?",
  "projectsDeleteConfirmMessage": "Dieses Projekt wird endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.",
  "projectsDeleteHasEntriesError": "Dieses Projekt hat noch zugewiesene Zeiteinträge und kann nicht gelöscht werden.",
```

In `lib/l10n/app_en.arb`, immediately after `"projectsUnarchiveTooltip": "Reactivate",`:

```json
  "projectsDeleteTooltip": "Delete",
  "projectsDeleteConfirmTitle": "Delete project?",
  "projectsDeleteConfirmMessage": "This project will be permanently deleted. This cannot be undone.",
  "projectsDeleteHasEntriesError": "This project still has time entries assigned and can't be deleted.",
```

In `lib/l10n/app_fr.arb`, immediately after `"projectsUnarchiveTooltip": "Réactiver",`:

```json
  "projectsDeleteTooltip": "Supprimer",
  "projectsDeleteConfirmTitle": "Supprimer le projet ?",
  "projectsDeleteConfirmMessage": "Ce projet sera définitivement supprimé. Cette action est irréversible.",
  "projectsDeleteHasEntriesError": "Ce projet a encore des saisies de temps associées et ne peut pas être supprimé.",
```

In `lib/l10n/app_es.arb`, immediately after `"projectsUnarchiveTooltip": "Reactivar",`:

```json
  "projectsDeleteTooltip": "Eliminar",
  "projectsDeleteConfirmTitle": "¿Eliminar proyecto?",
  "projectsDeleteConfirmMessage": "Este proyecto se eliminará permanentemente. Esta acción no se puede deshacer.",
  "projectsDeleteHasEntriesError": "Este proyecto todavía tiene entradas de tiempo asignadas y no se puede eliminar.",
```

In `lib/l10n/app_it.arb`, immediately after `"projectsUnarchiveTooltip": "Riattiva",`:

```json
  "projectsDeleteTooltip": "Elimina",
  "projectsDeleteConfirmTitle": "Eliminare il progetto?",
  "projectsDeleteConfirmMessage": "Questo progetto verrà eliminato definitivamente. Questa azione non può essere annullata.",
  "projectsDeleteHasEntriesError": "Questo progetto ha ancora voci di tempo assegnate e non può essere eliminato.",
```

In `lib/l10n/app_nl.arb`, immediately after `"projectsUnarchiveTooltip": "Heractiveren",`:

```json
  "projectsDeleteTooltip": "Verwijderen",
  "projectsDeleteConfirmTitle": "Project verwijderen?",
  "projectsDeleteConfirmMessage": "Dit project wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.",
  "projectsDeleteHasEntriesError": "Dit project heeft nog gekoppelde tijdregistraties en kan niet worden verwijderd.",
```

- [ ] **Step 2: Regenerate localization Dart files**

Run: `flutter gen-l10n`
Expected: exits 0, updates `lib/l10n/app_localizations.dart` and all 6 `app_localizations_<lang>.dart` files with the 4 new getters each.

- [ ] **Step 3: Run the ARB completeness test**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "feat(projects): add i18n keys for project deletion"
```

---

### Task 5: `ProjectsEditor` delete UI

**Files:**
- Modify: `lib/features/projects/projects_editor.dart`
- Test: `test/features/projects/projects_editor_test.dart` (append new `testWidgets()` blocks at the end of `main()`, before the closing `}`)

**Interfaces:**
- Consumes: `SyncedWrites.deleteProject` and `ProjectHasTimeEntriesException` (Task 3), the 4 new l10n getters (Task 4).
- Produces: a delete `IconButton` on both active and archived project rows, wired to a confirm dialog then `SyncedWrites.deleteProject`.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/projects/projects_editor_test.dart`, inside `main()`, before the final `}` (uses the same `makeApp`/`seedProject`/`pumpUntilTrue` helpers already defined in this file):

```dart
  testWidgets('renders a delete action on active project rows', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('renders a delete action on archived project rows', (tester) async {
    final project = await seedProject(archived: true);
    await tester.pumpWidget(makeApp(archived: [project]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived projects'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('confirming delete removes a project with no entries from the database', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete project?'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntilTrue(tester, () async {
        final remaining =
            await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
        return remaining.isEmpty;
      });
    });
  });

  testWidgets('cancelling the delete confirmation leaves the project untouched', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, hasLength(1));
  });

  testWidgets('attempting to delete a project with entries shows the blocked-delete error', (
    tester,
  ) async {
    final project = await seedProject();
    await db.timeEntriesDao.startEntry(deviceId: 'device-1', projectId: project.id);
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntilTrue(tester, () async {
        await tester.pump();
        return find.text("This project still has time entries assigned and can't be deleted.").evaluate().isNotEmpty;
      });
    });

    final remaining = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).get();
    expect(remaining, hasLength(1));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/projects/projects_editor_test.dart`
Expected: FAIL — `Icons.delete_outline` finds nothing in the first two new tests (no such button exists yet)

- [ ] **Step 3: Implement the delete UI**

In `lib/features/projects/projects_editor.dart`, add the import for the new exception at the top (alongside the existing imports):

```dart
import '../../data/sync/synced_writes.dart' show ProjectHasTimeEntriesException;
```

Add a `_delete` method to `_ProjectsEditorState`, after the existing `_unarchive` method:

```dart
  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.projectsDeleteConfirmTitle),
        content: Text(l10n.projectsDeleteConfirmMessage),
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
        await writes.deleteProject(id);
      } on ProjectHasTimeEntriesException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.projectsDeleteHasEntriesError)),
          );
        }
      }
    });
  }
```

In `build`, add a delete button to the active-project row's trailing `Row` (after the archive `IconButton`):

```dart
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.projectsDeleteTooltip,
                  onPressed: _busy ? null : () => _delete(project.id),
                ),
```

And to the archived-project row's trailing (replace the single `trailing: IconButton(...)` for unarchive with a `Row` containing both, matching the active row's shape):

```dart
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.unarchive_outlined),
                        tooltip: l10n.projectsUnarchiveTooltip,
                        onPressed: _busy ? null : () => _unarchive(project.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.projectsDeleteTooltip,
                        onPressed: _busy ? null : () => _delete(project.id),
                      ),
                    ],
                  ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/projects/projects_editor_test.dart`
Expected: PASS (all tests in the file, old and new)

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/projects_editor.dart test/features/projects/projects_editor_test.dart
git commit -m "feat(projects): add delete action to the projects editor"
```

---

### Task 6: `AppResetService`

**Files:**
- Create: `lib/data/reset/app_reset_service.dart`
- Test: `test/data/reset/app_reset_service_test.dart`

**Interfaces:**
- Consumes: `AppDatabase.allTables` (Drift built-in), `sync_paths.dart#deviceLogDir` (existing), `JiraCredentialsStore`/`PersonioCredentialsStore` (existing interfaces), `LocaleStore` (existing, constructed with a plain `Directory`).
- Produces: `class AppResetService` with constructor `AppResetService({required AppDatabase db, required String deviceId, required Directory effectiveSyncRoot, required Directory defaultSyncRoot, required Future<void> Function() clearSyncFolder, required JiraCredentialsStore jiraCredentialsStore, required PersonioCredentialsStore personioCredentialsStore, required LocaleStore localeStore})` and `Future<void> resetEverything()`, used by Task 8.

Note on `clearSyncFolder`: this is a callback (`syncFolderProvider.clearPersistedFolder`) rather than the whole `SyncFolderProvider` object — `SyncFolderProvider` depends on `path_provider`/`file_picker` platform channels that would need mocking for no benefit, since `resetEverything()` only ever needs to invoke this one method.

- [ ] **Step 1: Write the failing test**

Create `test/data/reset/app_reset_service_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/reset/app_reset_service.dart';
import 'package:hickory/data/sync/sync_paths.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:hickory/core/locale/locale_store.dart';

class _FakeJiraCredentialsStore implements JiraCredentialsStore {
  bool cleared = false;

  @override
  Future<JiraCredentials?> read() async => null;

  @override
  Future<void> write(JiraCredentials credentials) async {}

  @override
  Future<void> clear() async => cleared = true;
}

class _FakePersonioCredentialsStore implements PersonioCredentialsStore {
  bool cleared = false;

  @override
  Future<PersonioCredentials?> read() async => null;

  @override
  Future<void> write(PersonioCredentials credentials) async {}

  @override
  Future<void> clear() async => cleared = true;
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late Directory effectiveRoot;
  late Directory defaultRoot;
  late Directory localeDir;
  late _FakeJiraCredentialsStore jiraStore;
  late _FakePersonioCredentialsStore personioStore;
  late LocaleStore localeStore;
  late bool syncFolderCleared;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('hickory_app_reset_service_test_');
    effectiveRoot = Directory('${tempDir.path}/configured_folder')..createSync();
    defaultRoot = Directory('${tempDir.path}/default_root')..createSync();
    localeDir = Directory('${tempDir.path}/locale')..createSync();
    jiraStore = _FakeJiraCredentialsStore();
    personioStore = _FakePersonioCredentialsStore();
    localeStore = LocaleStore(supportDirectory: localeDir);
    syncFolderCleared = false;

    // This device's own log file under the configured folder, and its own
    // log file under the always-present default root -- both must be
    // deleted so the device can't re-ingest its own history on next sync.
    await deviceLogDir(effectiveRoot, 'this-device').create(recursive: true);
    await File('${deviceLogDir(effectiveRoot, 'this-device').path}/2026-08.jsonl')
        .writeAsString('{}\n');
    await deviceLogDir(defaultRoot, 'this-device').create(recursive: true);
    await File('${deviceLogDir(defaultRoot, 'this-device').path}/2026-08.jsonl')
        .writeAsString('{}\n');

    // Another device's log file under the configured (shared) folder --
    // must survive untouched: a device-local reset must never delete
    // another device's contribution to a shared sync folder.
    await deviceLogDir(effectiveRoot, 'other-device').create(recursive: true);
    await File('${deviceLogDir(effectiveRoot, 'other-device').path}/2026-08.jsonl')
        .writeAsString('{}\n');

    await localeStore.write('de');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AppResetService makeService() => AppResetService(
        db: db,
        deviceId: 'this-device',
        effectiveSyncRoot: effectiveRoot,
        defaultSyncRoot: defaultRoot,
        clearSyncFolder: () async => syncFolderCleared = true,
        jiraCredentialsStore: jiraStore,
        personioCredentialsStore: personioStore,
        localeStore: localeStore,
      );

  test('resetEverything clears every drift table', () async {
    await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.timeEntriesDao.startEntry(deviceId: 'this-device');
    await db.appSettingsDao.updateSettings(dateFormat: 'us');
    await db.breakRuleTiersDao.createTier(deviceId: 'this-device', afterMinutes: 360, requiredBreakMinutes: 30);

    await makeService().resetEverything();

    for (final table in db.allTables) {
      final rows = await db.customSelect('SELECT * FROM ${table.actualTableName}').get();
      expect(rows, isEmpty, reason: 'expected ${table.actualTableName} to be empty after reset');
    }
  });

  test('resetEverything deletes this device\'s own log directory from both roots', () async {
    await makeService().resetEverything();

    expect(await deviceLogDir(effectiveRoot, 'this-device').exists(), isFalse);
    expect(await deviceLogDir(defaultRoot, 'this-device').exists(), isFalse);
  });

  test('resetEverything never touches another device\'s log directory', () async {
    await makeService().resetEverything();

    expect(await deviceLogDir(effectiveRoot, 'other-device').exists(), isTrue);
  });

  test('resetEverything clears the sync folder pointer, credentials, and locale', () async {
    await makeService().resetEverything();

    expect(syncFolderCleared, isTrue);
    expect(jiraStore.cleared, isTrue);
    expect(personioStore.cleared, isTrue);
    expect(await localeStore.read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/reset/app_reset_service_test.dart`
Expected: FAIL — `Error: Not found: 'package:hickory/data/reset/app_reset_service.dart'`

- [ ] **Step 3: Implement `AppResetService`**

Create `lib/data/reset/app_reset_service.dart`:

```dart
import 'dart:io';

import '../../core/locale/locale_store.dart';
import '../../features/jira/jira_credentials_store.dart';
import '../../features/personio/personio_credentials_store.dart';
import '../drift/database.dart';
import '../sync/sync_paths.dart';

/// Returns this device to a fresh-install state: every local drift row is
/// deleted, this device's own sync event-log files are deleted (so the next
/// sync pass can't re-ingest and resurrect its own history -- see
/// docs/superpowers/specs/2026-08-05-project-delete-and-full-reset-design.md
/// section 3.1 for why that matters), the configured sync folder is
/// forgotten, and third-party credentials plus the locale preference are
/// cleared. Deliberately bypasses SyncedWrites/the event log entirely: this
/// *is* the sync state being cleared, so it can't go through that pipeline.
class AppResetService {
  AppResetService({
    required this.db,
    required this.deviceId,
    required this.effectiveSyncRoot,
    required this.defaultSyncRoot,
    required this.clearSyncFolder,
    required this.jiraCredentialsStore,
    required this.personioCredentialsStore,
    required this.localeStore,
  });

  final AppDatabase db;
  final String deviceId;
  final Directory effectiveSyncRoot;
  final Directory defaultSyncRoot;
  final Future<void> Function() clearSyncFolder;
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
    await clearSyncFolder();
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/reset/app_reset_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/reset/app_reset_service.dart test/data/reset/app_reset_service_test.dart
git commit -m "feat(reset): add AppResetService"
```

---

### Task 7: i18n keys for the reset UI

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- (generated) `lib/l10n/app_localizations.dart` and the 6 `app_localizations_<lang>.dart` files

**Interfaces:**
- Produces: `AppLocalizations` getters `settingsResetTitle`, `settingsResetDescription`, `settingsResetButton`, `settingsResetConfirmTitle`, `settingsResetConfirmMessage`, `settingsResetConfirmButton`, `settingsResetSuccess`, `settingsResetError`, used by Task 8.

- [ ] **Step 1: Add the keys to every ARB file**

Append to the end of `lib/l10n/app_de.arb`, just before the final closing `}` (add a comma after whatever the current last key's value line is):

```json
  "settingsResetTitle": "Zurücksetzen",
  "settingsResetDescription": "Löscht alle lokalen Daten dieses Geräts (Projekte, Kunden, Zeiteinträge, Einstellungen, Jira-/Personio-Verknüpfungen) und trennt die Verbindung zum Sync-Ordner. Andere Geräte sind davon nicht betroffen.",
  "settingsResetButton": "Komplett zurücksetzen",
  "settingsResetConfirmTitle": "Wirklich alles zurücksetzen?",
  "settingsResetConfirmMessage": "Projekte, Kunden, Zeiteinträge, Einstellungen und Jira-/Personio-Verknüpfungen auf diesem Gerät werden unwiderruflich gelöscht, und die Verbindung zum Sync-Ordner wird getrennt. Diese Aktion kann nicht rückgängig gemacht werden.",
  "settingsResetConfirmButton": "Ja, alles zurücksetzen",
  "settingsResetSuccess": "App wurde zurückgesetzt.",
  "settingsResetError": "Zurücksetzen fehlgeschlagen."
```

Append the equivalent block (same keys) just before the final closing `}` in `lib/l10n/app_en.arb`:

```json
  "settingsResetTitle": "Reset",
  "settingsResetDescription": "Deletes all of this device's local data (projects, clients, time entries, settings, Jira/Personio links) and disconnects it from the sync folder. Other devices are not affected.",
  "settingsResetButton": "Reset everything",
  "settingsResetConfirmTitle": "Really reset everything?",
  "settingsResetConfirmMessage": "Projects, clients, time entries, settings, and Jira/Personio links on this device will be permanently deleted, and the connection to the sync folder will be removed. This cannot be undone.",
  "settingsResetConfirmButton": "Yes, reset everything",
  "settingsResetSuccess": "The app has been reset.",
  "settingsResetError": "Reset failed."
```

`lib/l10n/app_fr.arb`:

```json
  "settingsResetTitle": "Réinitialiser",
  "settingsResetDescription": "Supprime toutes les données locales de cet appareil (projets, clients, saisies de temps, paramètres, liens Jira/Personio) et le déconnecte du dossier de synchronisation. Les autres appareils ne sont pas concernés.",
  "settingsResetButton": "Tout réinitialiser",
  "settingsResetConfirmTitle": "Vraiment tout réinitialiser ?",
  "settingsResetConfirmMessage": "Les projets, clients, saisies de temps, paramètres et liens Jira/Personio de cet appareil seront définitivement supprimés, et la connexion au dossier de synchronisation sera supprimée. Cette action est irréversible.",
  "settingsResetConfirmButton": "Oui, tout réinitialiser",
  "settingsResetSuccess": "L'application a été réinitialisée.",
  "settingsResetError": "La réinitialisation a échoué."
```

`lib/l10n/app_es.arb`:

```json
  "settingsResetTitle": "Restablecer",
  "settingsResetDescription": "Elimina todos los datos locales de este dispositivo (proyectos, clientes, entradas de tiempo, ajustes, vínculos de Jira/Personio) y lo desconecta de la carpeta de sincronización. Los demás dispositivos no se ven afectados.",
  "settingsResetButton": "Restablecer todo",
  "settingsResetConfirmTitle": "¿Restablecer todo de verdad?",
  "settingsResetConfirmMessage": "Los proyectos, clientes, entradas de tiempo, ajustes y vínculos de Jira/Personio de este dispositivo se eliminarán permanentemente, y se eliminará la conexión con la carpeta de sincronización. Esta acción no se puede deshacer.",
  "settingsResetConfirmButton": "Sí, restablecer todo",
  "settingsResetSuccess": "La aplicación se ha restablecido.",
  "settingsResetError": "No se pudo restablecer."
```

`lib/l10n/app_it.arb`:

```json
  "settingsResetTitle": "Ripristina",
  "settingsResetDescription": "Elimina tutti i dati locali di questo dispositivo (progetti, clienti, voci di tempo, impostazioni, collegamenti Jira/Personio) e lo disconnette dalla cartella di sincronizzazione. Gli altri dispositivi non vengono interessati.",
  "settingsResetButton": "Ripristina tutto",
  "settingsResetConfirmTitle": "Ripristinare davvero tutto?",
  "settingsResetConfirmMessage": "Progetti, clienti, voci di tempo, impostazioni e collegamenti Jira/Personio su questo dispositivo verranno eliminati definitivamente, e la connessione alla cartella di sincronizzazione verrà rimossa. Questa azione non può essere annullata.",
  "settingsResetConfirmButton": "Sì, ripristina tutto",
  "settingsResetSuccess": "L'app è stata ripristinata.",
  "settingsResetError": "Ripristino non riuscito."
```

`lib/l10n/app_nl.arb`:

```json
  "settingsResetTitle": "Resetten",
  "settingsResetDescription": "Verwijdert alle lokale gegevens van dit apparaat (projecten, klanten, tijdregistraties, instellingen, Jira-/Personio-koppelingen) en koppelt het los van de synchronisatiemap. Andere apparaten worden niet beïnvloed.",
  "settingsResetButton": "Alles resetten",
  "settingsResetConfirmTitle": "Alles echt resetten?",
  "settingsResetConfirmMessage": "Projecten, klanten, tijdregistraties, instellingen en Jira-/Personio-koppelingen op dit apparaat worden permanent verwijderd, en de verbinding met de synchronisatiemap wordt verwijderd. Dit kan niet ongedaan worden gemaakt.",
  "settingsResetConfirmButton": "Ja, alles resetten",
  "settingsResetSuccess": "De app is gereset.",
  "settingsResetError": "Resetten is mislukt."
```

Remember: every ARB file is a single JSON object — adding a block "at the end" means inserting it right before the file's final `}`, and adding a trailing comma after the previous last key's line so the JSON stays valid.

- [ ] **Step 2: Regenerate localization Dart files**

Run: `flutter gen-l10n`
Expected: exits 0

- [ ] **Step 3: Run the ARB completeness test**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "feat(reset): add i18n keys for the reset UI"
```

---

### Task 8: `AppResetSection` UI + provider wiring + Settings screen

**Files:**
- Create: `lib/core/di/reset_providers.dart`
- Create: `lib/features/settings/app_reset_section.dart`
- Modify: `lib/features/settings/settings_screen.dart` (add the new card)
- Test: `test/features/settings/app_reset_section_test.dart`

**Interfaces:**
- Consumes: `AppResetService` (Task 6), the 8 new l10n getters (Task 7), existing providers `configuredSyncFolderPathProvider`/`effectiveSyncRootProvider`/`syncFolderProviderProvider` (`lib/core/di/sync_providers.dart`), `deviceIdProvider` (`lib/core/di/device_id_provider.dart`), `appDatabaseProvider` (`lib/core/di/database_provider.dart`), `jiraCredentialsStoreProvider`/`jiraCredentialsProvider` (`lib/core/di/jira_providers.dart`), `personioCredentialsStoreProvider`/`personioCredentialsProvider` (`lib/core/di/personio_providers.dart`), `localeStoreProvider`/`localeControllerProvider` (`lib/core/di/locale_provider.dart`), `sync_paths.dart#defaultSyncRoot`.
- Produces: `appResetServiceProvider` (`FutureProvider<AppResetService>`), `AppResetSection extends ConsumerStatefulWidget`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/settings/app_reset_section_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/reset_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/reset/app_reset_service.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/features/settings/app_reset_section.dart';
import 'package:hickory/l10n/app_localizations.dart';

class _NoopJiraCredentialsStore implements JiraCredentialsStore {
  @override
  Future<JiraCredentials?> read() async => null;
  @override
  Future<void> write(JiraCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

class _NoopPersonioCredentialsStore implements PersonioCredentialsStore {
  @override
  Future<PersonioCredentials?> read() async => null;
  @override
  Future<void> write(PersonioCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

Future<void> pumpUntilTrue(
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) return;
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late bool resetCalled;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('hickory_app_reset_section_test_');
    resetCalled = false;
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appResetServiceProvider.overrideWith(
            (ref) async => AppResetService(
              db: db,
              deviceId: 'device-1',
              effectiveSyncRoot: Directory('${tempDir.path}/effective')..createSync(),
              defaultSyncRoot: Directory('${tempDir.path}/default')..createSync(),
              clearSyncFolder: () async => resetCalled = true,
              jiraCredentialsStore: _NoopJiraCredentialsStore(),
              personioCredentialsStore: _NoopPersonioCredentialsStore(),
              localeStore: LocaleStore(supportDirectory: Directory('${tempDir.path}/locale')..createSync()),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AppResetSection()),
        ),
      );

  testWidgets('shows the reset button', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Reset everything'), findsOneWidget);
  });

  testWidgets('tapping the button opens a confirmation dialog explaining the consequences', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();

    expect(find.text('Really reset everything?'), findsOneWidget);
    expect(resetCalled, isFalse);
  });

  testWidgets('cancelling the confirmation performs no reset', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(resetCalled, isFalse);
  });

  testWidgets('confirming runs the reset and shows a success message', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Yes, reset everything'));
      await pumpUntilTrue(() async {
        await tester.pump();
        return resetCalled;
      });
      await pumpUntilTrue(() async {
        await tester.pump();
        return find.text('The app has been reset.').evaluate().isNotEmpty;
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/settings/app_reset_section_test.dart`
Expected: FAIL — `Error: Not found: 'package:hickory/core/di/reset_providers.dart'` / `'package:hickory/features/settings/app_reset_section.dart'`

- [ ] **Step 3: Implement `reset_providers.dart`**

Create `lib/core/di/reset_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reset/app_reset_service.dart';
import '../../data/sync/sync_paths.dart';
import 'database_provider.dart';
import 'device_id_provider.dart';
import 'jira_providers.dart';
import 'locale_provider.dart';
import 'personio_providers.dart';
import 'sync_providers.dart';

// Plain (non-generated) provider -- same reasoning as sync_providers.dart:
// AppResetService's constructor touches AppDatabase (drift-generated).

final appResetServiceProvider = FutureProvider<AppResetService>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final deviceId = await ref.watch(deviceIdProvider.future);
  final effectiveRoot = await ref.watch(effectiveSyncRootProvider.future);
  final localeStore = await ref.watch(localeStoreProvider.future);
  return AppResetService(
    db: db,
    deviceId: deviceId,
    effectiveSyncRoot: effectiveRoot,
    defaultSyncRoot: await defaultSyncRoot(),
    clearSyncFolder: ref.watch(syncFolderProviderProvider).clearPersistedFolder,
    jiraCredentialsStore: ref.watch(jiraCredentialsStoreProvider),
    personioCredentialsStore: ref.watch(personioCredentialsStoreProvider),
    localeStore: localeStore,
  );
});
```

- [ ] **Step 4: Implement `AppResetSection`**

Create `lib/features/settings/app_reset_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/locale_provider.dart';
import '../../core/di/personio_providers.dart';
import '../../core/di/reset_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';

/// Settings-screen "danger zone": returns this device to a fresh-install
/// state. See
/// docs/superpowers/specs/2026-08-05-project-delete-and-full-reset-design.md
/// for why this only ever touches this device's own data.
class AppResetSection extends ConsumerStatefulWidget {
  const AppResetSection({super.key});

  @override
  ConsumerState<AppResetSection> createState() => _AppResetSectionState();
}

class _AppResetSectionState extends ConsumerState<AppResetSection> {
  bool _busy = false;

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsResetConfirmTitle),
        content: Text(l10n.settingsResetConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsResetConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = await ref.read(appResetServiceProvider.future);
      await service.resetEverything();
      ref.invalidate(configuredSyncFolderPathProvider);
      ref.invalidate(jiraCredentialsProvider);
      ref.invalidate(personioCredentialsProvider);
      ref.invalidate(localeControllerProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsResetSuccess)),
        );
      }
    } catch (error) {
      debugPrint('Failed to reset the app: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsResetError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsResetTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsResetDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error),
          ),
          onPressed: _busy ? null : _reset,
          child: Text(l10n.settingsResetButton),
        ),
      ],
    );
  }
}
```

Add `import 'debug_print'` note: `debugPrint` comes from `package:flutter/foundation.dart`, already re-exported by `package:flutter/material.dart`, so no separate import is needed (matches how `settings_screen.dart` and `projects_editor.dart` already call `debugPrint` with only the `material.dart` import).

- [ ] **Step 5: Wire `AppResetSection` into the Settings screen**

In `lib/features/settings/settings_screen.dart`, add the import alongside the existing feature imports:

```dart
import 'app_reset_section.dart';
```

Add a new `Card` after the existing update `Card` block (after the `if (Platform.isMacOS || Platform.isWindows) ...[` block's closing `],`, still inside the outer `children: [...]` list of the root `Column`):

```dart
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AppResetSection(),
            ),
          ),
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/settings/app_reset_section_test.dart`
Expected: PASS

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: PASS (no regressions in `settings_screen`-adjacent tests or elsewhere)

- [ ] **Step 8: Commit**

```bash
git add lib/core/di/reset_providers.dart lib/features/settings/app_reset_section.dart lib/features/settings/settings_screen.dart test/features/settings/app_reset_section_test.dart
git commit -m "feat(reset): add the full-reset button to Settings"
```

---

## Post-Plan Verification

After Task 8, run the complete suite once more and confirm nothing outside this plan's files changed:

```bash
flutter analyze
flutter test
git status
```

`flutter analyze` must report no new issues; `git status` should show a clean tree (everything already committed task-by-task).
