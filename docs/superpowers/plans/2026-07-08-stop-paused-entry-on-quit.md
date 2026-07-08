# Finalize a Paused Timer on Real Quit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user actually quits Hickory (tray menu → "Beenden"), automatically finalize a currently-paused timer instead of leaving it paused forever; a running (non-paused) timer is left untouched.

**Architecture:** A one-shot `TimeEntriesDao.getRunningEntry()` query backs a small, plain, directly-testable coordinator function (`stopPausedEntryOnQuit`) that decides whether to call the existing `SyncedWrites.stopEntry`. `WindowTrayController` gets an injectable `onBeforeQuit` hook invoked right before it destroys the window; `main.dart` wires that hook to the coordinator, which requires switching from `ProviderScope` to an explicit `ProviderContainer` + `UncontrolledProviderScope` so code outside the widget tree can reach providers.

**Tech Stack:** Flutter/Dart, Riverpod, drift — same stack as the rest of the app, no new dependencies.

## Global Constraints

- Every task must leave `flutter analyze` clean and the existing test suite green.
- `DateTime.now()` calls in DAO methods are always immediately `.toUtc()`'d — not directly relevant here since `getRunningEntry()` does no time arithmetic, but keep in mind if touching `stopEntry`.
- No new `testWidgets` — the native tray/window pieces this plan touches aren't unit-testable in this environment (same as the earlier window/tray plan); all new test coverage is plain `test()` against the coordinator function and the DAO method.
- This only covers the app's own quit path (tray menu). OS-level force-quit/process kill is not interceptable and is out of scope.

---

## File Structure

New files:
- `lib/core/window/quit_behavior.dart` — `stopPausedEntryOnQuit(AppDatabase db, SyncedWrites writes)`, the one place that decides whether quitting should finalize the open entry.
- `test/core/window/quit_behavior_test.dart` — unit tests for the coordinator function against a real in-memory database.

Modified files:
- `lib/data/drift/daos/time_entries_dao.dart` — add `getRunningEntry()`.
- `test/data/drift/time_entries_dao_test.dart` — add a test for `getRunningEntry()`.
- `lib/core/window/window_tray_controller.dart` — add the `onBeforeQuit` hook and route "Beenden" through it.
- `lib/main.dart` — switch to `ProviderContainer`/`UncontrolledProviderScope`, wire `onBeforeQuit`.

---

### Task 1: TimeEntriesDao.getRunningEntry()

**Files:**
- Modify: `lib/data/drift/daos/time_entries_dao.dart`
- Modify: `test/data/drift/time_entries_dao_test.dart`

**Interfaces:**
- Produces: `Future<TimeEntry?> getRunningEntry()` — a one-shot counterpart to the existing `watchRunningEntry()` stream. Task 2 depends on this exact name/signature.

- [ ] **Step 1: Write the failing test**

Read the current `test/data/drift/time_entries_dao_test.dart` first — it already has a `setUp`/`tearDown` pair opening/closing an `AppDatabase.forTesting(NativeDatabase.memory())` as `db`, and five existing `test()` blocks. Add one more test to the same `main()`, after the existing tests:

```dart
  test('getRunningEntry returns the open entry, or null if none exists', () async {
    expect(await db.timeEntriesDao.getRunningEntry(), isNull);

    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    final running = await db.timeEntriesDao.getRunningEntry();

    expect(running?.id, entry.id);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/drift/time_entries_dao_test.dart`
Expected: FAIL — `getRunningEntry` is not defined on `TimeEntriesDao`.

- [ ] **Step 3: Write the implementation**

In `lib/data/drift/daos/time_entries_dao.dart`, add immediately after the existing `watchRunningEntry()`:

```dart
  /// One-shot counterpart to [watchRunningEntry], for callers outside the
  /// widget tree (e.g. the quit-time check) that need a fresh direct read
  /// rather than a cached stream value.
  Future<TimeEntry?> getRunningEntry() {
    return (select(timeEntries)..where((t) => t.endAt.isNull())).getSingleOrNull();
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/drift/time_entries_dao_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Analyze, run the full suite, and commit**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

```bash
git add lib/data/drift/daos/time_entries_dao.dart test/data/drift/time_entries_dao_test.dart
git commit -m "Add TimeEntriesDao.getRunningEntry: a one-shot read for callers outside the widget tree"
```

---

### Task 2: stopPausedEntryOnQuit coordinator function

**Files:**
- Create: `lib/core/window/quit_behavior.dart`
- Create: `test/core/window/quit_behavior_test.dart`

**Interfaces:**
- Consumes: `TimeEntriesDao.getRunningEntry()` (Task 1), `SyncedWrites.stopEntry(String id)` (already exists).
- Produces: `Future<void> stopPausedEntryOnQuit(AppDatabase db, SyncedWrites writes)` — called from `lib/main.dart` (Task 3) via `WindowTrayController.onBeforeQuit`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/window/quit_behavior_test.dart
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/quit_behavior.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

// Plain test() (not testWidgets): no widget pumping needed.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory syncRoot;
  late AppDatabase db;
  late SyncedWrites writes;

  setUp(() {
    syncRoot = Directory.systemTemp.createTempSync('hickory_quit_behavior_test_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) {
      syncRoot.deleteSync(recursive: true);
    }
  });

  test('a paused entry is stopped', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);

    await stopPausedEntryOnQuit(db, writes);

    final result = await db.timeEntriesDao.getRunningEntry();
    expect(result, isNull); // no longer "running" (endAt is now set)
  });

  test('a running (not paused) entry is left untouched', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');

    await stopPausedEntryOnQuit(db, writes);

    final result = await db.timeEntriesDao.getRunningEntry();
    expect(result?.id, entry.id);
    expect(result?.endAt, isNull);
  });

  test('no open entry at all is a no-op', () async {
    await stopPausedEntryOnQuit(db, writes); // must not throw

    expect(await db.timeEntriesDao.getRunningEntry(), isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/window/quit_behavior_test.dart`
Expected: FAIL — `package:hickory/core/window/quit_behavior.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/window/quit_behavior.dart
import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart';

/// Called right before the app actually quits (tray menu "Beenden" — see
/// WindowTrayController.onBeforeQuit). If the current open entry is
/// paused, finalize it now rather than leaving it paused forever with no
/// running app to resume it into. A running (non-paused) entry is left
/// untouched — that's expected to keep counting through an app restart.
Future<void> stopPausedEntryOnQuit(AppDatabase db, SyncedWrites writes) async {
  final running = await db.timeEntriesDao.getRunningEntry();
  if (running != null && running.pausedAt != null) {
    await writes.stopEntry(running.id);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/window/quit_behavior_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze, run the full suite, and commit**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

```bash
git add lib/core/window/quit_behavior.dart test/core/window/quit_behavior_test.dart
git commit -m "Add stopPausedEntryOnQuit: finalize a paused entry when the app really quits"
```

---

### Task 3: Wire onBeforeQuit through WindowTrayController and main.dart

**Files:**
- Modify: `lib/core/window/window_tray_controller.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `stopPausedEntryOnQuit` (Task 2), `appDatabaseProvider` (existing, `lib/core/di/database_provider.dart`), `syncedWritesProvider` (existing, `lib/core/di/sync_providers.dart`).

- [ ] **Step 1: Add the `onBeforeQuit` hook to WindowTrayController**

Current `lib/core/window/window_tray_controller.dart` is:

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
  static const _windowSize = Size(400, 800);

  /// Shown via a SnackBar the first time the window is hidden to the tray,
  /// so the app doesn't seem to have silently vanished. A [GlobalKey] is
  /// used instead of a BuildContext because this controller is initialized
  /// before any widget tree exists — see lib/app.dart for where the key is
  /// attached to MaterialApp's scaffoldMessengerKey.
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

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
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Öffnen', onClick: (_) => _restore()),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Beenden', onClick: (_) => windowManager.destroy()),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    await windowManager.hide();

    final supportDir = await getApplicationSupportDirectory();
    final noticeStore = BackgroundNoticeStore(supportDirectory: supportDir);
    if (!await noticeStore.hasBeenShown()) {
      await noticeStore.markShown();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Hickory läuft im Hintergrund weiter.')),
      );
    }
  }

  @override
  void onWindowClose() async {
    // setPreventClose(true) means the OS won't close the window on its
    // own — this callback is Hickory's only chance to react to the X
    // button, so it must explicitly hide instead of doing nothing.
    if (await windowManager.isPreventClose()) {
      await _hideToTray();
    }
  }

  @override
  void onWindowMinimize() async {
    await _hideToTray();
  }

  @override
  void onTrayIconMouseDown() {
    _restore();
  }
}
```

Change it to (new/changed lines: the `onBeforeQuit` field, the "quit" `MenuItem`'s `onClick`, and the new `_quit` method):

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
  static const _windowSize = Size(400, 800);

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
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Öffnen', onClick: (_) => _restore()),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Beenden', onClick: (_) => _quit()),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    await windowManager.hide();

    final supportDir = await getApplicationSupportDirectory();
    final noticeStore = BackgroundNoticeStore(supportDirectory: supportDir);
    if (!await noticeStore.hasBeenShown()) {
      await noticeStore.markShown();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Hickory läuft im Hintergrund weiter.')),
      );
    }
  }

  Future<void> _quit() async {
    await onBeforeQuit?.call();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    // setPreventClose(true) means the OS won't close the window on its
    // own — this callback is Hickory's only chance to react to the X
    // button, so it must explicitly hide instead of doing nothing.
    if (await windowManager.isPreventClose()) {
      await _hideToTray();
    }
  }

  @override
  void onWindowMinimize() async {
    await _hideToTray();
  }

  @override
  void onTrayIconMouseDown() {
    _restore();
  }
}
```

- [ ] **Step 2: Switch main.dart to an explicit ProviderContainer and wire the hook**

Current `lib/main.dart` is:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/window/window_tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AutostartService().setup();

  final windowTrayController = WindowTrayController();
  await windowTrayController.initialize();

  runApp(
    ProviderScope(
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );
}
```

Change it to:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/di/database_provider.dart';
import 'core/di/sync_providers.dart';
import 'core/window/quit_behavior.dart';
import 'core/window/window_tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AutostartService().setup();

  final container = ProviderContainer();
  final windowTrayController = WindowTrayController();
  windowTrayController.onBeforeQuit = () async {
    final db = container.read(appDatabaseProvider);
    final writes = await container.read(syncedWritesProvider.future);
    await stopPausedEntryOnQuit(db, writes);
  };
  await windowTrayController.initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: all tests pass — check whether any test directly constructs `HickoryApp(...)` inside a `ProviderScope` (`grep -rn "ProviderScope" test/`); as of this plan, no test does, but confirm before committing.

- [ ] **Step 5: Commit**

```bash
git add lib/core/window/window_tray_controller.dart lib/main.dart
git commit -m "Finalize a paused entry when quitting via the tray menu"
```

---

### Task 4: Manual verification

**Files:** none (verification only).

- [ ] **Step 1: Build**

```powershell
flutter build windows --debug
```

Expected: `✓ Built build\windows\x64\runner\Debug\hickory.exe`

- [ ] **Step 2: Verify paused-then-quit finalizes the entry**

Launch the exe. Start a timer, click Pause. Right-click the tray icon, click "Beenden" — confirm the process actually exits (`Get-Process hickory` finds nothing). Relaunch the exe. Confirm: no "Fortsetzen" prompt for the old entry — the Timer tab shows the idle Start card. Open the entries list, confirm the previously-paused entry now appears as a finished entry with the correct duration (excluding whatever time had accumulated as paused before the quit).

- [ ] **Step 3: Verify a running (non-paused) entry is unaffected by quit**

Start a new timer, do NOT pause it. Quit via the tray's "Beenden". Relaunch. Confirm: the Timer tab shows the same entry still running, with elapsed time counting from the original start (including the time the app was closed) — unchanged from pre-existing behavior.

- [ ] **Step 4: Verify minimize/close-to-tray is unaffected**

With a timer paused, click the window's minimize button, then restore via the tray icon — confirm the entry is still paused (not auto-stopped); only real quit finalizes it. Repeat with the X (close) button.

- [ ] **Step 5: Clean up test processes**

```powershell
Stop-Process -Name hickory -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 6: Final full-suite check**

```bash
flutter analyze
flutter test
```

Expected: both clean/green.

---

## Self-Review Notes

- **Spec coverage:** `getRunningEntry` one-shot read (Task 1), the coordinator function's exact decision logic including the "running entry untouched" and "no entry" cases (Task 2), the `onBeforeQuit` hook and its wiring via an explicit `ProviderContainer` (Task 3), and manual confirmation of all three spec'd scenarios — paused+quit, running+quit, minimize/close unaffected (Task 4) — cover every section of the spec.
- **Placeholder scan:** none found.
- **Type consistency:** `stopPausedEntryOnQuit(AppDatabase db, SyncedWrites writes)` (Task 2) matches its call site in `main.dart` (Task 3) exactly; `WindowTrayController.onBeforeQuit`'s type (`Future<void> Function()?`) matches how it's both set (Task 3) and invoked (`await onBeforeQuit?.call();` in `_quit()`, also Task 3).
- **Sequencing:** Task 1 → Task 2 → Task 3 → Task 4 is a valid linear order; Task 3 depends on both Task 1 (transitively, via Task 2) and Task 2 directly, Task 4 depends on all three being in place.
