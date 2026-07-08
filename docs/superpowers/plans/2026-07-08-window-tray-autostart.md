# Window / Tray / Autostart / Settings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the desktop window to a fixed, slim "phone-like" size, make minimize/close hide to the system tray instead of quitting, add an autostart-on-login toggle, and give both a home on a new 4th "Settings" bottom-nav tab.

**Architecture:** A `WindowTrayController` initialized once in `main()` owns all `window_manager`/`tray_manager` setup and listens for close/minimize events to hide instead of exit. A thin `AutostartService` wraps the `launch_at_startup` package. `SettingsScreen` is a new body-only tab (matching the pattern every other tab already follows) hosting the autostart toggle; `AppShell` gains it as a 4th `NavShell` destination — `NavShell` itself (from the Electric Violet redesign) needs no changes since it was built generic.

**Tech Stack:** Flutter/Dart, `window_manager` (already a dependency, unused until now), `tray_manager` (ditto), `launch_at_startup` + `package_info_plus` (new), Riverpod.

## Global Constraints

- Desktop only (Windows/macOS) — consistent with the rest of the app's current platform scope.
- Windows is the only platform actually buildable/testable in this environment. macOS-specific native code (a `launch_at_startup` requirement — see Task 5) is written against the package's documented setup but cannot be built or run here; flag it as unverified, the same way the Electric Violet plan's `activity_tracker` macOS Swift code was flagged.
- Every task must leave `flutter analyze` clean and the existing test suite green.
- Follow the existing local-persistence pattern already used in this codebase for simple flags (`lib/core/di/device_id_provider.dart`, `packages/storage_access/lib/src/sync_folder_provider.dart`: a plain text file in the app-support directory) rather than adding a new persistence mechanism.
- `NavShell` (`lib/features/shell/nav_shell.dart`) must not be modified — it already accepts an arbitrary `children`/`destinations` list; only `AppShell` (`lib/features/shell/app_shell.dart`) needs to grow a 4th entry.

---

## File Structure

New files:
- `lib/core/window/window_tray_controller.dart` — owns `window_manager` setup (fixed size, non-resizable, prevent-close) and `tray_manager` setup (icon, context menu, listeners); shows the one-time "runs in background" message.
- `lib/core/window/background_notice_store.dart` — tiny persisted "have we shown the background notice yet" flag (same file-based pattern as `device_id_provider.dart`).
- `lib/core/di/autostart_service.dart` — thin wrapper around `launch_at_startup` (`setup`/`enable`/`disable`/`isEnabled`) plus a Riverpod provider exposing the current enabled state.
- `lib/features/settings/settings_screen.dart` — new Settings tab body (autostart toggle for now).

Modified files:
- `pubspec.yaml` — add `launch_at_startup`, `package_info_plus`.
- `lib/main.dart` — initialize `WindowTrayController` before `runApp`.
- `lib/features/shell/app_shell.dart` — add `SettingsScreen` as a 4th `NavShell` child/destination.
- `macos/Runner/MainFlutterWindow.swift` — add the `launch_at_startup` method-channel handler (per the package's documented macOS setup; unverified here, see Task 5).

---

### Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `launch_at_startup` and `package_info_plus` packages available for import.

- [ ] **Step 1: Add the packages**

Run:
```bash
flutter pub add launch_at_startup package_info_plus
```

Expected: both added to `pubspec.yaml` under `dependencies` with `^`-constrained versions (don't hand-pin exact versions — consistent with how every other dependency in this project was added). `window_manager`/`tray_manager` are already present from an earlier milestone; no change needed for those.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add launch_at_startup and package_info_plus dependencies"
```

---

### Task 2: Background-notice persistence

**Files:**
- Create: `lib/core/window/background_notice_store.dart`
- Test: `test/core/window/background_notice_store_test.dart`

**Interfaces:**
- Produces: `class BackgroundNoticeStore { Future<bool> hasBeenShown(); Future<void> markShown(); }` — reads/writes a flag file under the app support directory.

This is the one piece of Task 3's controller that's cleanly unit-testable in isolation (plain file I/O, no native window/tray calls) — split out for that reason, same rationale as why `sync_folder_provider.dart`'s path helpers are separate from its native-call methods.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/window/background_notice_store_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/background_notice_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_notice_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('has not been shown before markShown is called', () async {
    final store = BackgroundNoticeStore(supportDirectory: tempDir);
    expect(await store.hasBeenShown(), isFalse);
  });

  test('reports shown after markShown, and persists across instances', () async {
    final store = BackgroundNoticeStore(supportDirectory: tempDir);
    await store.markShown();

    expect(await store.hasBeenShown(), isTrue);
    // A fresh instance reading the same directory sees the same flag —
    // proves this is real file persistence, not in-memory state.
    final freshStore = BackgroundNoticeStore(supportDirectory: tempDir);
    expect(await freshStore.hasBeenShown(), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/window/background_notice_store_test.dart`
Expected: FAIL — `package:hickory/core/window/background_notice_store.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/window/background_notice_store.dart
import 'dart:io';

import 'package:path/path.dart' as p;

/// Tracks whether the user has already been shown the one-time "Hickory
/// keeps running in the background" message after their first
/// minimize/close-to-tray. Takes the support directory as a constructor
/// parameter (rather than resolving it internally via path_provider) so
/// it's trivially testable against a temp directory — the real caller
/// passes `await getApplicationSupportDirectory()`.
class BackgroundNoticeStore {
  BackgroundNoticeStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _flagFile => File(p.join(supportDirectory.path, 'background_notice_shown'));

  Future<bool> hasBeenShown() => _flagFile.exists();

  Future<void> markShown() async {
    await _flagFile.create(recursive: true);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/window/background_notice_store_test.dart`
Expected: PASS (2 tests) — plain `test()`, fast.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/core/window/background_notice_store.dart test/core/window/background_notice_store_test.dart
git commit -m "Add BackgroundNoticeStore for the one-time tray-minimize message"
```

---

### Task 3: WindowTrayController

**Files:**
- Create: `lib/core/window/window_tray_controller.dart`

**Interfaces:**
- Consumes: `BackgroundNoticeStore` (Task 2).
- Produces: `class WindowTrayController { Future<void> initialize(); }` — call once from `main()` before `runApp`.

Native window/tray behavior isn't unit-testable in this environment (no headless windowing harness) — this task's verification is `flutter analyze` plus the manual check in Task 6. Keep the file focused: window setup, tray setup, and the close/minimize → hide-and-notify wiring, nothing else.

- [ ] **Step 1: Write the implementation**

```dart
// lib/core/window/window_tray_controller.dart
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
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: _windowSize, center: true, title: 'Hickory'),
      () async {
        await windowManager.setResizable(false);
        await windowManager.setMinimumSize(_windowSize);
        await windowManager.setMaximumSize(_windowSize);
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      },
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

Note: the tray icon path branches by platform because `tray_manager` expects a platform-appropriate icon format (`.ico` on Windows, `.png` on macOS) — Windows already has `windows/runner/resources/app_icon.ico` from the default Flutter template; macOS needs a `assets/tray_icon.png` added as a project asset (Task 5 handles the macOS-specific pieces this depends on; for now on Windows this path resolves and works, on macOS it will need that asset added before the tray icon shows correctly there — noted as a follow-up in Task 5's report rather than blocking this task, since this task can't be verified on macOS regardless).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/window/window_tray_controller.dart
git commit -m "Add WindowTrayController: fixed window size, minimize/close to tray"
```

---

### Task 4: Wire WindowTrayController into main.dart and app.dart

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `WindowTrayController` (Task 3).

- [ ] **Step 1: Update main.dart**

Current `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: HickoryApp()));
}
```

New `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/window/window_tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final windowTrayController = WindowTrayController();
  await windowTrayController.initialize();

  runApp(
    ProviderScope(
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );
}
```

- [ ] **Step 2: Update app.dart to accept and wire the scaffold messenger key**

Read the current `lib/app.dart` first (it was last touched by the Electric Violet redesign plan's Task 10 — confirm its exact current content before editing, since this plan doesn't have that file's full text memorized). Add a required `scaffoldMessengerKey` constructor parameter to `HickoryApp` and pass it to `MaterialApp(scaffoldMessengerKey: ...)`, keeping every other existing field (`title`, `theme`, `darkTheme`, `home`) unchanged.

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: all existing tests still pass — check whether any test directly constructs `HickoryApp()` (search `grep -rn "HickoryApp(" test/`); if so, update that call site to pass a `GlobalKey<ScaffoldMessengerState>()` too.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/app.dart
git commit -m "Wire WindowTrayController into app startup"
```

---

### Task 5: Autostart service + Settings tab

**Files:**
- Create: `lib/core/di/autostart_service.dart`
- Create: `lib/features/settings/settings_screen.dart`
- Modify: `lib/features/shell/app_shell.dart`
- Modify: `macos/Runner/MainFlutterWindow.swift` (macOS-only, unverified — see below)

**Interfaces:**
- Produces: `autostartServiceProvider` (`Provider<AutostartService>`), `class AutostartService { Future<void> setup(); Future<bool> isEnabled(); Future<void> setEnabled(bool value); }`; `SettingsScreen` (body-only, no own `Scaffold`).
- Consumes (in `app_shell.dart`): adds `SettingsScreen` as a 4th `NavShell` child/destination — no FAB on this tab (`fabBuilder` only returns non-null at index 0, same as today).

- [ ] **Step 1: Write AutostartService**

```dart
// lib/core/di/autostart_service.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Thin wrapper around launch_at_startup so the rest of the app depends on
/// a small local interface instead of the package directly.
class AutostartService {
  Future<void> setup() async {
    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      packageName: 'com.hickory.hickory',
    );
  }

  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  Future<void> setEnabled(bool value) {
    return value ? launchAtStartup.enable() : launchAtStartup.disable();
  }
}

final autostartServiceProvider = Provider<AutostartService>((ref) => AutostartService());
```

`setup()` must be called once before `isEnabled()`/`setEnabled()` are used — call it from `main()` alongside `WindowTrayController.initialize()` (this step is folded into this task's file changes below rather than touching `main.dart` again in a separate task).

- [ ] **Step 2: Call AutostartService.setup() from main.dart**

Add to `lib/main.dart` (from Task 4), right after `WidgetsFlutterBinding.ensureInitialized()`:

```dart
  await AutostartService().setup();
```

with the corresponding import (`import 'core/di/autostart_service.dart';`). This is a one-off setup call, not read through the provider (the provider is for the widget tree's `isEnabled`/`setEnabled` calls afterward).

- [ ] **Step 3: Write SettingsScreen**

```dart
// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/autostart_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _autostartEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAutostartState();
  }

  Future<void> _loadAutostartState() async {
    final enabled = await ref.read(autostartServiceProvider).isEnabled();
    if (!mounted) return;
    setState(() {
      _autostartEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setAutostart(bool value) async {
    setState(() => _autostartEnabled = value);
    await ref.read(autostartServiceProvider).setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Einstellungen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  )
                : SwitchListTile(
                    title: const Text('Beim Systemstart öffnen'),
                    value: _autostartEnabled,
                    onChanged: _setAutostart,
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add SettingsScreen as a 4th tab in AppShell**

Read the current `lib/features/shell/app_shell.dart` first (built by the Electric Violet redesign plan's Task 10; confirm its exact current content before editing). Add:
- an import for `settings_screen.dart`,
- `const SettingsScreen()` as a 4th entry in the `children` list passed to `NavShell`,
- a 4th `NavigationDestination` (`icon: Icon(Icons.settings_outlined)`, `selectedIcon: Icon(Icons.settings)`, `label: 'Einstellungen'`) as a 4th entry in `_destinations`, in the same order as the children list,

leaving the existing `fabBuilder` unchanged (`selectedIndex == 0` still means only the Timer tab gets the FAB — index 0 doesn't move since Settings is appended at the end, index 3).

- [ ] **Step 5: macOS native wiring (unverified — cannot build/test on this machine)**

Per `launch_at_startup`'s documented macOS support, add to `macos/Runner/MainFlutterWindow.swift`. Read the current file first, then add the import and method channel handler shown below, keeping the rest of the file (in particular `RegisterGeneratedPlugins` and the `super.awakeFromNib()` call) exactly where they already are relative to `flutterViewController` setup:

```swift
import Cocoa
import FlutterMacOS
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    FlutterMethodChannel(
      name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtLogin.isEnabled)
      case "launchAtStartupSetEnabled":
        if let arguments = call.arguments as? [String: Any] {
          LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
```

This also requires adding the `LaunchAtLogin` Swift package as an Xcode dependency (Xcode → project → Package Dependencies → add `https://github.com/sindresorhus/LaunchAtLogin`) and enabling the "Login Item" capability — both are Xcode-GUI steps that can't be scripted from here. Note this explicitly in the report as a manual follow-up required before the macOS build will compile, exactly like the Electric Violet plan's `activity_tracker` macOS Swift code was flagged as written-but-unverified.

- [ ] **Step 6: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: all tests still pass.

- [ ] **Step 8: Commit**

```bash
git add lib/core/di/autostart_service.dart lib/features/settings/settings_screen.dart lib/features/shell/app_shell.dart lib/main.dart macos/Runner/MainFlutterWindow.swift
git commit -m "Add autostart toggle and a new Settings tab"
```

---

### Task 6: Manual verification

**Files:** none (verification only).

- [ ] **Step 1: Build**

```powershell
flutter build windows --debug
```

Expected: `✓ Built build\windows\x64\runner\Debug\hickory.exe`

- [ ] **Step 2: Launch and check window sizing**

Launch the exe. Confirm: it opens at a fixed slim size (~400×800), centered. Try dragging an edge/corner — it should not resize. Try maximizing (if the maximize button is even present) — it should have no effect or be disabled.

- [ ] **Step 3: Check minimize-to-tray**

Click the window's minimize button. Confirm: the window disappears from the taskbar, a tray icon appears in the system tray, and (first time only) a snackbar/message about running in the background was visible just before the window hid. Left-click the tray icon — window should restore. Minimize again — no repeat message this time (already marked shown).

- [ ] **Step 4: Check close-to-tray**

Click the window's X (close) button. Confirm: same hide-to-tray behavior as minimize, window does not actually exit the process (check `Get-Process hickory` still shows it running). Right-click the tray icon, confirm "Öffnen"/"Beenden" menu items appear; click "Öffnen" to restore, then use "Beenden" to actually quit and confirm the process exits.

- [ ] **Step 5: Check autostart toggle**

Relaunch, navigate to the new "Einstellungen" tab (4th bottom-nav destination), confirm it's reachable and shows the autostart switch (off by default). Toggle it on, then check (PowerShell) whether the OS registered it:

```powershell
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" | Select-Object -ExpandProperty * -ErrorAction SilentlyContinue
```

or check the Startup Apps list in Windows Settings / Task Manager's Startup tab for a "Hickory" (or `hickory.exe`) entry. Toggle it off again and confirm the entry disappears.

- [ ] **Step 6: Clean up test processes**

```powershell
Stop-Process -Name hickory -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 7: Final full-suite check**

```bash
flutter analyze
flutter test
```

Expected: both clean/green.

---

## Self-Review Notes

- **Spec coverage:** fixed window size + locked (Task 3), minimize/close → tray with one-time message (Tasks 2-3), autostart toggle (Task 5), new Settings tab (Task 5), macOS-specific autostart wiring flagged as unverified (Task 5 Step 5) consistent with how the redesign plan handled macOS-only code.
- **Placeholder scan:** none found.
- **Type consistency:** `WindowTrayController.scaffoldMessengerKey` (Task 3) matches its usage in `main.dart`/`app.dart` (Task 4); `AutostartService`'s three methods (Task 5 Step 1) match `SettingsScreen`'s usage (Task 5 Step 3).
- **Open item requiring judgment during implementation:** Tasks 4 and 5 both say "read the current file first" for `app.dart`/`app_shell.dart` instead of showing complete before/after code, because this plan was written without re-reading those files' latest state (they were last touched by a different, already-executed plan). This is a deliberate deviation from "always show complete code" — the implementer should treat the described change (add one constructor parameter; add one list entry each to two parallel lists) as the actual spec, and include the real before/after diff in their commit and report.
