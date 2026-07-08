# Pause/Resume for the Running Timer

## Context

The desktop window/tray work (fixed slim window, minimize/close to tray, autostart, Settings tab) raised a follow-up request: a small overlay shown when minimizing while a timer runs, with a way to pause it from there. Hickory currently only has Start/Stop — there is no way to temporarily halt a running entry without ending it, so "pause" doesn't exist anywhere in the data model, DAOs, or UI yet.

This spec covers only the pause/resume feature itself (data model, write API, main-window UI, and the reporting/export call sites that compute duration). The minimize overlay is a separate, later spec that will consume this feature once it exists — building the overlay first would mean designing it against a pause concept that doesn't exist yet, so the two are deliberately sequenced.

## Data Model

Two new columns on `TimeEntries` (`lib/data/drift/tables/time_entries_table.dart`):

- `pausedAt: DateTime?` — set to the current time when paused, `null` while running or stopped.
- `totalPausedSeconds: int` (default `0`) — the sum of all pause spans for this entry, accumulated across as many pause/resume cycles as the user performs.

An entry's state is derived, not stored as a separate enum:

| State | Condition |
|---|---|
| running | `endAt == null && pausedAt == null` |
| paused | `endAt == null && pausedAt != null` |
| stopped | `endAt != null` |

An entry may be paused and resumed any number of times before it's stopped (e.g. paused for lunch, resumed, paused again for a meeting, resumed again).

Both columns are plain drift columns, so the existing `TimeEntry.toJson()`/`fromJson()` (drift-generated) automatically include them in the sync event payload — the sync engine's last-write-wins merge already treats payloads as opaque full snapshots, so no changes are needed in `packages/sync_engine` or `sync_ingestor.dart`.

## Duration Calculation

A single shared getter is the only place that knows how to turn an entry into a worked duration, replacing the raw `endAt.difference(startAt)` used today in four places:

```dart
Duration get workedDuration =>
    (endAt ?? pausedAt ?? DateTime.now().toUtc()).difference(startAt) -
    Duration(seconds: totalPausedSeconds);
```

- While running: counts up live (via the existing `timerTickProvider` 1-second rebuild).
- While paused: frozen at the moment `pausedAt` was set.
- While stopped: fixed, with all accumulated pause time already subtracted.

This replaces the manual `endAt!.difference(startAt)` / `endAt.difference(entry.startAt)` calculations in:
- `lib/features/entries/entries_list.dart`
- `lib/features/reports/report_calculations.dart` (two call sites)
- `lib/features/reports/csv_export.dart`
- `lib/features/timer/timer_screen.dart`'s `_RunningCard` (currently computes elapsed inline)

## Write API

New methods alongside the existing `startEntry`/`stopEntry` in `lib/data/drift/daos/time_entries_dao.dart` and `lib/data/sync/synced_writes.dart` (mirroring the existing pattern: DAO does the local write, `SyncedWrites` wraps it and appends the sync event):

- `pauseEntry(id)`: sets `pausedAt = DateTime.now().toUtc()`. Only meaningful while running; calling it on an already-paused or stopped entry is a no-op guarded by the UI never offering the action in those states (no defensive runtime check needed beyond that, consistent with how `stopEntry` already assumes a valid running entry).
- `resumeEntry(id)`: adds `DateTime.now().toUtc().difference(pausedAt)` to `totalPausedSeconds`, sets `pausedAt = null`.
- `stopEntry(id)` (existing method, behavior extended): if the entry is currently paused, `endAt` is set to the stored `pausedAt` value (not "now") — the entry logically ended the moment it was paused, so forgetting to resume/stop for hours doesn't inflate anything and doesn't require any extra pause-time bookkeeping for the trailing gap. If the entry is running (not paused), behavior is unchanged (`endAt = now`).

## UI Changes

`_RunningCard` in `lib/features/timer/timer_screen.dart` gets a second button next to the existing one, matching the app's established two-action pattern:

- **Running**: primary gradient button "Pause" (icon `Icons.pause`) + secondary "Stop" button.
- **Paused**: primary gradient button "Fortsetzen" (icon `Icons.play_arrow`) + secondary "Stop" button.

The displayed elapsed time uses `workedDuration` (see above), so it visibly freezes the instant Pause is tapped and resumes counting from the same value on Resume.

## Tracking Suspension While Paused

Both of `TimerScreen`'s existing `ref.listen` handlers must no-op while the running entry is paused, so "pause" genuinely stops all background recording rather than just the displayed clock:

- `_handleIdleSecondsChanged`: returns immediately if the current running entry's `pausedAt != null` (checked the same way it already checks `running == null`).
- `_recordActivitySample`: same guard.

## Testing

- DAO-level tests for `pauseEntry`/`resumeEntry`/`stopEntry`-while-paused against a real in-memory drift database (matching the existing `time_entries_dao_test.dart` pattern), covering: single pause/resume cycle, multiple cycles accumulating `totalPausedSeconds` correctly, and stop-while-paused setting `endAt` to `pausedAt`.
- Unit tests for the `workedDuration` getter covering all three states (running/paused/stopped) with synthetic `TimeEntry` values — plain `test()`, no widget pump needed.
- No new `testWidgets` tests are required; the existing `_RunningCard`/`_StartCard` structure has no widget-level test today and this doesn't change that pattern.

## Out of Scope

- The minimize-to-tray overlay itself — separate, later spec, built on top of this.
- Reports UI changes beyond using the corrected `workedDuration` (no new pause-specific reporting views, e.g. no "time spent paused" report).
- Editing `pausedAt`/`totalPausedSeconds` directly via the manual-entry dialog — manual entries are always created already-stopped and don't go through the pause states.
- Any change to the auto-tracking (`activity_tracker`) plugin itself — only the app-level decision of whether to call into it while paused changes.

## Verification

- `flutter analyze` clean, existing test suite green throughout.
- New DAO and `workedDuration` unit tests pass.
- Manual: start a timer, pause it, confirm the displayed time freezes and the button switches to "Fortsetzen"; wait a few seconds, resume, confirm the clock continues from the frozen value (not from zero, not including the paused gap); pause and resume a second time to confirm multi-cycle accumulation; stop while paused and confirm the entries list shows the correct (pause-excluded) duration; confirm no idle prompt appears while paused even after exceeding the idle threshold.
