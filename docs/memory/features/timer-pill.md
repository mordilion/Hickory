# Timer Pill (floating always-on-top mini window)

## Entities

None. Pure UI/window-management feature — reads `runningEntryProvider` and writes only
through the existing `SyncedWrites` methods (`pauseEntry`, `resumeEntry`, `stopEntry`) the
timer tab already uses.

## Architecture

- `lib/core/window/window_mode.dart` — `enum WindowMode { full, pill }`.
- `lib/core/window/window_mode_controller.dart` (`WindowModeController`) — the only place
  that reshapes the native window: size, position, resizable, minimum size, title-bar
  style, always-on-top. `collapse()` / `expand()`.
- `lib/core/window/window_mode_provider.dart` (`windowModeProvider`,
  `WindowModeNotifier`) — Riverpod state mirroring the controller's mode.
- `lib/core/window/native_window.dart` — narrow interface (`setSize`, `setPosition`,
  `setResizable`, `setMinimumSize`, `setTitleBarHidden`, `setAlwaysOnTop`, `getBounds`,
  `getDisplaySize`) so `window_manager` (a plugin singleton, unreachable in tests) is never
  called from untestable code. Production delegates to `windowManager`/`screen_retriever`;
  tests use a `mocktail` fake. There is no `getTitleBarHeight` — see the frame-origin
  gotcha below for how the title-bar height is actually accounted for.
- `lib/core/window/window_bounds_store.dart` (`WindowBoundsStore`) — gained a `fileName`
  constructor parameter (default `window_bounds.json`); the controller holds two
  instances, the second pointed at `pill_bounds.json`, so dragging the pill can never
  overwrite the main window's remembered size.
- `lib/features/timer/pill/pill_screen.dart` (`PillScreen`, `PillHost`) — `PillScreen` is a
  pure rendering of five callbacks (pause/resume/stop/expand/drag-start); `PillHost` wires
  those to `SyncedWrites` and to `windowManager.startDragging()`.
- `lib/features/timer/pill/timer_pill_coordinator.dart` (`TimerPillCoordinator`) — the
  only place that calls `collapse()`/`expand()` automatically, reacting solely to
  `runningEntryProvider` transitioning to/from non-null. Ignores the first emission (see
  Decisions) and never undoes a manual expand while paused.
- `lib/features/shell/background_services.dart` (`BackgroundServices`) — see below.
- `lib/features/timer/timer_background_handlers.dart` (`TimerBackgroundHandlers`,
  `TimerBackgroundHandlersState.handleIdleSecondsChanged`) — wraps `BackgroundServices`
  with the idle-prompt and activity-sample handlers; lives directly under `MaterialApp`.
- `lib/app.dart` (`HickoryApp.build`) — the mode switch itself:
  `TimerBackgroundHandlers > TimerPillCoordinator > switch (windowModeProvider) { full:
  AppShell, pill: PillHost }`.
- `lib/features/shell/app_shell.dart` — passes the collapse-to-pill FAB via `NavShell`'s
  `fabBuilder`, shown only while an entry is running.
- `lib/features/entries/entries_list.dart` — `_bottomPaddingForFab` (see Gotchas).

## The core decision: a mode, not a second window

The pill is a *mode of the single existing window*, not a second window. Decided with the
user 2026-09-10 (design spec §2) over the alternative of a real second window: a second
window needs a second Flutter engine (or Flutter's multi-window API) plus cross-window
state transport, and an unknown amount of platform-specific work — for a benefit (main
window and pill visible at the same time) the user explicitly did not want. One window
that reshapes itself sidesteps all of that; the cost is that expanding and collapsing must
each rebuild the tree under `MaterialApp.home` (see `lib/app.dart`), which is why anything
that must survive the swap was deliberately pulled above it (`BackgroundServices`,
`TimerPillCoordinator`, `TimerBackgroundHandlers`).

## The frame-origin gotcha (spec §8.1) — found by a spike, not by reasoning

Hiding or restoring the title bar shifts the window's *frame* origin by exactly the
title-bar height (measured 32px on macOS): collapsing moved the reported top from y=49 to
y=81, and from y=33 to y=65 on a second run — both +32 — and expanding moved it back.
`getBounds`/`setPosition` operate on the frame, not the content area, so the frame moves
whenever the title bar appears or disappears even though nothing asked the window to move.

Consequence, enforced in `WindowModeController.collapse()`/`expand()`: **every mode switch
sets its target position explicitly, from that mode's own `WindowBoundsStore`** — never by
reusing a `getBounds()` taken in the other mode. `NativeWindow` has no `getTitleBarHeight`
(and none should be added for this): the correct fix for a shifted frame origin is not to
measure the shift and compensate, it's to never read the position from the wrong mode in
the first place. `collapse()` reads from `pillBounds`/writes to `fullBounds`, `expand()`
the reverse — always that mode's own store, never a `getBounds()` taken while the other
mode's shape is still on screen. This would be trivial to reintroduce by reasoning instead
of testing (it looks correct until you actually watch the window jump). `collapse()` also
hides the title bar *before* setting position, and lowers the minimum size *before* setting
the pill size — both orderings were spike findings, not assumptions.

## Bounds persistence must be suppressed for the whole duration of a switch

Found by the final whole-branch review, not the spike: `collapse()`/`expand()`'s own
`setSize`/`setPosition` calls make the native window emit a move event *during* the switch
(macOS: `NSWindow.setFrame` posts `NSWindowDidMove`, exactly as a user drag would), which
`WindowTrayController.onWindowMoved` routes into `persistCurrentBounds()`. Because `_mode`
in `WindowModeController` was only assigned after every native call, that re-entrant write
landed on the *old* mode's store while the window already had its *new* shape — corrupting
the user's saved window geometry on the very first collapse. `WindowModeController` now
tracks a `_switching` flag for the duration of `collapse()`/`expand()`; `persistCurrentBounds()`
no-ops while it is set, and the same flag also serialises overlapping switches (e.g. a
double-clicked collapse button). See `lib/core/window/window_mode_controller.dart` and
`test/core/window/window_mode_controller_test.dart` for the re-entrant-fake technique used
to reproduce this without a real platform channel.

## Why `BackgroundServices` exists

Four subscriptions — `syncWatcherProvider`, `jiraAutoSyncProvider`, and listeners on
`idleSecondsProvider` (idle detection) and `activeWindowChangesProvider` (activity
sampling) — used to live in `TimerScreen.build()`. That only worked because `NavShell`'s
`IndexedStack` kept the timer tab mounted for the app's whole lifetime, so the
subscriptions never tore down.

The pill replaces the entire tree under `MaterialApp.home` (`AppShell` ↔ `PillHost`), so
anything anchored to a screen would stop precisely while a timer runs — silent data loss
(no idle trim, no activity samples, no Jira push) with no error surfaced anywhere.
`BackgroundServices` (`lib/features/shell/background_services.dart`) is a `ConsumerWidget`
mounted above the switch, in `TimerBackgroundHandlers`, itself mounted above
`TimerPillCoordinator` in `lib/app.dart`. **Anything else that must outlive a screen
belongs there too** — it is the one place in the tree guaranteed to stay mounted regardless
of window mode.

## The dialog rule, and its one enforcement point

Any dialog shown from *above* the mode switch must expand the window first — a dialog
cannot open over a 320×56 window. The only call site today is
`TimerBackgroundHandlersState.handleIdleSecondsChanged`
(`lib/features/timer/timer_background_handlers.dart`): mode-check → `await
ref.read(windowModeProvider.notifier).expand()` → re-check `mounted` → `showIdlePromptDialog`.

Every other `showDialog` call in the app lives inside `AppShell`, which is swapped out
entirely in pill mode, so those are unreachable there — that is incidental protection from
the mode switch itself, not from any shared mechanism. There is deliberately **no shared
`showDialogExpandingWindow` helper**: the reviewer proposed one during Task 9 and it was
declined, because exactly one call site exists and building an abstraction for one caller
violates this project's YAGNI rule (abstract after three repetitions, not before). **A
future background-triggered dialog added above the switch must repeat the three-line
pattern by hand** — mode-check, `await expand()`, re-check `mounted` — this note is the
mitigation in place of that helper.

## The entries-list bottom padding is coupled to the FAB existing

`_bottomPaddingForFab` in `lib/features/entries/entries_list.dart` (currently `40.0 + 2 *
kFloatingActionButtonMargin`) reserves space so the shell's collapse-to-pill FAB can never
cover the trailing edit button on the last absence row in the deepest drill-down level.

This exact defect has already been introduced, fixed, and reintroduced once in this
project's history: required by
`docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md:72`, then removed in
commit `fc82d62` when the old manual-entry FAB went away, then restored in this feature
(Task 8) now that a shell-level FAB exists again. **If the FAB is ever removed again, this
padding must go with it; if a FAB is ever re-added, the padding must come back.** Neither
side of that pairing is enforced by a test that would fail if only one half changed.

## Windows is unverified

The spike (design spec §8) ran on macOS only — no Windows machine was available. Both
native risks remain open there:

- Whether `setTitleBarStyle`/`setTitleBarHidden` restores a normal frame on the way back
  from pill mode (macOS: proven reliable across two round trips).
- Whether a frameless always-on-top window keeps its taskbar entry on Windows.

Spec §8.2 requires re-running the same spike on Windows before this ships, and names a
Windows-only fallback (keeping the title bar in pill mode, or hiding to the tray instead)
as a possible outcome. No Windows claim has been added to code, comments, or user-facing
docs for this feature.

## Deferred follow-ups (out of scope, recorded not built)

- **User setting for the window level**, so the pill can show over full-screen apps. The
  user explicitly asked for this to become a setting later (not built now).
  `window_manager` already offers `setVisibleOnAllWorkspaces(true,
  visibleOnFullScreen: true)` on macOS; dragging the pill onto a full-screen space on a
  *second* display additionally needs `MainFlutterWindow` to inherit from `NSPanel`
  (per the package's own notes). The window-level handling is kept behind
  `WindowModeController` specifically so this can be added later without touching
  `PillScreen`/`PillHost`.
- **Global hotkey** to start/stop/pause from anywhere — already tracked in `ROADMAP.md`'s
  backlog, not specific to this feature.
- **Right-click context menu on the pill** — not built.
