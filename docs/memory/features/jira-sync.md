# Jira Sync (booking worklogs)

## Entities

- `JiraWorklogs` (`lib/data/drift/tables/jira_worklogs_table.dart`) — 1:1 with a time entry,
  keyed by the entry's own id, deliberately **without** an FK to `TimeEntries` so the row can
  outlive its entry and still push the delete. Synced across devices via the event log.

## Architecture

- `JiraSyncService.syncNow()` (`lib/features/jira/jira_sync_service.dart`) is a full
  reconciliation, not fire-and-forget: it walks every finished entry against its worklog row
  and derives create / update / move / delete. Idempotent, and a one-way push — worklogs are
  never read back from Jira.
- Triggering lives entirely outside the service, in `jiraAutoSyncProvider`
  (`lib/core/di/jira_providers.dart`): one run at app start plus a debounced run after every
  time-entry write, coalesced by `AutoSyncTrigger` (`lib/data/sync/auto_sync_trigger.dart`).
  The Sync screen's button calls `syncNow()` directly, bypassing the trigger, because it is the
  one place an outcome is reported to the user.
- `AutoSyncTrigger` is provider-agnostic (no Riverpod, no Jira) so Personio can adopt it.

## Decisions

- **No periodic timer.** Every automatic run answers a real change, which keeps the load on
  Jira Cloud's per-account rate limit proportional to what the user did and avoids a second
  scheduling mechanism. Decided 2026-08-20; see
  docs/superpowers/specs/2026-08-19-sync-error-visibility-design.md §3.
- **The debounce window opens with the first trigger and is not extended by later ones.** A
  restarting window would let continuous editing starve the run forever; this way a change is
  always reconciled within the window of the first trigger that saw it.
- **A trigger raised while a run is in flight is remembered, not dropped**, because that run may
  already have read its entries before the change landed. Runs never overlap.
- **Background runs are silent, including on failure.** Their outcome is the per-entry status
  icon in the entries list; `syncNow` records per-row errors itself. `AutoSyncTrigger` therefore
  swallows the exception rather than letting it surface.
- **No credentials means skip, not error.** `jiraSyncServiceProvider` resolves to null while
  Jira is unconfigured and the trigger returns without touching a row.
- **Error text is stored sanitised, not sanitised at display time.** `_safeErrorMessage` reduces
  a transport exception to a fixed string before it is written, because `lastError` is synced to
  every device and a raw `toString()` can embed the request URI — and therefore credentials.

## Gotchas

- **The trigger is activated by `ref.watch(jiraAutoSyncProvider)` in `TimerScreen`**, next to
  `syncWatcherProvider`. That works only because `AppShell` uses an `IndexedStack`, so the timer
  tab stays mounted for the app's lifetime. Moving to lazily-built tabs would silently stop both
  background triggers.
- **`ref.read` inside the trigger callback, never `ref.watch`.** Watching
  `jiraSyncServiceProvider` would rebuild the provider — and reset the trigger — every time the
  credentials are invalidated. Reading it at run time also means newly saved credentials are
  picked up on the next run without any extra wiring.
- **Tests must override `jiraAutoSyncDebounceProvider`**, otherwise every assertion waits out the
  real 3-second window.
- Configuring credentials does *not* itself trigger a run; the next entry write or app start
  does. The Sync tab's button covers the impatient case.

## Out of scope (intentionally)

- Retry backoff for a failing row — it simply retries on the next run.
- Reading worklogs back from Jira.
- Auto-triggering Personio's sync; it still runs only from the Sync tab's button.
