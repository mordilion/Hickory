# Resizable Window — Design

Date: 2026-08-05
Status: Approved for planning

## 1. Goal & Scope

Hickory's desktop window is currently locked to a fixed 480×960 "phone-like" size
(`WindowTrayController._windowSize`, `setResizable(false)`,
`setMinimumSize`/`setMaximumSize` both pinned to that same value). This makes the
window freely resizable, with 480×960 kept only as a **minimum** (no maximum), and
persists the user's chosen size and position across app restarts.

Out of scope: clamping a restored position against currently-connected monitors (a
disconnected second monitor could in theory leave the window off-screen on next
launch) — accepted as a rare edge case the OS generally recovers from on its own;
revisit only if it turns out to be a real problem in practice. Also out of scope:
any UI/layout changes to make individual screens adapt to wider/taller windows —
the existing screens (Timer, Reports, Sync, Settings) are simple vertical layouts
that already scroll/wrap reasonably; revisit specific screens later if resizing
reveals actual layout breakage.

## 2. Behavior

- **Resizable:** `windowManager.setResizable(true)` (currently `false`).
- **Minimum size:** stays 480×960 — the size the UI was designed and tested at — via
  `setMinimumSize`. No `setMaximumSize` call, so there's no upper bound.
- **Persistence:** on `onWindowResized()` and `onWindowMoved()` (window_manager
  callbacks that each fire once when the user's drag/resize gesture completes, not
  continuously during it), read `windowManager.getBounds()` and write it to a new
  `WindowBoundsStore`.
- **Startup:** before calling `windowManager.waitUntilReadyToShow`, attempt to read
  persisted bounds via `WindowBoundsStore.read()`. If present, use that `Rect` as the
  `WindowOptions.size`/position instead of the default centered 480×960. If absent
  (first run, or the store file doesn't exist/is unreadable), fall back to today's
  behavior exactly (480×960, centered).
- **No monitor-bounds validation** on restore — the saved position is used as-is.

## 3. Data

### `lib/core/window/window_bounds_store.dart` (new)

Mirrors the existing `BackgroundNoticeStore` exactly: takes a `Directory` in its
constructor (the real caller passes `await getApplicationSupportDirectory()`, same as
`WindowTrayController._hideToTray()` already does for `BackgroundNoticeStore`), reads
and writes a single JSON file (`window_bounds.json`) containing `{"x":, "y":,
"width":, "height":}`. Deliberately **not** routed through `SyncedWrites`/Drift —
window bounds are a device-local UI preference, not something that should propagate
to the user's other devices, matching the existing precedent (`BackgroundNoticeStore`
is local-only for the same reason).

Public surface:
- `Future<Rect?> read()` — returns `null` if the file doesn't exist or fails to
  parse (corrupt/partial write), so the caller can fall back to defaults without
  special-casing errors.
- `Future<void> write(Rect bounds)` — overwrites the file with the given bounds.

## 4. `WindowTrayController` changes

- Constructor/public API unchanged (still `WindowTrayController()`, no new
  constructor params) — `getApplicationSupportDirectory()` is resolved lazily inside
  `initialize()`, same lazy-resolution style already used for
  `BackgroundNoticeStore` in `_hideToTray()`, and cached on the instance so the
  resize/move listeners can reuse it without re-resolving per event.
- `initialize()`: read persisted bounds before building `WindowOptions`; use them if
  present, else the existing default. Replace `setResizable(false)` with
  `setResizable(true)`; drop the `setMaximumSize` call; keep `setMinimumSize`.
- New listener overrides `onWindowResized()` and `onWindowMoved()`: call
  `windowManager.getBounds()` and `WindowBoundsStore.write(...)`. Best-effort — a
  failed write (e.g. disk full) is not user-visible and doesn't block anything else,
  matching this controller's existing best-effort error handling elsewhere (e.g.
  `_quit()`'s swallowed `onBeforeQuit` failure).

## 5. Testing

- `test/core/window/window_bounds_store_test.dart`: read returns `null` before any
  write; write-then-read round-trips the same `Rect` (via a fresh instance pointing
  at the same temp directory, proving real file persistence — same technique as
  `background_notice_store_test.dart`); read returns `null` for a missing/corrupt
  file rather than throwing.
- `WindowTrayController` itself stays untested, consistent with today (it's a thin
  platform-channel wrapper around `window_manager`/`tray_manager`, and the codebase's
  existing pattern is to only unit-test the pure/storage pieces it delegates to,
  e.g. `BackgroundNoticeStore`, `quit_behavior.dart`).

## 6. Out of Scope

Monitor-bounds validation on restore; any per-screen responsive-layout work; a
user-facing "reset window size" action; syncing window bounds across devices.
