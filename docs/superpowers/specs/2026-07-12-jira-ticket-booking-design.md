# Jira Ticket Booking — Design

Date: 2026-07-12
Status: Approved for planning

## 1. Goal & Scope

Allow a time entry to be optionally linked to a Jira ticket (issue key), independent of
the entry's local project. A manual "sync to Jira" action (added to the existing Sync
screen) pushes linked, finished entries to Jira as worklogs. Later edits or deletion of
an already-synced entry are reconciled into Jira on the next sync.

This is a one-way push integration: Hickory never reads existing worklogs back from
Jira, and never displays Jira issue metadata beyond the key the user entered/selected.

## 2. Data Model

### `TimeEntries` table
- New nullable column `jiraTicketKey` (text). Schema migration `schemaVersion` 3 → 4.

### New `JiraWorklogs` table (1:1 with a time entry)
Tracks the Jira sync state for an entry, separately from the entry itself so the
tracking row can outlive the entry (needed to push a delete after the entry is gone).

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | Same value as the time entry's id. Plain column, no cascading FK — must survive deletion of the `TimeEntries` row. |
| `syncedTicketKey` | text, nullable | Issue key the worklog currently exists under in Jira. Null until first successful push. |
| `jiraWorklogId` | text, nullable | Jira-assigned worklog id. Null until first successful push. |
| `status` | text | One of `pending`, `synced`, `error`, `pendingDelete`. |
| `lastError` | text, nullable | Last error message, for display. Never contains tokens/secrets. |
| `syncedAt` | datetime, nullable | Timestamp of the last successful push. Compared against the entry's `updatedAt` to decide whether a re-push is needed. |

### Cross-device sync
`JiraWorklogs` rows are synced across the user's own devices via the existing
event-log mechanism (same pattern as `Projects`, `TimeEntries`, etc.): a new
`EntityTypes.jiraWorklog` constant, a `SyncedWrites` method to write it, and a new
case in `SyncIngestor._applyMaterializedEntity`.

This is required for correctness: without it, a second device wouldn't know an entry
was already pushed to Jira from the first device, and would create a duplicate worklog
on its own next sync.

### Credentials are not synced
Jira base URL, account email, and API token are stored in `flutter_secure_storage`,
per device, and are never written to the event log or the synced database. This
follows the project's security rules (secrets must not be stored in plaintext/synced
storage). Each device needs its Jira credentials configured once, locally.

## 3. Jira API Client

New dependencies: `http` (REST calls) and `flutter_secure_storage` (credential
storage).

Auth: HTTP Basic with `email:apiToken`, the standard scheme for Jira Cloud API tokens.

Endpoints used (REST API v2 — chosen over v3 so the worklog `comment` field can stay a
plain string instead of Atlassian Document Format JSON):
- `POST /rest/api/2/issue/{key}/worklog` — create
- `PUT /rest/api/2/issue/{key}/worklog/{id}` — update
- `DELETE /rest/api/2/issue/{key}/worklog/{id}` — delete
- `GET /rest/api/2/issue/picker?query=...` — issue search, used for the ticket
  autocomplete field

## 4. Sync Algorithm

Triggered manually by the "Sync to Jira" button. For every finished entry
(`endAt != null`), reconcile against its `JiraWorklogs` row (if any):

1. `jiraTicketKey` is null, but a `JiraWorklogs` row exists → the ticket was removed
   locally. If the row has a `jiraWorklogId`, mark it `pendingDelete`; otherwise (never
   pushed yet) delete the tracking row directly.
2. `jiraTicketKey` is set, no tracking row exists → create one (`status = pending`),
   then `POST` a new worklog (`timeSpentSeconds` = worked duration excluding pauses,
   `started` = `startAt`, `comment` = `description`). On success, store
   `jiraWorklogId`, `syncedTicketKey`, `syncedAt`, set `status = synced`. On failure,
   set `status = error` and `lastError`.
3. A tracking row exists and `syncedTicketKey != jiraTicketKey` → the ticket changed.
   Delete the old worklog (if `jiraWorklogId` is set) and create a new one on the new
   ticket, same as case 2.
4. A tracking row exists, ticket unchanged, and `entry.updatedAt > syncedAt` (or
   `syncedAt` is null) → `PUT` an update with the current duration/start/comment.
5. Otherwise → already in sync, skip.

### Local deletion (`SyncedWrites.deleteEntry`)
Before removing the `TimeEntries` row:
- No `JiraWorklogs` row → nothing to do.
- Row exists but `jiraWorklogId` is null (never pushed) → delete the tracking row too.
- Row exists with a `jiraWorklogId` → set `status = pendingDelete`, keep the row. The
  next sync deletes the Jira worklog and only then removes the tracking row.

## 5. UI

- **Timer start card & manual entry dialog**: new ticket field with autocomplete,
  built on Flutter's built-in `Autocomplete`/`RawAutocomplete` widget (no extra
  package), debounced against `/issue/picker`. Manual typing remains a fallback (with
  a light client-side format check, e.g. `KEY-123`) when Jira isn't reachable or
  configured — the field must never block entry creation.
- **Entries list**: a small status indicator next to the ticket key badge
  (synced / pending / error), consistent with the existing project-name `Chip`.
- **Sync screen**: new "Jira Integration" card — base URL, email, API token fields,
  a "Test connection" action, the "Sync to Jira" button, and a result summary
  (created/updated/deleted/failed counts) after each run.

## 6. Error Handling

Per-entry failures (ticket doesn't exist, auth expired, network error, etc.) are
recorded on the `JiraWorklogs` row (`status = error`, `lastError`) and surfaced in the
entries list; they're retried automatically on the next manual sync. Error messages
are generic/safe — no tokens or full request/response bodies are logged or displayed.

## 7. Localization

All new user-facing strings go through ARB files for all six existing locales
(de, en, es, fr, it, nl), following the project's established i18n pattern.

## 8. Out of Scope (v1)

- Reading back existing Jira worklogs.
- Displaying Jira issue metadata (title, status) beyond the key.
- Jira ticket key in reports or CSV export.
- OAuth authentication (API token only).
