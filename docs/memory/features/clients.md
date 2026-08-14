# Client Management

## Entities

- `Clients` table (`lib/data/drift/tables/clients_table.dart`): `id`, `name`, `archived`, `createdAt`, `updatedAt`. Predates this feature in the schema (was already in `AppDatabase`'s `tables:` list, unused) — no migration was needed to add it.
- `Projects.clientId` (nullable FK to `Clients`): the only link between a project and a client. No other table references `Clients`.
- Sync entity type: `EntityTypes.client` (`lib/data/sync/entity_types.dart`) — also predated this feature as a reserved constant.

## Architecture

Every layer mirrors the pre-existing `Projects` CRUD stack exactly: `ClientsDao` ↔ `ProjectsDao`, `SyncedWrites.createClient/updateClient/archiveClient/unarchiveClient/deleteClient` ↔ the Project equivalents, `ClientsEditor` ↔ `ProjectsEditor`, `ClientsSettingsScreen` ↔ `ProjectsSettingsScreen`. See `docs/superpowers/specs/2026-08-13-client-management-design.md` and `docs/superpowers/plans/2026-08-13-client-management.md` for the full design/implementation record.

- `SyncIngestor._applyMaterializedEntity`'s `EntityTypes.client` case and `rebuildFromScratch()`'s `db.delete(db.clients)` — added in this feature; `EntityTypes.tag` is still on the unhandled `default:` fallback (Tags is a separate, not-yet-built feature).
- `ClientHasProjectsException` (in `synced_writes.dart`, mirrors `ProjectHasTimeEntriesException`): blocks deleting a client that any project still references. `ProjectsDao.hasProjectsForClient` matches **both active and archived** projects, not just active ones — a client whose only projects are all archived still can't be deleted, and the error message doesn't distinguish this (a known, accepted UX rough edge, not a bug).

## Gotchas

- **A project's client picker must be able to display an archived client.** If a project's assigned client gets archived, the picker (`project_form_dialog.dart`) reads its item list from `activeClientsProvider` only — without special handling, an archived-but-assigned client would show as "No client" while the project's `clientId` still silently holds the archived id, so saving *any* unrelated change (e.g. just the color) would re-save the stale id with no visible sign anything happened. Fixed by also watching `archivedClientsProvider` and including the currently-assigned client (labeled "(archived)") in the dropdown items if it's not in the active list. Any future picker/selector for clients should do the same.
- **`TextEditingController` disposal in a `showDialog` body must go through `State.dispose()`, not `.whenComplete()` on the `showDialog` future.** The future resolves at `Navigator.pop()`, before the dialog's exit transition finishes rendering — disposing a controller in `.whenComplete()` can race a still-mounted `TextField` during those last frames ("used after dispose"). Both `client_form_dialog.dart` and `project_form_dialog.dart` are `StatefulWidget`s specifically for this reason. Any new dialog with a `TextEditingController` should follow the same pattern.
- **`DropdownButtonFormField`'s `initialValue` isn't always re-read on rebuild.** The installed Flutter SDK's own `didUpdateWidget` resyncs it when `initialValue` actually *changes* — but the client picker's inline "create new client" flow can resolve to *no change* (user cancels), in which case the framework's own resync is a no-op and the dropdown visually sticks on the wrong item. `project_form_dialog.dart` works around this with a `clientPickerGeneration` counter folded into the dropdown's `key: ValueKey(...)`, incremented unconditionally every time the inline-create flow resolves (success or cancel), forcing a fresh `State` (and therefore a fresh `initialValue` read) either way.
- **No FK enforcement (`PRAGMA foreign_keys` is never set).** A client deleted on one device while a project pointing at it was created offline on another can leave a dangling `clientId` after sync merge — nothing crashes, but nothing cleans it up either. Not addressed; flagged for whoever builds CSV import next, since that's the next feature that will touch client/project linkage at scale.
- l10n keys follow the existing `settingsProjects*`/`projects*` naming split exactly: `settingsClients*` for the Settings category/editor strings, `clients*` for the create/edit dialog and list-row action strings, `projectsClient*` for the picker strings living inside `project_form_dialog.dart`. `app_de.arb` is the actual l10n template (`l10n.yaml`), not `app_en.arb` — new keys must be written as real translations in all six locale files, not just English.

## Out of scope (intentionally, per the design spec)

- Client name is not shown in Reports or CSV export.
- Client name is not shown in `ProjectsEditor`'s project list.
- Tags (`Tags`/`TimeEntryTags` tables) — separate future feature, still unwired.
