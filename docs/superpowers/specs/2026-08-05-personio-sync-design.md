# Personio Sync — Design

Date: 2026-08-05
Status: Approved for planning

## 1. Goal & Scope

Let the user manually push finished time entries to Personio as attendance periods,
via a "Personio Integration" section in the Sync screen — mirroring the existing
Jira worklog integration's architecture (credentials store → API client → sync
service → synced tracking table → Settings UI), but with a different trigger model:
a manual, date-range-scoped push button rather than Jira's "sync everything with a
ticket key" reconciliation.

Out of scope (explicit decisions from brainstorming):
- No per-entry opt-in field (unlike Jira's `jiraTicketKey`) — every finished entry
  whose date falls in the selected push range is a candidate.
- No mapping between Hickory projects and Personio projects — the Personio
  `project` field is simply omitted from every request.
- No `BREAK`-type attendance periods — only `WORK` periods are pushed; a time
  entry's internal pause time (`totalPausedSeconds`) is not represented in
  Personio at all in this iteration.
- No employee-lookup via the Personio Employees API — the user's own Personio
  person/employee ID is entered manually alongside the API credentials (avoids the
  Employees endpoint's attribute-whitelisting setup step for a single-user need).
- No absence/vacation pull from Personio (a separate, later effort if ever picked
  up).

## 2. Personio API (v2)

**Source note:** v1 Attendance endpoints are deprecated (final deprecation
2026-08-30) — this design targets v2 exclusively. Verified against
developer.personio.de: auth flow, endpoint paths/methods, top-level request fields,
and response status codes. The exact nested JSON shape of the `person`/`start`/
`end` request objects could not be fully extracted from Personio's interactive
docs (client-rendered schema widgets) — `[inferred]` as the OAuth2/REST-conventional
shape below; per explicit instruction, this is **not** verified against a live call
before planning. The implementation's first "Test connection" against a real
account is what actually confirms/corrects it — same role Jira's test-connection
button already plays for that integration.

- **Auth** `[verified]`: `POST https://api.personio.de/v2/auth/token`,
  `application/x-www-form-urlencoded` body `grant_type=client_credentials&client_id=...&client_secret=...`.
  Returns a bearer access token (standard OAuth2 client-credentials response shape:
  `access_token`, `token_type`, `expires_in`). Must be cached and re-obtained when
  expired (or about to expire) — new territory for this codebase; Jira's client
  uses stateless Basic auth per request instead.
- **Create attendance period** `[verified endpoint/fields, inferred nesting]`:
  `POST https://api.personio.de/v2/attendance-periods?skip_approval=true`, Bearer
  auth. Body: `person` (object, required — reference to the Personio employee by
  id), `type` (`"WORK"` | `"BREAK"`, required — always `"WORK"` here), `start`
  (object, required), `end` (object | null), `comment` (string, optional),
  `project` (object, optional — omitted entirely per Section 1). Returns 201 with
  the new period's id. `skip_approval=true` per the confirmed product decision —
  pushed periods are immediately final, no manager approval step.
- **Update / delete attendance period** `[inferred, by REST convention]`: `PATCH`
  and `DELETE` on `/v2/attendance-periods/{id}`, same auth and body shape as
  create for `PATCH`. Mirrors Jira's `updateWorklog`/`deleteWorklog` shape.
  `DELETE` on an already-gone period should be treated as success, same reasoning
  as `JiraClient.deleteWorklog`'s 404-is-success handling.
- **Errors**: 400 (invalid request), 403 (forbidden / update-limit reached), 422
  (unprocessable, e.g. start after end). All non-2xx responses raise
  `PersonioApiException` with a caller-safe message (status code only — never the
  raw response body, which could echo back request content).

## 3. Data Model

### New `PersonioAttendances` table (synced entity, same shape as `JiraWorklogs`)

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | Same id as the `TimeEntry` it tracks (1:1). No FK — must outlive its entry so a delete can still be pushed after the entry is gone locally, exactly like `JiraWorklogs`. |
| `personioAttendanceId` | text, nullable | Personio-assigned period id; null until the first successful push. |
| `status` | text | `pending` \| `synced` \| `error` \| `pendingDelete`, default `pending` — same enum shape as `JiraWorklogStatus`. |
| `lastError` | text, nullable | Caller-safe error message from the last failed push. |
| `syncedAt` | datetime, nullable | |

Synced across the user's own devices via the event log (`EntityTypes.personioAttendance`) — otherwise a second device wouldn't know an entry was already pushed and would create a duplicate attendance period on its own next push.

Migration: next `schemaVersion` bump, `onUpgrade` adds `m.createTable(personioAttendances)`, following the exact pattern of every prior migration step. `SyncIngestor._resetLocalCache`-equivalent full-reset path also gets `db.delete(db.personioAttendances)`, alongside the existing `jiraWorklogs` line.

Sync wiring follows the exact existing pattern:
- `lib/data/drift/tables/personio_attendances_table.dart`, `lib/data/drift/daos/personio_attendances_dao.dart` (`watchAll()`, `getAll()`, `getForEntry(String)`, `upsert(Insertable<PersonioAttendanceRow>)`, `deleteForEntry(String)` — identical surface to `JiraWorklogsDao`).
- `EntityTypes.personioAttendance = 'personio_attendance'`.
- `SyncedWrites.upsertPersonioAttendanceState(...)`, `SyncedWrites.deletePersonioAttendanceState(...)` (mirrors `upsertJiraWorklogState`/`deleteJiraWorklogState`).
- `SyncedWrites.deleteEntry` gains a second lookup/pendingDelete block for `PersonioAttendances`, right alongside the existing Jira one — same two-branch logic (pushed → `pendingDelete`; never pushed → delete tracking row outright).
- `SyncIngestor._applyMaterializedEntity` gains an `EntityTypes.personioAttendance` case — insert-or-update on non-delete, row delete on delete, identical shape to the existing `EntityTypes.jiraWorklog` case.

### Entry → attendance mapping

One finished `TimeEntry` (`endAt != null`) maps to at most one Personio `WORK`
attendance period. `start` = `entry.startAt`, `end` = `entry.endAt` (the entry's
wall-clock span, not adjusted for `totalPausedSeconds` — see Section 1's
out-of-scope note). `comment` = `entry.description` (mirrors
`JiraSyncService`'s use of the description as the worklog comment).

## 4. `PersonioSyncService`

```dart
class PersonioSyncService {
  Future<PersonioSyncResult> pushRange({required DateTime from, required DateTime to});
}
```

`from`/`to` are inclusive local calendar days (the Sync screen's date pickers).
Structurally mirrors `JiraSyncService.syncNow`, split into the same two passes:

1. **Pending deletes — unconditional, not date-filtered.** Every
   `PersonioAttendances` row with `status == pendingDelete` is reconciled
   regardless of the selected range — otherwise an entry deleted outside the
   currently-selected range would leave its Personio-side period orphaned forever.
   Same delete-then-clear-tracking-row logic as
   `JiraSyncService._reconcilePendingDelete`.
2. **Creates and updates — date-filtered.** Only finished `TimeEntry` rows whose
   `startAt` (local date) falls within `[from, to]` are considered. For each:
   - No existing `PersonioAttendances` row, or one with no
     `personioAttendanceId` yet (a previous create failed) → `POST` create.
   - Existing row with a `personioAttendanceId`, and
     `entry.updatedAt.isAfter(row.syncedAt)` → `PATCH` update.
   - Otherwise → skip (already up to date).

Returns `PersonioSyncResult(created, updated, deleted, failed)` — same shape as
`JiraSyncResult`.

### Default push range

The Sync screen defaults the "from" date to the day after the latest `startAt`
date among `PersonioAttendances` rows with `status == synced` (computed live from
the DAO — no separate "last pushed" setting to keep in sync), and "to" to today.
First-ever push (no synced rows yet) defaults "from" to today. The user can widen
or narrow the range before pushing; the default is a convenience, not an
enforced boundary.

## 5. Credentials & Client

### `PersonioCredentials` / `PersonioCredentialsStore` / `SecurePersonioCredentialsStore`

Exact structural mirror of `JiraCredentials`/`JiraCredentialsStore`/
`SecureJiraCredentialsStore`: `{clientId, clientSecret, employeeId}`, device-local
only via `flutter_secure_storage` (never synced — same reasoning as Jira's
credentials-not-synced rule).

### `PersonioClient` (interface) / `HttpPersonioClient`

```dart
abstract class PersonioClient {
  Future<bool> testConnection();
  Future<String> createAttendance({required DateTime start, required DateTime end, String? comment});
  Future<void> updateAttendance({required String periodId, required DateTime start, required DateTime end, String? comment});
  Future<void> deleteAttendance({required String periodId});
}
```

`PersonioApiException` mirrors `JiraApiException` (message-only, caller-safe).
`HttpPersonioClient` additionally owns OAuth2 token lifecycle: an in-memory
`{accessToken, expiresAt}` cache, re-authenticating via the `/v2/auth/token`
endpoint when no cached token exists or the cached one is within a small safety
margin (e.g. 30s) of `expiresAt`. `testConnection()` performs a token fetch and
reports success/failure the same way `HttpJiraClient.testConnection()` does (never
throws for an auth failure, only for transport-level errors).

## 6. UI

### Sync screen — new "Personio Integration" section

New `Card` in `sync_screen.dart`, structurally mirroring the existing Jira card:
- Fields: Client ID, Client Secret (obscured), Employee/Person ID.
- "Save credentials" / "Test connection" buttons — identical behavior shape to
  the Jira ones (`_saveJiraCredentials`/`_testJiraConnection`).
- Below that: two date fields ("From" / "To"), pre-filled per Section 4's default
  range each time the screen loads, and a "Push" button. Pushing calls
  `PersonioSyncService.pushRange(from: ..., to: ...)` and shows the result as text
  (created/updated/deleted/failed counts), same presentation as
  `syncJiraSyncResult`.

### Riverpod

`lib/core/di/personio_providers.dart`, structurally mirroring `jira_providers.dart`:
`personioCredentialsStoreProvider`, `personioCredentialsProvider`,
`personioClientProvider` (null until configured), `personioSyncServiceProvider`
(null until configured). Plain providers throughout (not `@riverpod` codegen) per
the repo's existing rule for providers touching drift-generated row types.

## 7. Testing

- `personio_attendances_dao_test.dart`: same shape as `jira_worklogs_dao_test.dart`.
- `http_personio_client_test.dart`: mocked `http.Client`, covering token
  acquisition/caching/re-auth-on-expiry, create/update/delete request shape, and
  error mapping — mirrors `http_jira_client_test.dart`'s structure, plus the new
  token-lifecycle cases Jira's client doesn't have.
- `personio_sync_service_test.dart`: fake `PersonioClient`, covering the two-pass
  reconcile logic (unconditional pending-delete, date-filtered create/update/skip)
  — mirrors `jira_sync_service_test.dart`.
- `sync_round_trip_test.dart`: new case for `EntityTypes.personioAttendance`,
  same shape as the existing Jira/break-rule-tier cases.
- Sync screen widget test additions for the new card (credentials save/test,
  push button triggers `pushRange` with the currently-shown date range).

## 8. Out of Scope

Absence/vacation pull from Personio; project mapping; `BREAK`-period push;
per-entry opt-in; employee lookup via the Personio Employees API; automatic/
background sync (push is always a manual, explicit user action).
