# Project Editing — Design

Date: 2026-08-04
Status: Approved for planning

## 1. Goal & Scope

Projects can currently only be created (`new_project_dialog.dart`), never edited or
archived from the UI — `ProjectsDao.archiveProject` exists but is unused, and there's
no `updateProject` at all. This adds a Settings-based project manager: edit a
project's name, color, billable flag, hourly rate, and currency; archive an active
project; reactivate an archived one.

Out of scope: assigning/editing a project's `clientId` (no client-picker UI exists
anywhere yet — separate future effort), hard-deleting a project (archiving is the only
removal path, consistent with the DAO's existing soft-delete design and the FK from
`TimeEntries`/reports needing archived projects to remain resolvable).

## 2. Data Layer

No schema/migration changes — every field already exists on `Projects`
(`lib/data/drift/tables/projects_table.dart`). Only new DAO/write methods.

### `lib/data/drift/daos/projects_dao.dart`

- `updateProject(String id, {Value<String> name, Value<String> colorHex, Value<bool>
  billable, Value<int?> hourlyRateCents, Value<String?> currency})` — partial update via
  `Value<T>` (each defaults to `Value.absent()`), same shape as
  `TimeEntriesDao.updateEntry`. Sets `updatedAt: Value(DateTime.now().toUtc())`
  unconditionally.
- `unarchiveProject(String id)` — mirrors the existing `archiveProject(String id)`:
  sets `archived: false`, `updatedAt: now`.
- `watchArchivedProjects()` — same shape as `watchActiveProjects()` but
  `where((p) => p.archived.equals(true))`, ordered by name. (`watchAllProjects()`
  already exists for reports' unfiltered need; this is the filtered counterpart the new
  editor needs so it doesn't re-filter a full unfiltered stream client-side.)

### `lib/data/sync/synced_writes.dart`

Three new wrapper methods, each following the existing pattern exactly (call the DAO,
then `logWriter.appendEvent(entityType: EntityTypes.project, entityId: id, op:
EventOp.update, payload: <fresh row>.toJson())`):

- `updateProject(String id, {...same optional Value params as the DAO...})`
- `archiveProject(String id)`
- `unarchiveProject(String id)`

No `SyncIngestor` changes needed: `_applyMaterializedEntity`'s `EntityTypes.project`
case already does insert-or-update from the latest payload regardless of `op`
(confirmed in `sync_ingestor.dart`), so an `EventOp.update` project event is already
handled correctly by existing code.

### `lib/features/projects/projects_providers.dart`

- `archivedProjectsProvider` — plain `StreamProvider<List<Project>>` wrapping
  `watchArchivedProjects()`, same style as the existing `activeProjectsProvider`.

## 3. UI

### `lib/features/projects/project_form_dialog.dart` (new; replaces `new_project_dialog.dart`)

One dialog used for both create and edit:

```dart
Future<void> showProjectFormDialog(BuildContext context, WidgetRef ref, {Project? project})
```

- `project == null` → title `projectsNewProjectTitle`, submit button
  `projectsCreateButton`, fields start empty/default (billable **on**, empty rate,
  empty currency), submit calls `SyncedWrites.createProject`.
- `project != null` → title `projectsEditTitle`, submit button `commonSave`, fields
  pre-filled from `project`, submit calls `SyncedWrites.updateProject` with only the
  fields the form owns (name, colorHex, billable, hourlyRateCents, currency).
- Fields, top to bottom: Name (`TextField`, required — submit is a no-op on empty/
  whitespace-only, same guard as today), color palette (reuses the existing
  `projectColorPalette` `Wrap` of selectable swatches — moved into this file from
  `new_project_dialog.dart`), billable (`SwitchListTile`), hourly rate
  (`TextField`, numeric keyboard, optional — empty means `null`, parsed as whole
  currency units and converted to cents: `(double.parse(text) * 100).round()`),
  currency (`TextField`, optional, short free-text code like "EUR" — matches how
  `reports_screen.dart` already renders it, no validation against an ISO list since
  none exists anywhere else in the app).
- Both callers (`timer_screen.dart`, `quick_add_bar.dart`) switch their `+` button from
  `showNewProjectDialog(context, ref)` to `showProjectFormDialog(context, ref)` (no
  `project` → create mode, identical behavior to today). `new_project_dialog.dart` is
  deleted.

### `lib/features/projects/projects_editor.dart` (new)

`ProjectsEditor extends ConsumerStatefulWidget` — lives in the `projects` feature
folder (not `settings/`), since it operates on the cross-cutting `Project` entity also
used by Timer; `settings_screen.dart` composes it the same way `app_shell.dart`
composes screens from other features.

- Title (`settingsProjectsTitle`) + description (`settingsProjectsDescription`), same
  header style as `BreakRuleTiersEditor`.
- One row per active project (from `activeProjectsProvider`): leading `CircleAvatar`
  in the project's color (same 8px-radius style as `entries_list.dart`'s), title =
  project name, trailing = edit `IconButton` (`Icons.edit_outlined`, opens
  `showProjectFormDialog(context, ref, project: project)`) + archive `IconButton`
  (`Icons.archive_outlined`, tooltip `projectsArchiveTooltip`, calls
  `SyncedWrites.archiveProject`).
- `ActionChip` "Add project" (`Icons.add`, label `settingsProjectsAddLabel`) below the
  list, opens `showProjectFormDialog(context, ref)`.
- Collapsible `ExpansionTile` "Archived projects"
  (`settingsProjectsArchivedSection`), only rendered when `archivedProjectsProvider`
  has at least one row. Each row: greyed-out `CircleAvatar` + name + trailing
  reactivate `IconButton` (`Icons.unarchive_outlined`, tooltip
  `projectsUnarchiveTooltip`, calls `SyncedWrites.unarchiveProject`). No edit action on
  archived rows — reactivate first, then edit from the active list.
- Same `_busy` guard + try/catch-with-snackbar pattern as `BreakRuleTiersEditor`
  (`settingsProjectsSaveError` message), so a double-tap on archive/reactivate can't
  race, and a write failure surfaces instead of silently doing nothing.

### `lib/features/settings/settings_screen.dart`

New `Card(child: Padding(..., child: ProjectsEditor()))`, appended after the existing
`BreakRuleTiersEditor` card (purely additive placement, no reordering of existing
cards).

## 4. i18n

New ARB keys (added to all 6 locale files — `test/l10n/arb_completeness_test.dart`
already enforces parity):

`projectsEditTitle`, `projectsBillableLabel`, `projectsHourlyRateLabel`,
`projectsCurrencyLabel`, `projectsArchiveTooltip`, `projectsUnarchiveTooltip`,
`settingsProjectsTitle`, `settingsProjectsDescription`, `settingsProjectsAddLabel`,
`settingsProjectsArchivedSection`, `settingsProjectsSaveError`.

Existing keys reused as-is: `projectsNewProjectTitle`, `projectsNameLabel`,
`projectsCreateButton`, `commonSave`, `commonCancel`.

## 5. Testing

- `test/data/drift/projects_dao_test.dart` (new): `updateProject` partial-update
  semantics (each field independently, absent fields untouched), `archiveProject` /
  `unarchiveProject` round-trip, `watchArchivedProjects()` filtering.
- `test/data/synced_writes_jira_test.dart`-style addition (or a new
  `test/data/synced_writes_projects_test.dart`): each new `SyncedWrites` method writes
  the row and appends the expected log event.
- `test/features/projects/project_form_dialog_test.dart` (new): create mode submits
  `createProject` with entered values; edit mode pre-fills fields from the passed
  `Project` and submits `updateProject` with only the changed shape; empty-name guard
  blocks submit in both modes.
- `test/features/projects/projects_editor_test.dart` (new, mirrors
  `break_rule_tiers_editor_test.dart`): active projects render with edit+archive
  actions; archiving moves a project into the archived section; reactivating moves it
  back; archived section is hidden when empty.

## 6. Out of Scope

Client (`clientId`) assignment UI, hard delete, bulk actions, reordering/sorting
projects manually (list stays name-sorted, matching `watchActiveProjects()`'s existing
order).
