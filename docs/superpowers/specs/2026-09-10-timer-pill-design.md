# Floating Timer Pill — Design

Date: 2026-09-10
Status: Approved for planning

## 1. Problem

While a timer runs, Hickory occupies a full window (minimum 480×960) or is hidden in the
tray. Neither state fits the situation the pill is for: the user is working in another
application and wants a permanent, glanceable answer to "is it still running, and for how
long" plus one-click pause/resume/stop — without the app covering the work it is timing.

Hiding to the tray solves the screen-estate problem but removes the running time from view
and puts stop/pause two clicks deep behind a tray menu.

## 2. Solution

A **pill mode**: the existing window shrinks to a frameless, always-on-top 320×56 window
showing the elapsed time, the client/project, and three controls (pause/resume, stop,
expand). It can be dragged anywhere and remembers where it was put.

The pill is a *mode of the single existing window*, not a second window. Decided with the
user on 2026-09-10 over the alternative of a real second window: a second window needs a
second Flutter engine (or Flutter's multi-window API), cross-window state transport, and an
unknown amount of platform-specific work — for a benefit (main window and pill visible at
the same time) the user did not want.

## 3. Scope

### In scope

- `WindowMode { full, pill }` and the controller that drives the native window between them
- Pill UI: elapsed time, client · project, pause/resume, stop, expand, drag-to-move
- Automatic collapse when a timer starts; manual expand and collapse in both directions
- Separate persistence of the pill's position from the main window's bounds
- Lifting `TimerScreen`'s background subscriptions to an always-mounted host (see §5.1)

### Out of scope (recorded as follow-ups, not built now)

- **Setting "show the pill over full-screen apps"** — the user explicitly asked that this
  become a user-facing setting later. `window_manager` already offers
  `setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true)` on macOS, so this is likely
  cheap; the package notes that dragging onto a full-screen space *on a second display*
  additionally requires `MainFlutterWindow` to inherit from `NSPanel`. The window-level
  handling is kept behind `WindowModeController` so this can be added without touching the
  pill itself.
- Global hotkey to start/stop/pause from anywhere (already in the roadmap backlog)
- Right-click context menu on the pill
- Hiding to the tray *from* pill mode (the pill has no title bar, hence no close/minimize;
  the tray icon remains the way back from the hidden state)

## 4. Behaviour

### 4.1 Transitions

| Trigger | From → to | Notes |
|---|---|---|
| Timer started | full → pill | automatic |
| Expand button on the pill | pill → full | the running entry is not touched |
| Collapse FAB in the main window | full → pill | FAB shown only while an entry is running |
| Stop, pressed on the pill | pill → full | without a timer the pill has no purpose |
| Stop, pressed in the main window | full → full | the FAB disappears |
| Pause / resume | pill → pill | time freezes, button becomes ▶, pill visually dimmed |
| Idle prompt becomes due | pill → full | see §4.2 |
| App start | always full | see §4.3 |

Starting an entry is only reachable in full mode (it needs the project picker and the
description field), so "timer started" always means "started from full". After a dialog has
forced an expand (§4.2), the window **stays** expanded; the user collapses it again when
they are ready, using the same FAB as always.

The expand/collapse pair exists because of a concrete scenario the user named: a client
calls while their timer runs and asks for figures, which only the Reports tab can answer.
Expanding must therefore never stop, pause, or otherwise disturb the running entry.

### 4.2 Dialogs force an expand

`showIdlePromptDialog` cannot open over a 320×56 window. The rule is general, not a
special case for idle: **any dialog expands the window first.** This is also the right
behaviour on its own terms — "you were away for 5 minutes, should I trim that?" is a
question answered in full size.

SnackBars are suppressed in pill mode. The only existing one that could collide is the
"runs in the background" notice, which fires on hide-to-tray — unreachable from pill mode.

### 4.3 App start is always `full`

Deliberately contrary to the "a running timer means pill" rule. The case where the app
starts with an entry already running is usually the case where the user forgot to stop it
the previous day — exactly when they need the entries list, not a 320px pill. The mode is
therefore not persisted across restarts; the pill's *position* is.

### 4.4 Window bounds

`WindowTrayController.onWindowMoved` / `onWindowResized` currently write to
`WindowBoundsStore` unconditionally. In pill mode they must write to `PillBoundsStore`
instead, or dragging the pill would overwrite the main window's remembered size. The
controller receives a `WindowMode Function()` callback for this — the same pattern already
used there for `onBeforeQuit` and `backgroundNoticeMessage`.

Default position when the pill has never been dragged: top-right of the display Hickory is
currently on (`screen_retriever` is already in the tree via `window_manager`).

## 5. Architecture

| New / changed | Role |
|---|---|
| `lib/core/window/window_mode.dart` | `enum WindowMode { full, pill }` |
| `lib/core/window/window_mode_controller.dart` | The only place that drives the native window across modes: size, position, resizable, minimum size, title-bar style, always-on-top. Also the seam for the later window-level setting |
| `lib/core/window/pill_bounds_store.dart` | Pill position, stored separately from the main window's bounds |
| `lib/features/timer/pill/pill_screen.dart` | The pill UI |
| `lib/app.dart` | `home:` switches on `windowModeProvider` |
| `lib/features/shell/app_shell.dart` | Passes a collapse FAB via the existing, so far unused `NavShell.fabBuilder`; becomes a `ConsumerWidget` |
| `lib/features/timer/timer_screen.dart` | Background subscriptions move out (§5.1) |

### 5.1 Background subscriptions must be lifted (required, not optional)

`TimerScreen.build()` currently starts four background concerns — `syncWatcherProvider`,
`jiraAutoSyncProvider`, and listeners on `idleSecondsProvider` and
`activeWindowChangesProvider`. Its own comment states why that works: the tab is *always*
mounted because `NavShell` uses an `IndexedStack`.

Swapping the tree for the pill unmounts `TimerScreen`. Idle detection, activity sampling,
and Jira auto-sync would then stop **precisely while a timer runs** — silent data loss, not
a cosmetic defect. A `BackgroundServices` widget above the mode switch takes ownership of
these four subscriptions.

Rejected alternative: keep `AppShell` mounted and overlay the pill via `Stack`/`Offstage`.
It avoids moving the subscriptions but forces a 480×960 tree into a 320×56 window —
overflow exceptions in debug and pointless layout work on every tick.

### 5.2 Native window access is injected

`windowManager` is a plugin singleton and unreachable in tests. `WindowModeController`
takes its native counterpart as a narrow interface (`setSize`, `setPosition`,
`setResizable`, `setMinimumSize`, `setTitleBarStyle`, `setAlwaysOnTop`); production
delegates to `windowManager`, tests use a `mocktail` fake.

## 6. The pill

Fixed 320×56, not resizable.

```
┌──────────────────────────────────────────┐
│  01:23:45              [⏸]  [⏹]  [⤢]     │
│  Müller GmbH · Website-Relaunch           │
└──────────────────────────────────────────┘
```

- Elapsed time via `formatDuration(..., TimeFormatStyle.h24Sec)` — the same function the
  timer tab uses, so the two displays can never diverge
- Client · project on one line, ellipsized
- Colours and radii from `hickory_colors.dart`; no new literals
- The whole surface outside the three buttons is the drag handle
  (`onPanStart → windowManager.startDragging()`)
- Paused state is visually distinct: frozen time, dimmed surface, ▶ instead of ⏸. At 56px
  height "running" and "paused" are otherwise indistinguishable, and that confusion costs
  real working time
- Each icon-only button carries a `Tooltip` and a `Semantics` label; four new ARB keys
  (`pillPause`, `pillResume`, `pillStop`, `pillExpand`) across all locale files

## 7. Testing

- full→pill lowers the minimum size **before** setting the size (the other order leaves the
  window stuck at 480 wide)
- pill→full restores minimum size, resizable, title-bar style **and** always-on-top
- moving in pill mode writes to `PillBoundsStore`, not `WindowBoundsStore`
- `PillBoundsStore` round-trip, following `test/core/window/window_bounds_store_test.dart`
- pill widget test with overridden providers: time formatting, paused rendering, callbacks
- starting an entry sets the mode to `pill`; stopping from the pill sets it back
- `BackgroundServices` keeps its subscriptions alive across a mode switch

## 8. Risks — resolve by spike before planning

1. **`setTitleBarStyle` in both directions at runtime.** Going frameless is the easy half;
   reliably restoring a normal title bar, on macOS *and* Windows, is the weakest point of
   the whole design. If the return path does not hold, the fallback is to keep the title
   bar hidden permanently and draw our own in the main window — a substantially larger
   change that must come back to this design.
2. **Shrinking without flicker**, and whether a frameless always-on-top window stays in the
   Windows taskbar.

The spike is a throwaway branch with a dummy widget in place of the real pill: shrink,
drag, expand, inspect the restored state. Its output is an answer, not code that is kept.
