# Project Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit a project's name, color, billable flag, hourly rate, and
currency, and archive/reactivate projects, from a new Settings section — today
projects can only be created, never edited, and the existing `archiveProject` DAO
method is unused.

**Architecture:** New DAO/`SyncedWrites` methods (`updateProject`, `archiveProject`,
`unarchiveProject`) following the exact existing write-through pattern. A single
`showProjectFormDialog` replaces the old create-only dialog, used for both create and
edit. A new `ProjectsEditor` widget (Settings) lists active projects with edit/archive
actions and a collapsible archived section with reactivate.

**Tech Stack:** Flutter, Riverpod (plain providers for Drift row types — see Global
Constraints), Drift.

**Full design:** `docs/superpowers/specs/2026-08-04-project-editing-design.md`

## Global Constraints

- English only in code, comments, and commit messages (repo convention).
- No schema/migration changes: every field this plan touches (`name`, `colorHex`,
  `billable`, `hourlyRateCents`, `currency`, `archived`) already exists on the
  `Projects` table. No `dart run build_runner build` needed — every new method is
  hand-written directly on `ProjectsDao`/`SyncedWrites`, not generated code.
- No `SyncIngestor` change needed: `_applyMaterializedEntity`'s `EntityTypes.project`
  case already does insert-or-update from the latest payload regardless of `op`, so an
  `EventOp.update` project event is already handled.
- ARB template locale is **German** (`lib/l10n/app_de.arb`,
  `template-arb-file: app_de.arb` in `l10n.yaml`). `test/l10n/arb_completeness_test.dart`
  fails the build if any of the 6 locale files' key sets diverge. After editing ARB
  files, run `flutter gen-l10n` before running any test that uses the new keys.
- Providers touching Drift-generated row classes (`Project`, ...) must be **plain**
  `StreamProvider`, not `@riverpod` codegen — mixing riverpod_generator with drift's
  generator on the same type trips `rrousselGit/riverpod#4323` (see
  `lib/features/projects/projects_providers.dart` for the existing precedent).
- Widget tests must override `activeProjectsProvider`/`archivedProjectsProvider` with
  a static `Stream.value(...)`, never leave them wired to the live drift-backed
  provider — a mounted widget subscribed to a real drift `QueryStream` hits a known
  `flutter_test` false positive ("A Timer is still pending...",
  flutter/flutter#144472) at teardown, documented in `test/features/entries/quick_add_bar_test.dart`.
  A test that must show a post-write UI update fully unmounts
  (`tester.pumpWidget(const SizedBox())`) and remounts with a fresh static override —
  same technique `quick_add_bar_test.dart` uses — rather than relying on the stream to
  emit again.
- `SyncedWrites` performs real file I/O per write (`SyncLogWriter.appendEvent`).
  `flutter_test`'s fake clock never completes real async I/O outside
  `WidgetTester.runAsync`, so every widget-test tap that triggers a `SyncedWrites` call
  must be wrapped in `tester.runAsync(() async { ... })` together with a polling helper
  that uses real `Future.delayed`/`tester.pump(Duration)` — see
  `test/features/settings/break_rule_tiers_editor_test.dart`'s `pumpUntilTrue`. This
  repo has no shared test helper for it; each test file defines its own copy — don't
  introduce a shared one.
- `hourlyRateCents` is a whole-cents integer; the form field is a whole-currency-unit
  text input (e.g. "95.50"), converted via `(value * 100).round()`.

---

### Task 1: `ProjectsDao` — update, archive, unarchive

**Files:**
- Modify: `lib/data/drift/daos/projects_dao.dart`
- Test: `test/data/drift/projects_dao_test.dart`

**Interfaces:**
- Produces: `ProjectsDao.updateProject(String id, {Value<String> name, Value<String>
  colorHex, Value<bool> billable, Value<int?> hourlyRateCents, Value<String?>
  currency})` → `Future<void>`; `ProjectsDao.unarchiveProject(String id)` →
  `Future<void>`; `ProjectsDao.watchArchivedProjects()` → `Stream<List<Project>>`.
  (`ProjectsDao.archiveProject(String id)` already exists, unchanged.)

- [ ] **Step 1: Write the failing DAO test**

Create `test/data/drift/projects_dao_test.dart`:

```dart
import 'package:drift/drift.dart';
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

  test('updateProject updates only the fields passed', () async {
    final project = await db.projectsDao.createProject(
      name: 'Old Name',
      colorHex: '#5B8DEF',
      hourlyRateCents: 5000,
      currency: 'USD',
    );

    await db.projectsDao.updateProject(project.id, name: const Value('New Name'));

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.name, 'New Name');
    expect(updated.colorHex, '#5B8DEF');
    expect(updated.billable, isTrue);
    expect(updated.hourlyRateCents, 5000);
    expect(updated.currency, 'USD');
  });

  test('updateProject can set hourlyRateCents and currency to null', () async {
    final project = await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#5B8DEF',
      hourlyRateCents: 5000,
      currency: 'USD',
    );

    await db.projectsDao.updateProject(
      project.id,
      hourlyRateCents: const Value(null),
      currency: const Value(null),
    );

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.hourlyRateCents, isNull);
    expect(updated.currency, isNull);
  });

  test('archiveProject sets archived to true', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await db.projectsDao.archiveProject(project.id);

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.archived, isTrue);
  });

  test('unarchiveProject sets archived back to false', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.projectsDao.archiveProject(project.id);

    await db.projectsDao.unarchiveProject(project.id);

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.archived, isFalse);
  });

  test('watchArchivedProjects only returns archived projects, ordered by name', () async {
    final active = await db.projectsDao.createProject(name: 'Active Project', colorHex: '#5B8DEF');
    final archivedB = await db.projectsDao.createProject(name: 'Zeta', colorHex: '#EF5B5B');
    final archivedA = await db.projectsDao.createProject(name: 'Alpha', colorHex: '#5BEF8D');
    await db.projectsDao.archiveProject(archivedB.id);
    await db.projectsDao.archiveProject(archivedA.id);

    final archived = await db.projectsDao.watchArchivedProjects().first;

    expect(archived.map((p) => p.name), ['Alpha', 'Zeta']);
    expect(archived.any((p) => p.id == active.id), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/drift/projects_dao_test.dart`
Expected: FAIL — `updateProject`/`unarchiveProject`/`watchArchivedProjects` are not
defined on `ProjectsDao`.

- [ ] **Step 3: Implement the DAO methods**

Edit `lib/data/drift/daos/projects_dao.dart`. Find:

```dart
  Future<void> archiveProject(String id) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now().toUtc())),
    );
  }
}
```

Replace it with:

```dart
  Future<void> archiveProject(String id) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> unarchiveProject(String id) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(archived: const Value(false), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  /// Partial update: every parameter left as [Value.absent] keeps that
  /// column's current value -- same shape as [TimeEntriesDao.updateEntry].
  Future<void> updateProject(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String> colorHex = const Value.absent(),
    Value<bool> billable = const Value.absent(),
    Value<int?> hourlyRateCents = const Value.absent(),
    Value<String?> currency = const Value.absent(),
  }) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: name,
        colorHex: colorHex,
        billable: billable,
        hourlyRateCents: hourlyRateCents,
        currency: currency,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Same shape as [watchActiveProjects] but the inverse filter -- backs the
  /// Settings project manager's "Archived projects" section.
  Stream<List<Project>> watchArchivedProjects() {
    return (select(projects)
          ..where((p) => p.archived.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/drift/projects_dao_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/drift/daos/projects_dao.dart test/data/drift/projects_dao_test.dart
git commit -m "feat(projects): add project update/archive DAO methods"
```

---

### Task 2: `SyncedWrites` — update, archive, unarchive with sync logging

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`
- Test: `test/data/synced_writes_projects_test.dart`

**Interfaces:**
- Consumes: `ProjectsDao.updateProject`/`unarchiveProject`/`watchArchivedProjects` from
  Task 1 (exact signatures above).
- Produces: `SyncedWrites.updateProject(String id, {Value<String> name, Value<String>
  colorHex, Value<bool> billable, Value<int?> hourlyRateCents, Value<String?>
  currency})` → `Future<Project>`; `SyncedWrites.archiveProject(String id)` →
  `Future<void>`; `SyncedWrites.unarchiveProject(String id)` → `Future<void>`. Each logs
  an `EntityTypes.project` / `EventOp.update` event, matching every other write in this
  class.

- [ ] **Step 1: Write the failing test**

Create `test/data/synced_writes_projects_test.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_synced_writes_projects_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('updateProject persists the given fields and returns the updated row', () async {
    final project = await writes.createProject(name: 'Old Name', colorHex: '#5B8DEF');

    final updated = await writes.updateProject(
      project.id,
      name: const Value('New Name'),
      billable: const Value(false),
    );

    expect(updated.name, 'New Name');
    expect(updated.billable, isFalse);
    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.name, 'New Name');
    expect(row.billable, isFalse);
  });

  test('archiveProject marks the project archived', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await writes.archiveProject(project.id);

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isTrue);
  });

  test('unarchiveProject clears the archived flag', () async {
    final project = await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await writes.archiveProject(project.id);

    await writes.unarchiveProject(project.id);

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/synced_writes_projects_test.dart`
Expected: FAIL — `updateProject`/`archiveProject`/`unarchiveProject` are not defined on
`SyncedWrites`.

- [ ] **Step 3: Implement the SyncedWrites methods**

Edit `lib/data/sync/synced_writes.dart`. Find:

```dart
    await logWriter.appendEvent(
      entityType: EntityTypes.project,
      entityId: project.id,
      op: EventOp.create,
      payload: project.toJson(),
    );
    return project;
  }

  Future<TimeEntry> startEntry({
```

Replace it with:

```dart
    await logWriter.appendEvent(
      entityType: EntityTypes.project,
      entityId: project.id,
      op: EventOp.create,
      payload: project.toJson(),
    );
    return project;
  }

  /// Partial update -- see [ProjectsDao.updateProject] for the [Value]
  /// semantics. Returns the row after the write so callers (the project
  /// form dialog) can use it without a second read.
  Future<Project> updateProject(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String> colorHex = const Value.absent(),
    Value<bool> billable = const Value.absent(),
    Value<int?> hourlyRateCents = const Value.absent(),
    Value<String?> currency = const Value.absent(),
  }) async {
    await db.projectsDao.updateProject(
      id,
      name: name,
      colorHex: colorHex,
      billable: billable,
      hourlyRateCents: hourlyRateCents,
      currency: currency,
    );
    return _logCurrentProjectState(id);
  }

  Future<void> archiveProject(String id) async {
    await db.projectsDao.archiveProject(id);
    await _logCurrentProjectState(id);
  }

  Future<void> unarchiveProject(String id) async {
    await db.projectsDao.unarchiveProject(id);
    await _logCurrentProjectState(id);
  }

  /// Re-reads the project's current row and appends it as an
  /// [EventOp.update] log entry -- the write-then-log pattern every project
  /// mutation above (other than [createProject]) shares, mirroring
  /// [_logCurrentState]'s role for TimeEntries.
  Future<Project> _logCurrentProjectState(String id) async {
    final current = await (db.select(db.projects)..where((p) => p.id.equals(id))).getSingle();
    await logWriter.appendEvent(
      entityType: EntityTypes.project,
      entityId: id,
      op: EventOp.update,
      payload: current.toJson(),
    );
    return current;
  }

  Future<TimeEntry> startEntry({
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/synced_writes_projects_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/synced_writes.dart test/data/synced_writes_projects_test.dart
git commit -m "feat(sync): add project update/archive SyncedWrites methods"
```

---

### Task 3: Localization strings

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`,
  `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Generated (via `flutter gen-l10n`, not hand-edited): `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `AppLocalizations` getters `projectsEditTitle`, `projectsBillableLabel`,
  `projectsHourlyRateLabel`, `projectsCurrencyLabel`, `projectsArchiveTooltip`,
  `projectsUnarchiveTooltip`, `projectsInvalidRateError`, `settingsProjectsTitle`,
  `settingsProjectsDescription`, `settingsProjectsAddLabel`,
  `settingsProjectsArchivedSection`, `settingsProjectsSaveError` — consumed by Task 4
  and Task 5.

- [ ] **Step 1: Add the new keys to all 6 ARB files**

Edit `lib/l10n/app_de.arb`. Find:

```json
  "settingsBreakRuleIncludePausedTimeDescription": "Zählt die über den Pause-Button des Timers pausierte Zeit zur Pausenzeit hinzu, zusätzlich zu Lücken zwischen Einträgen.",
  "projectsNewProjectTitle": "Neues Projekt",
  "projectsNameLabel": "Name",
  "projectsCreateButton": "Erstellen",
```

Replace it with:

```json
  "settingsBreakRuleIncludePausedTimeDescription": "Zählt die über den Pause-Button des Timers pausierte Zeit zur Pausenzeit hinzu, zusätzlich zu Lücken zwischen Einträgen.",
  "settingsProjectsTitle": "Projekte",
  "settingsProjectsDescription": "Projekte anlegen, bearbeiten und archivieren.",
  "settingsProjectsAddLabel": "Projekt hinzufügen",
  "settingsProjectsArchivedSection": "Archivierte Projekte",
  "settingsProjectsSaveError": "Änderung konnte nicht gespeichert werden.",
  "projectsNewProjectTitle": "Neues Projekt",
  "projectsNameLabel": "Name",
  "projectsCreateButton": "Erstellen",
  "projectsEditTitle": "Projekt bearbeiten",
  "projectsBillableLabel": "Abrechenbar",
  "projectsHourlyRateLabel": "Stundensatz",
  "projectsCurrencyLabel": "Währung",
  "projectsArchiveTooltip": "Archivieren",
  "projectsUnarchiveTooltip": "Reaktivieren",
  "projectsInvalidRateError": "Bitte einen gültigen Betrag eingeben.",
```

Edit `lib/l10n/app_en.arb`. Find:

```json
  "settingsBreakRuleIncludePausedTimeDescription": "Counts time paused via the Timer's pause button toward break time, in addition to gaps between entries.",
  "projectsNewProjectTitle": "New project",
  "projectsNameLabel": "Name",
  "projectsCreateButton": "Create",
```

Replace it with:

```json
  "settingsBreakRuleIncludePausedTimeDescription": "Counts time paused via the Timer's pause button toward break time, in addition to gaps between entries.",
  "settingsProjectsTitle": "Projects",
  "settingsProjectsDescription": "Create, edit, and archive projects.",
  "settingsProjectsAddLabel": "Add project",
  "settingsProjectsArchivedSection": "Archived projects",
  "settingsProjectsSaveError": "Could not save the change.",
  "projectsNewProjectTitle": "New project",
  "projectsNameLabel": "Name",
  "projectsCreateButton": "Create",
  "projectsEditTitle": "Edit project",
  "projectsBillableLabel": "Billable",
  "projectsHourlyRateLabel": "Hourly rate",
  "projectsCurrencyLabel": "Currency",
  "projectsArchiveTooltip": "Archive",
  "projectsUnarchiveTooltip": "Reactivate",
  "projectsInvalidRateError": "Please enter a valid amount.",
```

Edit `lib/l10n/app_es.arb`. Find:

```json
  "projectsNewProjectTitle": "Nuevo proyecto",
  "projectsNameLabel": "Nombre",
  "projectsCreateButton": "Crear",
```

Replace it with:

```json
  "settingsProjectsTitle": "Proyectos",
  "settingsProjectsDescription": "Crea, edita y archiva proyectos.",
  "settingsProjectsAddLabel": "Añadir proyecto",
  "settingsProjectsArchivedSection": "Proyectos archivados",
  "settingsProjectsSaveError": "No se pudo guardar el cambio.",
  "projectsNewProjectTitle": "Nuevo proyecto",
  "projectsNameLabel": "Nombre",
  "projectsCreateButton": "Crear",
  "projectsEditTitle": "Editar proyecto",
  "projectsBillableLabel": "Facturable",
  "projectsHourlyRateLabel": "Tarifa por hora",
  "projectsCurrencyLabel": "Moneda",
  "projectsArchiveTooltip": "Archivar",
  "projectsUnarchiveTooltip": "Reactivar",
  "projectsInvalidRateError": "Introduce un importe válido.",
```

Edit `lib/l10n/app_fr.arb`. Find:

```json
  "projectsNewProjectTitle": "Nouveau projet",
  "projectsNameLabel": "Nom",
  "projectsCreateButton": "Créer",
```

Replace it with:

```json
  "settingsProjectsTitle": "Projets",
  "settingsProjectsDescription": "Créer, modifier et archiver des projets.",
  "settingsProjectsAddLabel": "Ajouter un projet",
  "settingsProjectsArchivedSection": "Projets archivés",
  "settingsProjectsSaveError": "Impossible d'enregistrer la modification.",
  "projectsNewProjectTitle": "Nouveau projet",
  "projectsNameLabel": "Nom",
  "projectsCreateButton": "Créer",
  "projectsEditTitle": "Modifier le projet",
  "projectsBillableLabel": "Facturable",
  "projectsHourlyRateLabel": "Taux horaire",
  "projectsCurrencyLabel": "Devise",
  "projectsArchiveTooltip": "Archiver",
  "projectsUnarchiveTooltip": "Réactiver",
  "projectsInvalidRateError": "Veuillez saisir un montant valide.",
```

Edit `lib/l10n/app_it.arb`. Find:

```json
  "projectsNewProjectTitle": "Nuovo progetto",
  "projectsNameLabel": "Nome",
  "projectsCreateButton": "Crea",
```

Replace it with:

```json
  "settingsProjectsTitle": "Progetti",
  "settingsProjectsDescription": "Crea, modifica e archivia progetti.",
  "settingsProjectsAddLabel": "Aggiungi progetto",
  "settingsProjectsArchivedSection": "Progetti archiviati",
  "settingsProjectsSaveError": "Impossibile salvare la modifica.",
  "projectsNewProjectTitle": "Nuovo progetto",
  "projectsNameLabel": "Nome",
  "projectsCreateButton": "Crea",
  "projectsEditTitle": "Modifica progetto",
  "projectsBillableLabel": "Fatturabile",
  "projectsHourlyRateLabel": "Tariffa oraria",
  "projectsCurrencyLabel": "Valuta",
  "projectsArchiveTooltip": "Archivia",
  "projectsUnarchiveTooltip": "Riattiva",
  "projectsInvalidRateError": "Inserisci un importo valido.",
```

Edit `lib/l10n/app_nl.arb`. Find:

```json
  "projectsNewProjectTitle": "Nieuw project",
  "projectsNameLabel": "Naam",
  "projectsCreateButton": "Aanmaken",
```

Replace it with:

```json
  "settingsProjectsTitle": "Projecten",
  "settingsProjectsDescription": "Projecten aanmaken, bewerken en archiveren.",
  "settingsProjectsAddLabel": "Project toevoegen",
  "settingsProjectsArchivedSection": "Gearchiveerde projecten",
  "settingsProjectsSaveError": "Wijziging kon niet worden opgeslagen.",
  "projectsNewProjectTitle": "Nieuw project",
  "projectsNameLabel": "Naam",
  "projectsCreateButton": "Aanmaken",
  "projectsEditTitle": "Project bewerken",
  "projectsBillableLabel": "Factureerbaar",
  "projectsHourlyRateLabel": "Uurtarief",
  "projectsCurrencyLabel": "Valuta",
  "projectsArchiveTooltip": "Archiveren",
  "projectsUnarchiveTooltip": "Heractiveren",
  "projectsInvalidRateError": "Voer een geldig bedrag in.",
```

- [ ] **Step 2: Verify key parity across locales**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes with no errors; `lib/l10n/app_localizations*.dart` are updated with
the 12 new getters.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart
git commit -m "feat(l10n): add project editing and archiving strings"
```

---

### Task 4: Unified create/edit project dialog

**Files:**
- Create: `lib/features/projects/project_form_dialog.dart`
- Delete: `lib/features/projects/new_project_dialog.dart`
- Modify: `lib/features/timer/timer_screen.dart:17,322`
- Modify: `lib/features/entries/quick_add_bar.dart:11,167`
- Test: `test/features/projects/project_form_dialog_test.dart`

**Interfaces:**
- Consumes: `SyncedWrites.createProject` (existing), `SyncedWrites.updateProject` (Task
  2), `AppLocalizations.projectsEditTitle`/`projectsBillableLabel`/
  `projectsHourlyRateLabel`/`projectsCurrencyLabel`/`projectsInvalidRateError` (Task 3).
- Produces: `showProjectFormDialog(BuildContext context, WidgetRef ref, {Project?
  project})` → `Future<void>` — omit `project` to create, pass it to edit. Also
  `const projectColorPalette` (moved here from the deleted file), consumed by Task 5's
  `ProjectsEditor` (indirectly, via this dialog) and by nothing else.

- [ ] **Step 1: Write the failing test**

Create `test/features/projects/project_form_dialog_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/projects/project_form_dialog.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_project_form_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp({Project? project}) => ProviderScope(
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
                  onPressed: () => showProjectFormDialog(context, ref, project: project),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('create mode: submitting with a name creates a project', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final projects = await db.select(db.projects).get();
    expect(projects, hasLength(1));
    expect(projects.single.name, 'Website Relaunch');
    expect(projects.single.billable, isTrue);
  });

  testWidgets('create mode: submitting with an empty name does not create a project', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    expect(await db.select(db.projects).get(), isEmpty);
  });

  testWidgets('edit mode: fields are pre-filled from the passed project', (tester) async {
    final project = await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#EF5B5B',
      hourlyRateCents: 9500,
      currency: 'EUR',
    );
    await tester.pumpWidget(makeApp(project: project));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit project'), findsOneWidget);
    expect(find.text('Website Relaunch'), findsOneWidget);
    expect(find.text('95.00'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
  });

  testWidgets('edit mode: submitting updates the existing project rather than creating a new one', (
    tester,
  ) async {
    final project = await db.projectsDao.createProject(name: 'Old Name', colorHex: '#5B8DEF');
    await tester.pumpWidget(makeApp(project: project));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Name');

    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await pumpUntilTrue(tester, () async {
        final rows = await db.select(db.projects).get();
        return rows.length == 1 && rows.single.name == 'New Name';
      });
    });

    final projects = await db.select(db.projects).get();
    expect(projects, hasLength(1));
    expect(projects.single.name, 'New Name');
  });

  testWidgets('entering a non-numeric hourly rate shows an inline error and does not submit', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.enterText(find.byType(TextField).at(1), 'abc');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    expect(find.text('Please enter a valid amount.'), findsWidgets);
    expect(await db.select(db.projects).get(), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/projects/project_form_dialog_test.dart`
Expected: FAIL — `package:hickory/features/projects/project_form_dialog.dart` doesn't
exist.

- [ ] **Step 3: Create the dialog**

Create `lib/features/projects/project_form_dialog.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';

const projectColorPalette = [
  '#5B8DEF',
  '#EF5B5B',
  '#5BEF8D',
  '#EFC75B',
  '#B85BEF',
  '#5BD3EF',
];

/// Parses a user-entered hourly-rate string ("95", "95.50", "95,50") into
/// whole cents. Returns null both for an empty string (no rate set) and for
/// unparseable input -- the submit handler tells the two apart via the raw
/// text itself before deciding whether to show an error.
int? _parseRateCents(String raw) {
  if (raw.isEmpty) return null;
  final value = double.tryParse(raw.replaceAll(',', '.'));
  if (value == null) return null;
  return (value * 100).round();
}

/// Shows the create/edit dialog for a project. Pass [project] to edit an
/// existing one (fields pre-filled, submit calls SyncedWrites.updateProject
/// with only this form's fields); omit it to create a new one (submit calls
/// SyncedWrites.createProject) -- matches the previous standalone "new
/// project" dialog's create behavior exactly. See
/// docs/superpowers/specs/2026-08-04-project-editing-design.md.
Future<void> showProjectFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Project? project,
}) {
  final nameController = TextEditingController(text: project?.name ?? '');
  final initialRateCents = project?.hourlyRateCents;
  final rateController = TextEditingController(
    text: initialRateCents == null ? '' : (initialRateCents / 100).toStringAsFixed(2),
  );
  final currencyController = TextEditingController(text: project?.currency ?? '');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      var selectedColor = project?.colorHex ?? projectColorPalette.first;
      var billable = project?.billable ?? true;
      String? rateError;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(project == null ? l10n.projectsNewProjectTitle : l10n.projectsEditTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(labelText: l10n.projectsNameLabel),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in projectColorPalette)
                        GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = color),
                          child: CircleAvatar(
                            backgroundColor: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                            radius: 14,
                            child: selectedColor == color
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.projectsBillableLabel),
                    value: billable,
                    onChanged: (value) => setDialogState(() => billable = value),
                  ),
                  TextField(
                    controller: rateController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.projectsHourlyRateLabel,
                      errorText: rateError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: currencyController,
                    decoration: InputDecoration(labelText: l10n.projectsCurrencyLabel),
                  ),
                ],
              ),
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
                  final rawRate = rateController.text.trim();
                  final rateCents = _parseRateCents(rawRate);
                  if (rawRate.isNotEmpty && rateCents == null) {
                    setDialogState(() => rateError = l10n.projectsInvalidRateError);
                    return;
                  }
                  final currency = currencyController.text.trim();
                  final writes = await ref.read(syncedWritesProvider.future);
                  if (project == null) {
                    await writes.createProject(
                      name: name,
                      colorHex: selectedColor,
                      billable: billable,
                      hourlyRateCents: rateCents,
                      currency: currency.isEmpty ? null : currency,
                    );
                  } else {
                    await writes.updateProject(
                      project.id,
                      name: Value(name),
                      colorHex: Value(selectedColor),
                      billable: Value(billable),
                      hourlyRateCents: Value(rateCents),
                      currency: Value(currency.isEmpty ? null : currency),
                    );
                  }
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: Text(project == null ? l10n.projectsCreateButton : l10n.commonSave),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    nameController.dispose();
    rateController.dispose();
    currencyController.dispose();
  });
}
```

- [ ] **Step 4: Rewire the Timer screen's "new project" button**

Edit `lib/features/timer/timer_screen.dart`. Find:

```dart
import '../projects/new_project_dialog.dart';
```

Replace it with:

```dart
import '../projects/project_form_dialog.dart';
```

Find:

```dart
                IconButton(
                  tooltip: l10n.timerNewProjectTooltip,
                  onPressed: () => showNewProjectDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
```

Replace it with:

```dart
                IconButton(
                  tooltip: l10n.timerNewProjectTooltip,
                  onPressed: () => showProjectFormDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
```

- [ ] **Step 5: Rewire the Quick Add bar's "new project" button**

Edit `lib/features/entries/quick_add_bar.dart`. Find:

```dart
import '../projects/new_project_dialog.dart';
```

Replace it with:

```dart
import '../projects/project_form_dialog.dart';
```

Find:

```dart
                IconButton(
                  tooltip: l10n.timerNewProjectTooltip,
                  onPressed: () => showNewProjectDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
```

Replace it with:

```dart
                IconButton(
                  tooltip: l10n.timerNewProjectTooltip,
                  onPressed: () => showProjectFormDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
```

- [ ] **Step 6: Delete the old dialog file**

Delete `lib/features/projects/new_project_dialog.dart`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/features/projects/project_form_dialog_test.dart`
Expected: PASS (5 tests)

Run: `flutter test test/features/timer/timer_screen_test.dart test/features/entries/quick_add_bar_test.dart`
Expected: PASS — both files already assert tapping the "New project" tooltip opens a
dialog titled "New project"; that behavior is unchanged.

- [ ] **Step 8: Commit**

```bash
git add lib/features/projects/project_form_dialog.dart lib/features/timer/timer_screen.dart lib/features/entries/quick_add_bar.dart test/features/projects/project_form_dialog_test.dart
git rm lib/features/projects/new_project_dialog.dart
git commit -m "feat(projects): add unified create/edit project dialog"
```

---

### Task 5: Settings project manager (`ProjectsEditor`)

**Files:**
- Modify: `lib/features/projects/projects_providers.dart`
- Create: `lib/features/projects/projects_editor.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/projects/projects_editor_test.dart`

**Interfaces:**
- Consumes: `activeProjectsProvider` (existing), `showProjectFormDialog` (Task 4),
  `SyncedWrites.archiveProject`/`unarchiveProject` (Task 2),
  `AppLocalizations.settingsProjectsTitle`/`settingsProjectsDescription`/
  `settingsProjectsAddLabel`/`settingsProjectsArchivedSection`/
  `settingsProjectsSaveError`/`projectsArchiveTooltip`/`projectsUnarchiveTooltip`
  (Task 3).
- Produces: `archivedProjectsProvider` — `StreamProvider<List<Project>>`. `ProjectsEditor`
  widget (`ConsumerStatefulWidget`, no constructor params beyond `key`), composed into
  `SettingsScreen`.

- [ ] **Step 1: Write the failing test**

Create `test/features/projects/projects_editor_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/projects/projects_editor.dart';
import 'package:hickory/features/projects/projects_providers.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_projects_editor_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // activeProjectsProvider/archivedProjectsProvider are overridden with
  // static streams rather than derived from a real drift database -- see
  // this plan's Global Constraints (avoids a known flutter_test false
  // positive with live drift QueryStreams). Tests that need to see an
  // updated list after a write remount with a fresh override, same
  // technique as quick_add_bar_test.dart.
  Widget makeApp({
    List<Project> active = const [],
    List<Project> archived = const [],
  }) => ProviderScope(
        overrides: [
          activeProjectsProvider.overrideWith((ref) => Stream.value(active)),
          archivedProjectsProvider.overrideWith((ref) => Stream.value(archived)),
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
          home: const Scaffold(body: SingleChildScrollView(child: ProjectsEditor())),
        ),
      );

  Future<Project> seedProject({bool archived = false}) async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    if (archived) await db.projectsDao.archiveProject(project.id);
    return (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
  }

  testWidgets('renders active projects with edit and archive actions', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    expect(find.text('Website Relaunch'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
  });

  testWidgets('archived section is hidden when there are no archived projects', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Archived projects'), findsNothing);
  });

  testWidgets('tapping archive marks the project archived in the database', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.archive_outlined));
      await pumpUntilTrue(tester, () async {
        final row =
            await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
        return row.archived;
      });
    });

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isTrue);
  });

  testWidgets('archived projects render under the collapsible section with a reactivate action', (
    tester,
  ) async {
    final project = await seedProject(archived: true);
    await tester.pumpWidget(makeApp(archived: [project]));
    await tester.pumpAndSettle();

    expect(find.text('Archived projects'), findsOneWidget);
    await tester.tap(find.text('Archived projects'));
    await tester.pumpAndSettle();

    expect(find.text('Website Relaunch'), findsOneWidget);
    expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
  });

  testWidgets('tapping reactivate clears the archived flag in the database', (tester) async {
    final project = await seedProject(archived: true);
    await tester.pumpWidget(makeApp(archived: [project]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived projects'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.unarchive_outlined));
      await pumpUntilTrue(tester, () async {
        final row =
            await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
        return !row.archived;
      });
    });

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isFalse);
  });

  testWidgets('tapping "Add project" opens the create dialog', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
  });

  testWidgets('tapping edit opens the edit dialog pre-filled with the project name', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Edit project'), findsOneWidget);
    expect(find.text('Website Relaunch'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/projects/projects_editor_test.dart`
Expected: FAIL — `archivedProjectsProvider` and
`package:hickory/features/projects/projects_editor.dart` don't exist.

- [ ] **Step 3: Add `archivedProjectsProvider`**

Edit `lib/features/projects/projects_providers.dart`. Find:

```dart
final activeProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(appDatabaseProvider).projectsDao.watchActiveProjects();
});
```

Replace it with:

```dart
final activeProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(appDatabaseProvider).projectsDao.watchActiveProjects();
});

final archivedProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(appDatabaseProvider).projectsDao.watchArchivedProjects();
});
```

- [ ] **Step 4: Create `ProjectsEditor`**

Create `lib/features/projects/projects_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import 'project_form_dialog.dart';
import 'projects_providers.dart';

/// Settings-screen project manager: edit/archive active projects, reactivate
/// archived ones. Lives in the `projects` feature (not `settings/`) since it
/// operates on the cross-cutting Project entity also used by Timer --
/// settings_screen.dart composes it the same way app_shell.dart composes
/// screens from other features. See
/// docs/superpowers/specs/2026-08-04-project-editing-design.md.
class ProjectsEditor extends ConsumerStatefulWidget {
  const ProjectsEditor({super.key});

  @override
  ConsumerState<ProjectsEditor> createState() => _ProjectsEditorState();
}

class _ProjectsEditorState extends ConsumerState<ProjectsEditor> {
  /// True while an archive/reactivate write is in flight -- disables every
  /// action in this editor so a fast double-tap can't fire the write twice.
  bool _busy = false;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save project change: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsProjectsSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.archiveProject(id);
      });

  Future<void> _unarchive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.unarchiveProject(id);
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeProjects = ref.watch(activeProjectsProvider).value ?? const <Project>[];
    final archivedProjects = ref.watch(archivedProjectsProvider).value ?? const <Project>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsProjectsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsProjectsDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final project in activeProjects)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Color(int.parse(project.colorHex.replaceFirst('#', '0xFF'))),
              radius: 8,
              child: const SizedBox.shrink(),
            ),
            title: Text(project.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed:
                      _busy ? null : () => showProjectFormDialog(context, ref, project: project),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  tooltip: l10n.projectsArchiveTooltip,
                  onPressed: _busy ? null : () => _archive(project.id),
                ),
              ],
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsProjectsAddLabel),
          onPressed: _busy ? null : () => showProjectFormDialog(context, ref),
        ),
        if (archivedProjects.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.settingsProjectsArchivedSection),
            children: [
              for (final project in archivedProjects)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Colors.grey,
                    radius: 8,
                    child: SizedBox.shrink(),
                  ),
                  title: Text(
                    project.name,
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.unarchive_outlined),
                    tooltip: l10n.projectsUnarchiveTooltip,
                    onPressed: _busy ? null : () => _unarchive(project.id),
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

- [ ] **Step 5: Wire `ProjectsEditor` into Settings**

Edit `lib/features/settings/settings_screen.dart`. Find:

```dart
import 'break_rule_tiers_editor.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';
```

Replace it with:

```dart
import '../projects/projects_editor.dart';
import 'break_rule_tiers_editor.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';
```

Find:

```dart
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

Replace it with:

```dart
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BreakRuleTiersEditor(),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: ProjectsEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/projects/projects_editor_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 7: Run the full test suite and analyzer to check for regressions**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add lib/features/projects/projects_providers.dart lib/features/projects/projects_editor.dart lib/features/settings/settings_screen.dart test/features/projects/projects_editor_test.dart
git commit -m "feat(settings): add project manager with archive/reactivate"
```
