# Finalize a Paused Timer on Real Quit

## Context

Pause/resume support just landed: a running `TimeEntry` can be paused (`pausedAt` set, `endAt` still null) and resumed any number of times before being stopped. Combined with the earlier window/tray work, Hickory now only truly exits via the tray menu's "Beenden" — minimizing or clicking the window's X always just hides to tray, keeping the app (and any paused entry) alive and resumable in the background.

The gap: if the user actually quits (tray → Beenden) while an entry is paused, that entry stays paused forever in the database. Next launch, it reappears in the running slot as a stale "Fortsetzen" prompt for a session from potentially days ago — confusing, and easy to accidentally resume into a huge bogus pause span. A running (not paused) entry has no equivalent problem: it's expected to keep counting through an app restart, since the elapsed-time formula is just `now - startAt`, so quitting mid-work and reopening later is already meaningful, intentional behavior. Pausing signals "I've stepped away"; quitting on top of that signals "I'm done for now" — so only that combination should auto-finalize.

## Decision

Quitting via the tray menu's "Beenden" checks whether the current open entry (if any) is paused. If it is, the entry is stopped first (`endAt` finalized to its existing `pausedAt`, per the pause/resume feature's established stop-while-paused behavior — no new finalization logic needed, just calling the existing `SyncedWrites.stopEntry`). A running (non-paused) entry is left untouched. This only applies to the real quit path — minimizing and closing the window continue to just hide to tray, unchanged.

## Design

**Architecture change**: `lib/main.dart` switches from `ProviderScope(child: ...)` (an implicit, inaccessible container) to an explicit `ProviderContainer()` + `UncontrolledProviderScope(container: ..., child: ...)`. This is the standard Riverpod pattern for code living outside the widget tree (the tray's quit handler, constructed and wired before `runApp`) needing to read providers.

**New DAO method** — `lib/data/drift/daos/time_entries_dao.dart`:
```dart
Future<TimeEntry?> getRunningEntry() {
  return (select(timeEntries)..where((t) => t.endAt.isNull())).getSingleOrNull();
}
```
A one-shot counterpart to the existing `watchRunningEntry()` stream — the quit handler needs a fresh direct read, not a possibly-stale cached stream value from a provider that may not have been actively watched recently.

**New coordinator function** — `lib/core/window/quit_behavior.dart`:
```dart
Future<void> stopPausedEntryOnQuit(AppDatabase db, SyncedWrites writes) async {
  final running = await db.timeEntriesDao.getRunningEntry();
  if (running != null && running.pausedAt != null) {
    await writes.stopEntry(running.id);
  }
}
```
Deliberately a plain function taking its two dependencies as parameters (not reading providers itself) so it's directly unit-testable against a real in-memory database, independent of `WindowTrayController`'s native tray code.

**`WindowTrayController` change** — `lib/core/window/window_tray_controller.dart` gains an injectable hook:
```dart
Future<void> Function()? onBeforeQuit;
```
The tray menu's "Beenden" `MenuItem.onClick` changes from directly calling `windowManager.destroy()` to a new `_quit()` method:
```dart
Future<void> _quit() async {
  await onBeforeQuit?.call();
  await windowManager.destroy();
}
```

**Wiring in `lib/main.dart`**: after constructing `windowTrayController` and the explicit `ProviderContainer`, before calling `windowTrayController.initialize()`:
```dart
windowTrayController.onBeforeQuit = () async {
  final db = container.read(appDatabaseProvider);
  final writes = await container.read(syncedWritesProvider.future);
  await stopPausedEntryOnQuit(db, writes);
};
```

## Out of Scope

- No change to minimize/close-to-tray behavior — both continue to just hide the window, exactly as before.
- No finalization for a *running* (non-paused) entry on quit — that's existing, intentional behavior (elapsed time naturally includes the closed-app gap) and isn't touched.
- No new UI (no confirmation dialog, no notice that a paused entry was auto-stopped) — this is a silent, background correctness fix, consistent with how `stopEntry`-while-paused already silently finalizes at the pause point rather than prompting.
- OS-level force-quit / process kill isn't interceptable and isn't attempted — this only covers the one quit path the app actually controls (the tray menu).

## Verification

- `flutter analyze` clean, existing test suite green.
- New unit tests for `stopPausedEntryOnQuit` against a real in-memory `AppDatabase` (matching the existing DAO test pattern): a paused entry gets stopped (`endAt` set, matching its `pausedAt`); a running (non-paused) entry is left untouched (`endAt` still null); no open entry at all is a no-op (no error, nothing to do).
- New unit test for `TimeEntriesDao.getRunningEntry()`: returns the open entry when one exists, `null` when none does.
- Manual: start a timer, pause it, quit via the tray's "Beenden", relaunch, confirm the entry now appears in the finished entries list (not as a stale paused prompt) with the correct pre-pause duration. Separately: start a timer, leave it running (not paused), quit, relaunch, confirm it's still running and picks up counting normally (unchanged behavior).
