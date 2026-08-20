# Sync Screen (Sync tab)

## Architecture

- `SyncScreen` (`lib/features/sync/sync_screen.dart`) is one `ConsumerStatefulWidget` holding
  three collapsible cards: the device sync folder, Jira, Personio. Credentials live in the
  per-service secure stores, never in the event log.
- Each service's run reports a count message into `_jiraStatusMessage` /
  `_personioStatusMessage` (widget state, gone on rebuild).
- The failed-entry list is *not* built from that run's result. `failedPushes`
  (`lib/features/sync/failed_pushes.dart`) joins the live entries with the failure map that
  `jiraFailures` / `personioFailures` derive from the stored tracking rows, and
  `FailedPushesList` (`failed_pushes_list.dart`) renders it. See
  docs/superpowers/specs/2026-08-19-sync-error-visibility-design.md §5.

## Decisions

- **The failed list reads stored state, not the last run's counts.** Since Jira reconciles
  automatically (see [jira-sync.md](jira-sync.md)), most runs happen without the user watching;
  a list tied to the button press would hide exactly those failures. It also means the list is
  already correct when the tab is opened, before anything is pressed.
- **A row on `pendingDelete` is left out of the list even when it carries an error.** A failed
  delete keeps that status so the whole delete retries, and its entry is normally gone locally —
  there would be no description or date to show. Same reason `failedPushes` drops a failure with
  no matching entry.
- **`FailedPushesList` is presentational and service-agnostic**: it takes the pairs, a fallback
  message for a row whose `lastError` is null, and an `onTapEntry` callback. Both services use
  it; the Riverpod-dependent part (opening `showManualEntryDialog`) stays in the screen.
- **Nothing is rendered when nothing failed** — no "all good" message. The tab is opened to do
  something else, and an empty-state line would be noise.
- **Date and error sit on separate lines**, not joined with a separator: the stored message is a
  sentence of its own and can be long.

## Gotchas

- **`AppSettingsStyles` extends the *nullable* `AppSettingsRow?`.** `ref.watch(...).value.dateStyle`
  chained in one expression trips `unchecked_use_of_nullable_value`; assign the row to a local
  first, as `entries_list.dart` does.
- The failed list depends on `allEntriesProvider`, `jiraWorklogsByEntryIdProvider` and
  `personioAttendancesByEntryIdProvider` — a widget test mounting `SyncScreen` has to override
  all three (there is no such test yet; the logic is covered by `failed_pushes_test.dart` and
  `failed_pushes_list_test.dart` instead).

## Out of scope (intentionally)

- A widget test for `SyncScreen` itself — it reads the secure credential stores in `initState`.
- Surfacing failures anywhere outside this tab and the entries list's status icons.
