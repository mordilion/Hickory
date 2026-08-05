# Resizable Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user freely resize Hickory's desktop window (currently locked to a
fixed 480×960), keeping that size only as a minimum, and remember the chosen size and
position across app restarts.

**Architecture:** A new device-local `WindowBoundsStore` (file-based, mirrors the
existing `BackgroundNoticeStore` pattern) persists a `Rect` as JSON. `WindowTrayController`
reads it on startup to seed the initial window bounds, and writes to it from
`window_manager`'s `onWindowResized`/`onWindowMoved` callbacks (which each fire once
per completed gesture, not continuously).

**Tech Stack:** Flutter desktop (`window_manager` 0.5.2), `path`/`path_provider`
(already dependencies — no new packages).

**Full design:** `docs/superpowers/specs/2026-08-05-resizable-window-design.md`

## Global Constraints

- English only in code, comments, and commit messages.
- No new dependencies — `window_manager`, `path`, `path_provider` already cover
  everything this plan needs.
- Window bounds persistence is device-local only — do **not** route it through
  `SyncedWrites`/Drift/the event log. This mirrors `BackgroundNoticeStore`, which is
  local-only for the identical reason (a UI preference tied to one machine, not the
  user's account).
- `WindowOptions` (`window_manager`'s startup config) has no position field —
  position can only be set after the window exists, via `windowManager.setPosition(Offset)`
  inside the `waitUntilReadyToShow` callback, same place `setResizable`/`setMinimumSize`
  are already called.
- No monitor-bounds validation on restore (explicit design decision) — a saved
  position is used as-is, even if it would now be off-screen.
- `WindowTrayController` itself stays untested (matches the existing codebase
  convention: it's a thin `window_manager`/`tray_manager` platform-channel wrapper,
  and only the pure/storage logic it delegates to gets unit tests — see
  `BackgroundNoticeStore`/`background_notice_store_test.dart` for the precedent).
  Verify Task 2 via `flutter analyze` + the full `flutter test` regression run, not a
  new test file.

---

### Task 1: `WindowBoundsStore`

**Files:**
- Create: `lib/core/window/window_bounds_store.dart`
- Test: `test/core/window/window_bounds_store_test.dart`

**Interfaces:**
- Produces: `WindowBoundsStore({required Directory supportDirectory})` with
  `Future<Rect?> read()` (null if nothing saved yet, or the file is missing/corrupt)
  and `Future<void> write(Rect bounds)`. `Rect` is `dart:ui`'s (re-exported by
  `package:flutter/material.dart`), the same type `window_manager`'s
  `windowManager.getBounds()` returns.

- [ ] **Step 1: Write the failing test**

Create `test/core/window/window_bounds_store_test.dart`:

```dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_bounds_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_window_bounds_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('read returns null before any write', () async {
    final store = WindowBoundsStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });

  test('write then read round-trips the same bounds, and persists across instances', () async {
    final store = WindowBoundsStore(supportDirectory: tempDir);
    const bounds = Rect.fromLTWH(120, 80, 900, 700);

    await store.write(bounds);

    expect(await store.read(), bounds);
    // A fresh instance reading the same directory sees the same bounds --
    // proves this is real file persistence, not in-memory state.
    final freshStore = WindowBoundsStore(supportDirectory: tempDir);
    expect(await freshStore.read(), bounds);
  });

  test('read returns null for a corrupt bounds file instead of throwing', () async {
    final file = File('${tempDir.path}/window_bounds.json');
    await file.writeAsString('{not valid json');

    final store = WindowBoundsStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/window/window_bounds_store_test.dart`
Expected: FAIL — `package:hickory/core/window/window_bounds_store.dart` doesn't exist.

- [ ] **Step 3: Implement `WindowBoundsStore`**

Create `lib/core/window/window_bounds_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;

/// Persists the user's chosen window size and position across app restarts.
/// Device-local only (deliberately not synced -- window bounds are a UI
/// preference for this machine, not something that should propagate to the
/// user's other devices, same reasoning as BackgroundNoticeStore). Takes the
/// support directory as a constructor parameter (rather than resolving it
/// internally via path_provider) so it's trivially testable against a temp
/// directory -- the real caller passes `await getApplicationSupportDirectory()`.
class WindowBoundsStore {
  WindowBoundsStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _boundsFile => File(p.join(supportDirectory.path, 'window_bounds.json'));

  /// Returns null if no bounds have been saved yet, or the file can't be
  /// read/parsed (e.g. a partial write) -- callers fall back to defaults.
  Future<Rect?> read() async {
    try {
      final content = await _boundsFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Rect.fromLTWH(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(Rect bounds) async {
    await _boundsFile.create(recursive: true);
    await _boundsFile.writeAsString(
      jsonEncode({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      }),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/window/window_bounds_store_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/window/window_bounds_store.dart test/core/window/window_bounds_store_test.dart
git commit -m "feat(window): add WindowBoundsStore for persisting window bounds"
```

---

### Task 2: Make the window resizable and wire up persistence

**Files:**
- Modify: `lib/core/window/window_tray_controller.dart`

**Interfaces:**
- Consumes: `WindowBoundsStore({required Directory supportDirectory})`,
  `.read() -> Future<Rect?>`, `.write(Rect) -> Future<void>` (Task 1, exact signatures
  above).
- No new public interface on `WindowTrayController` — its constructor and all
  existing public members (`initialize()`, `onBeforeQuit`, `backgroundNoticeMessage`,
  `scaffoldMessengerKey`, `updateContextMenu()`) are unchanged; `main.dart` needs no
  edits.

- [ ] **Step 1: Replace the fixed-size window setup with resizable + persisted bounds**

Edit `lib/core/window/window_tray_controller.dart`. Current content is:

```dart
// lib/core/window/window_tray_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'background_notice_store.dart';

/// Locks the desktop window to a fixed, slim "phone-like" size and routes
/// both minimize and close (the window's X button) to the system tray
/// instead of exiting — Hickory keeps tracking in the background. Call
/// [initialize] once from `main()`, before `runApp`.
class WindowTrayController with WindowListener, TrayListener {
  static const _windowSize = Size(480, 960);

  /// Shown via a SnackBar the first time the window is hidden to the tray,
  /// so the app doesn't seem to have silently vanished. A [GlobalKey] is
  /// used instead of a BuildContext because this controller is initialized
  /// before any widget tree exists — see lib/app.dart for where the key is
  /// attached to MaterialApp's scaffoldMessengerKey.
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Invoked right before the app actually quits (the tray menu's
  /// "Beenden", the only path that really exits — minimize/close only hide
  /// to tray). Set by `main()`, which has provider access this controller
  /// deliberately doesn't — see lib/core/window/quit_behavior.dart.
  Future<void> Function()? onBeforeQuit;

  /// Supplies the localized "runs in background" snackbar text. Set by
  /// `main()` (like [onBeforeQuit]) because localization lookup needs the
  /// active locale, which lives in the provider container this controller
  /// deliberately has no access to. Falls back to German when unset.
  String Function()? backgroundNoticeMessage;

  Future<void> initialize() async {
    windowManager.addListener(this);
    trayManager.addListener(this);

    await windowManager.ensureInitialized();
    // Deliberately not awaited: per window_manager's documented pattern,
    // this runs concurrently with Flutter building its first frame (which
    // only starts once `runApp` is called back in `main()`, after this
    // whole `initialize()` future completes). Awaiting it here would show
    // the native window before Flutter has anything to render into it,
    // producing a blank white window until the next paint is triggered.
    unawaited(
      windowManager.waitUntilReadyToShow(
        const WindowOptions(size: _windowSize, center: true, title: 'Hickory'),
        () async {
          await windowManager.setResizable(false);
          await windowManager.setMinimumSize(_windowSize);
          await windowManager.setMaximumSize(_windowSize);
          await windowManager.setPreventClose(true);
          await windowManager.show();
          await windowManager.focus();
        },
      ),
    );

    await trayManager.setIcon(
      defaultTargetPlatform == TargetPlatform.windows
          ? 'windows/runner/resources/app_icon.ico'
          : 'assets/tray_icon.png',
    );
    await trayManager.setToolTip('Hickory');
    await updateContextMenu();
  }
```

Replace it with:

```dart
// lib/core/window/window_tray_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'background_notice_store.dart';
import 'window_bounds_store.dart';

/// Manages the desktop window (resizable, with a slim "phone-like" minimum
/// size) and routes both minimize and close (the window's X button) to the
/// system tray instead of exiting — Hickory keeps tracking in the
/// background. Call [initialize] once from `main()`, before `runApp`.
class WindowTrayController with WindowListener, TrayListener {
  static const _minimumSize = Size(480, 960);

  /// Set once [initialize] resolves the app's support directory, then
  /// reused by the resize/move listeners so they don't re-resolve it on
  /// every event. Null only in the brief window before [initialize] runs.
  WindowBoundsStore? _boundsStore;

  /// Shown via a SnackBar the first time the window is hidden to the tray,
  /// so the app doesn't seem to have silently vanished. A [GlobalKey] is
  /// used instead of a BuildContext because this controller is initialized
  /// before any widget tree exists — see lib/app.dart for where the key is
  /// attached to MaterialApp's scaffoldMessengerKey.
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Invoked right before the app actually quits (the tray menu's
  /// "Beenden", the only path that really exits — minimize/close only hide
  /// to tray). Set by `main()`, which has provider access this controller
  /// deliberately doesn't — see lib/core/window/quit_behavior.dart.
  Future<void> Function()? onBeforeQuit;

  /// Supplies the localized "runs in background" snackbar text. Set by
  /// `main()` (like [onBeforeQuit]) because localization lookup needs the
  /// active locale, which lives in the provider container this controller
  /// deliberately has no access to. Falls back to German when unset.
  String Function()? backgroundNoticeMessage;

  Future<void> initialize() async {
    windowManager.addListener(this);
    trayManager.addListener(this);

    await windowManager.ensureInitialized();

    final supportDir = await getApplicationSupportDirectory();
    final boundsStore = WindowBoundsStore(supportDirectory: supportDir);
    _boundsStore = boundsStore;
    final savedBounds = await boundsStore.read();

    // Deliberately not awaited: per window_manager's documented pattern,
    // this runs concurrently with Flutter building its first frame (which
    // only starts once `runApp` is called back in `main()`, after this
    // whole `initialize()` future completes). Awaiting it here would show
    // the native window before Flutter has anything to render into it,
    // producing a blank white window until the next paint is triggered.
    unawaited(
      windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: savedBounds == null
              ? _minimumSize
              : Size(savedBounds.width, savedBounds.height),
          center: savedBounds == null,
          title: 'Hickory',
        ),
        () async {
          await windowManager.setResizable(true);
          await windowManager.setMinimumSize(_minimumSize);
          if (savedBounds != null) {
            await windowManager.setPosition(savedBounds.topLeft);
          }
          await windowManager.setPreventClose(true);
          await windowManager.show();
          await windowManager.focus();
        },
      ),
    );

    await trayManager.setIcon(
      defaultTargetPlatform == TargetPlatform.windows
          ? 'windows/runner/resources/app_icon.ico'
          : 'assets/tray_icon.png',
    );
    await trayManager.setToolTip('Hickory');
    await updateContextMenu();
  }
```

- [ ] **Step 2: Persist bounds when a resize or move gesture completes**

Edit `lib/core/window/window_tray_controller.dart`. Find:

```dart
  @override
  void onWindowMinimize() async {
    await _hideToTray();
  }
```

Replace it with:

```dart
  @override
  void onWindowMinimize() async {
    await _hideToTray();
  }

  @override
  void onWindowResized() async {
    await _persistBounds();
  }

  @override
  void onWindowMoved() async {
    await _persistBounds();
  }

  /// Best-effort: a failed write (e.g. disk full) isn't user-visible and
  /// doesn't block anything else, matching this controller's existing
  /// best-effort handling elsewhere (e.g. [_quit]'s swallowed
  /// [onBeforeQuit] failure).
  Future<void> _persistBounds() async {
    final store = _boundsStore;
    if (store == null) return;
    final bounds = await windowManager.getBounds();
    await store.write(bounds);
  }
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/core/window/window_tray_controller.dart lib/core/window/window_bounds_store.dart`
Expected: No issues found.

Run: `flutter test`
Expected: PASS (all tests — this task adds no new test file per the Global
Constraints, but the full suite must still show no regressions from the edit).

- [ ] **Step 4: Commit**

```bash
git add lib/core/window/window_tray_controller.dart
git commit -m "feat(window): make the window resizable and remember its bounds"
```

- [ ] **Step 5: Manual verification (not automatable — note for the user)**

`WindowTrayController` drives real OS window chrome, which isn't exercised by
`flutter test`. Before considering this feature done, run the app on at least one
desktop platform and confirm:
1. The window can be dragged larger/smaller than 480×960 in both dimensions, but not
   smaller.
2. Resize the window, quit via the tray menu's "Beenden"/quit item (not just closing
   to tray), relaunch — the window reopens at the same size and position.
3. Move the window (don't resize it), quit and relaunch the same way — the new
   position is remembered too.
