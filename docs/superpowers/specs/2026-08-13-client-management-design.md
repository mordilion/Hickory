# Client Management — Design

Date: 2026-08-13
Status: Approved for planning

## 1. Goal & Scope

`Clients` (`lib/data/drift/tables/clients_table.dart`) and `Projects.clientId`
already exist in the schema, but nothing reads or writes them: no DAO, no
`SyncedWrites` methods, no `SyncIngestor` handling beyond the explicit "not wired
up yet" fallback, and no UI anywhere (confirmed by grep — `Clients` only appears in
`database.dart` and the table file itself). This is the first part of the roadmap's
v1.3 "Migration" theme (see `ROADMAP.md`): CSV import needs a real client concept to
map onto, and this spec builds that concept as a standalone, independently useful
feature before import touches it.

Scope: full CRUD for clients (create, rename, archive, reactivate, delete-if-unused),
and assigning a client to a project. Tags are a separate, later spec (they touch
`TimeEntries`' sync payload, not just a new independent entity, so they're kept out
of this one). Reports/CSV export changes are explicitly deferred — this spec only
makes clients assignable, not visible in exports yet.

## 2. Data Layer

No schema/migration changes — `Clients` and `Projects.clientId` already exist. Only
new DAO/write/ingest code.

### `lib/data/drift/daos/clients_dao.dart` (new)

Mirrors `ProjectsDao` exactly:

- `watchActiveClients()` — `where((c) => c.archived.equals(false))`, ordered by name.
- `watchArchivedClients()` — inverse filter, same ordering.
- `createClient({required String name})` — generates a uuid, sets
  `createdAt`/`updatedAt` to `DateTime.now().toUtc()`, returns the inserted row.
- `updateClient(String id, {Value<String> name, Value<bool> archived})` — partial
  update, same `Value<T>` shape as `ProjectsDao.updateProject`.
- `archiveClient(String id)` / `unarchiveClient(String id)` — same shape as
  `ProjectsDao.archiveProject`/`unarchiveProject`.
- `deleteClient(String id)` — same shape as `ProjectsDao.deleteProject`.

### `lib/data/drift/daos/projects_dao.dart`

One new method: `Future<bool> hasProjectsForClient(String clientId)` — mirrors
`TimeEntriesDao.hasEntriesForProject`, used by the delete guard below.

### `lib/data/sync/synced_writes.dart`

New methods, following the existing project-mutation pattern exactly (write via the
DAO, then log the fresh row):

- `createClient({required String name})` — logs `EventOp.create` with the new row's
  `toJson()`, mirrors `createProject`.
- `updateClient(String id, {Value<String> name, Value<bool> archived})`,
  `archiveClient(String id)`, `unarchiveClient(String id)` — each calls the DAO then
  a new `_logCurrentClientState(id)` helper (mirrors `_logCurrentProjectState`).
- `deleteClient(String id)` — calls `db.projectsDao.hasProjectsForClient(id)` first;
  throws `ClientHasProjectsException` (new, same shape as
  `ProjectHasTimeEntriesException`) if true; otherwise deletes and appends an
  `EventOp.delete` event with `payload: null`.

### `lib/data/sync/sync_ingestor.dart`

Replace the `EntityTypes.client` share of the current `default` fallback (the
"Client/Tag aren't wired into the app yet" branch) with a real case, same shape as
`EntityTypes.project`: delete on `entity.isDeleted`, else
`insertOnConflictUpdate(Client.fromJson(entity.payload!).toCompanion(true))`.
`EntityTypes.tag` stays on the fallback path until the Tags spec. Add
`db.delete(db.clients)` to `rebuildFromScratch()`'s transaction, alongside the
existing table deletes.

### `lib/features/clients/clients_providers.dart` (new)

`activeClientsProvider` / `archivedClientsProvider` — plain
`StreamProvider<List<Client>>`, same style as `projects_providers.dart`.

## 3. UI

### `lib/features/clients/client_form_dialog.dart` (new)

```dart
Future<void> showClientFormDialog(BuildContext context, WidgetRef ref, {Client? client})
```

One dialog for both create and edit, structurally the same as
`project_form_dialog.dart` but with a single field: Name (`TextField`, required,
autofocus — submit is a no-op on empty/whitespace-only). `client == null` → title
`clientsNewClientTitle`, button `clientsCreateButton`, calls
`SyncedWrites.createClient`. `client != null` → title `clientsEditTitle`, button
`commonSave`, calls `SyncedWrites.updateClient` with just the name.

### `lib/features/clients/clients_editor.dart` (new)

`ClientsEditor extends ConsumerStatefulWidget`, 1:1 structure of
`projects_editor.dart`: title + description header, one `ListTile` per active
client (name only, no color swatch — `Clients` has none) with edit + archive +
delete `IconButton`s, `ActionChip` "Add client" below, collapsible "Archived
clients" `ExpansionTile` (reactivate + delete actions, hidden when empty). Same
`_busy` guard / try-catch-with-snackbar pattern, catching `ClientHasProjectsException`
on delete (message: `clientsDeleteHasProjectsError`) the same way
`ProjectsEditor._delete` catches `ProjectHasTimeEntriesException`. Delete
confirmation dialog reused in the same shape as `ProjectsEditor._delete`'s.

### `lib/features/settings/clients_settings_screen.dart` (new)

Same one-line wrapper as `projects_settings_screen.dart`: `SettingsSubPage` → `Card`
→ `Padding` → `ClientsEditor`.

### `lib/features/settings/settings_home_screen.dart`

New `ListTile` (icon `Icons.business_outlined`, title `clientsTitle`) inserted
directly after the existing "Projects" row, same `Divider` + `MaterialPageRoute`
push pattern as its neighbors.

### `lib/features/projects/project_form_dialog.dart`

Add a client picker between the Name field and the color palette:

- `DropdownButtonFormField<String?>` (label `projectsClientLabel`), items built from
  `activeClientsProvider` plus a leading "No client" entry (`projectsClientNone`,
  value `null`) and a trailing "+ New client…" entry
  (`projectsClientCreateNew`, a sentinel value distinct from any real client id).
- Selecting the sentinel opens `showClientFormDialog` inline (awaited); on success,
  the dialog re-reads `activeClientsProvider`'s latest value for the just-created
  client (matched by name, since `createClient` doesn't return through this call
  site directly — simplest correct option: `showClientFormDialog` is given an
  `onCreated: (Client) => ...` callback instead of relying on provider timing) and
  sets it as the selected value; cancelling leaves the previous selection untouched.
- Submit passes the selected client id (or `null`) into `SyncedWrites.createProject`
  / `updateProject`'s existing `clientId` parameter (already present on
  `createProject`, needs adding to `updateProject`'s signature and DAO method — both
  currently omit it).

## 4. i18n

New ARB keys (all 6 locale files; `test/l10n/arb_completeness_test.dart` enforces
parity):

`clientsTitle`, `clientsNameLabel`, `clientsNewClientTitle`, `clientsEditTitle`,
`clientsCreateButton`, `clientsAddLabel`, `clientsArchiveTooltip`,
`clientsUnarchiveTooltip`, `clientsDeleteTooltip`, `clientsDeleteConfirmTitle`,
`clientsDeleteConfirmMessage`, `clientsDeleteHasProjectsError`,
`clientsArchivedSection`, `clientsSaveError`, `projectsClientLabel`,
`projectsClientNone`, `projectsClientCreateNew`.

Existing keys reused as-is: `commonSave`, `commonCancel`, `commonDelete`.

## 5. Testing

- `test/data/drift/clients_dao_test.dart` (new): create/update/archive/unarchive/
  delete round-trips, active/archived stream filtering — mirrors
  `projects_dao_test.dart`.
- `test/data/drift/projects_dao_test.dart`: add coverage for
  `hasProjectsForClient` (true/false cases) and `clientId` now flowing through
  `updateProject`.
- `test/data/synced_writes_client_test.dart` (new): each `SyncedWrites` client
  method writes the row and appends the expected log event;
  `deleteClient` throws `ClientHasProjectsException` when a project still
  references the client and succeeds otherwise.
- `test/data/sync_ingestor_test.dart` (or equivalent existing ingestor test file):
  add a case asserting `client` events materialize into the `clients` table, and
  that `rebuildFromScratch()` clears it.
- `test/features/clients/client_form_dialog_test.dart` and
  `clients_editor_test.dart` (new, mirror the Projects equivalents once those exist
  from the same prior spec).
- `test/features/projects/project_form_dialog_test.dart`: extend for the new client
  picker — selecting an existing client sets `clientId`; the inline-create path
  creates a client and selects it; "No client" submits `clientId: null`.

## 6. Out of Scope

Showing a project's client name in `ProjectsEditor`'s list or anywhere in
reports/CSV export (both explicitly deferred per the earlier discussion — separate
future work), Tags (own spec next), hard-coding a fixed client/project hierarchy
depth (a client only ever groups projects, one level).
