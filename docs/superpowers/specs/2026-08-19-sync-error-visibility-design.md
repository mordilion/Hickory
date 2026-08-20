# Sync Error Visibility & Automatic Reconciliation — Design

Date: 2026-08-19
Status: Approved for planning

## 1. What already works (verified in code, 2026-08-19)

`JiraSyncService.syncNow()` is a real reconciliation, not fire-and-forget. It walks every
finished entry and compares it against its worklog row, handling all of these:

| Case | Handling |
|---|---|
| New entry with a ticket | `_pushCreate` |
| Entry edited | `entry.updatedAt.isAfter(worklog.syncedAt)` → `_pushUpdate`; the DAO stamps `updatedAt` on every write, so edits are always detected |
| Ticket changed | `_pushMove` — delete on the old ticket, create on the new; a failed delete keeps the old state so the whole move retries instead of losing the old worklog |
| Ticket removed | row goes to `pendingDelete`, worklog deleted from Jira next run |
| Entry deleted locally | survives, because the worklog row deliberately has no FK to the entry |
| Previous failure | row sits on `error` and is retried on the next run |

`status`, `lastError` and `syncedAt` are persisted per entry and synced across the user's own
devices via the event log, so a second device won't duplicate a worklog. `_safeErrorMessage`
strips transport exceptions down before storing, because their `toString()` can embed the
request URI and therefore credentials. Personio mirrors this design.

**Manual create and edit are therefore already covered by the mechanism.** Nothing below
changes that logic; the gaps are all in triggering and surfacing it.

## 2. Gap 1 — `lastError` is written and never read

The column is stored, synced across devices, and displayed nowhere. `_jiraStatusIcon` in
`entries_list.dart` shows a generic "Jira booking failed" tooltip. The reason sits in the
database.

**Fix:** the error tooltip carries the stored message. Keep the generic string as the fallback
for a row whose `lastError` is null (possible: an older row, or a device that received the
state before the message). This is UI-only — the data is already there and already sanitised.

## 3. Gap 2 — nothing triggers reconciliation but a button

`jiraSyncService.syncNow()` is called from exactly one place: the Sync screen's button. There is
no startup trigger, no timer, no hook after an entry is stopped or edited. A user who never
opens the Sync tab never books to Jira — which makes the edit case above effectively dead.

By contrast the file-based device sync *is* automatic (`sync_providers.dart` runs it at startup
and on file-system events), so the app is inconsistent with itself here.

**Design, and the decisions it needs:**

- Trigger at app start, and after an entry is stopped, created or edited. `syncNow()` is
  idempotent, so a redundant run costs API calls but cannot corrupt state.
- **Debounce required.** Editing three entries in a row must not fire three full
  reconciliations; collapse triggers within a few seconds into one run.
- **Silent by default.** An automatic run must not raise dialogs or steal focus. Its outcome
  belongs in the per-entry status the entries list already shows.
- **Skip cleanly when not configured or offline.** No credentials means "do nothing", not an
  error state written to every row. A network failure already lands in `lastError`; it must not
  escalate into a user-facing popup on a background run.
- **Open question for the partner:** how aggressive? Every stop/edit, or only at startup plus a
  periodic interval? Jira Cloud rate limits per account, and a user editing a week of entries
  could otherwise produce a burst. Recommendation: startup plus a debounced trigger on writes,
  no periodic timer.
- **Decided 2026-08-20 (delegated to the implementer): the recommendation, i.e. startup plus a
  debounced trigger on writes, no periodic timer.** Every run then answers a real change, so
  the load on the rate limit stays proportional to what the user did, and there is no second
  scheduling mechanism whose interval has to be reasoned about. The debounce window opens with
  the first trigger and is not extended by later ones, so continuous editing cannot starve the
  run.

## 4. Gap 3 — Personio has no per-entry status in the list

`lib/features/entries/` contains no Personio reference at all. A failed Personio push is visible
only as a number in the Sync tab, and only right after the run.

**Fix:** a second status icon beside the Jira one, driven by the Personio attendance row, with
the same tooltip treatment as §2. Larger than §2 because it needs a provider for the attendance
state by entry id, mirroring `jiraWorklogsByEntryIdProvider`.

## 5. Gap 4 — the Sync tab reports only counts

"3 created, 1 failed" tells the user something is wrong but not what or where.

**Fix:** list the failed entries under the result — description, date, and the stored error —
each tappable to open the entry. Depends on §2 having made the message available in the UI.

## 6. Out of scope

- Any change to the reconciliation logic itself. It is correct; only its triggering and
  reporting are lacking.
- Retry backoff. A failing row already retries on every run, and adding backoff without
  evidence of a rate-limit problem would be speculative.
- Reading worklogs back from Jira. The service is a deliberate one-way push.
