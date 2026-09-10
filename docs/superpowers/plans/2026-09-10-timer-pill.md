# Floating Timer Pill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While a timer runs, Hickory's window can collapse into a frameless, always-on-top 320×56 pill showing the elapsed time and client · project, with pause/resume, stop and expand controls, draggable anywhere and remembering where it was put.

**Architecture:** The pill is a *mode of the single existing window*, not a second window. A `WindowModeController` owns every native window call needed to move between `full` and `pill`; a Riverpod notifier exposes the mode; `MaterialApp.home` switches between `AppShell` and `PillScreen`. Because the pill replaces the widget tree, the four background subscriptions that `TimerScreen` currently holds must first move to an always-mounted host.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `window_manager` 0.5.2, `screen_retriever` (transitive), Riverpod 3, Drift, `mocktail` for fakes, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-10-timer-pill-design.md`

## Global Constraints

- Pill size is exactly `Size(320, 56)`; main-window minimum size is exactly `Size(480, 960)` (the existing `WindowTrayController._minimumSize`).
- Every user-facing string goes through `AppLocalizations`. New keys must be added to **all six** ARB files: `lib/l10n/app_de.arb` (template), `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`.
- No new colour literals. Use `HickoryColors.of(context)` tokens and `Theme.of(context)`.
- Icon-only buttons require both a `Tooltip` and a `Semantics` label.
- Elapsed time is rendered with `formatDuration(...)` from `lib/core/format/duration_format.dart` — never a hand-rolled formatter.
- Verification commands: `flutter analyze` and `flutter test` (there is no justfile in this repo).
- Do not add dependencies. `window_manager` and `screen_retriever` are already present.
- Windows is unverified for the frameless round trip (spec §8.2). Do not claim Windows support in any comment or doc.

---

### Task 1: Pill position persistence

`WindowBoundsStore` already does exactly what the pill needs, hardcoded to one filename. Give it a `fileName` parameter instead of writing a second, near-identical class.

**Files:**
- Modify: `lib/core/window/window_bounds_store.dart`
- Test: `test/core/window/window_bounds_store_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `WindowBoundsStore({required Directory supportDirectory, String fileName = 'window_bounds.json'})`, with `Future<Rect?> read()` and `Future<void> write(Rect bounds)` unchanged. A pill store is `WindowBoundsStore(supportDirectory: dir, fileName: 'pill_bounds.json')`.

- [ ] **Step 1: Write the failing test**

Append to `test/core/window/window_bounds_store_test.dart`:

```dart
  test('two stores with different file names keep separate bounds', () async {
    final windowStore = WindowBoundsStore(supportDirectory: tempDir);
    final pillStore = WindowBoundsStore(
      supportDirectory: tempDir,
      fileName: 'pill_bounds.json',
    );
    const windowBounds = Rect.fromLTWH(100, 100, 480, 960);
    const pillBounds = Rect.fromLTWH(1500, 40, 320, 56);

    await windowStore.write(windowBounds);
    await pillStore.write(pillBounds);

    expect(await windowStore.read(), windowBounds);
    expect(await pillStore.read(), pillBounds);
    expect(File('${tempDir.path}/pill_bounds.json').existsSync(), isTrue);
  });

  test('default file name is unchanged, so existing installs keep their bounds', () async {
    final store = WindowBoundsStore(supportDirectory: tempDir);
    await store.write(const Rect.fromLTWH(10, 20, 480, 960));
    expect(File('${tempDir.path}/window_bounds.json').existsSync(), isTrue);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/window/window_bounds_store_test.dart`
Expected: FAIL — `No named parameter with the name 'fileName'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/core/window/window_bounds_store.dart`, replace the constructor and `_boundsFile` getter:

```dart
  WindowBoundsStore({
    required this.supportDirectory,
    this.fileName = 'window_bounds.json',
  });

  final Directory supportDirectory;

  /// Which file inside [supportDirectory] this instance owns. Defaults to the
  /// main window's bounds; the pill passes 'pill_bounds.json' so dragging the
  /// pill can't overwrite the main window's remembered size.
  final String fileName;

  File get _boundsFile => File(p.join(supportDirectory.path, fileName));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/window/window_bounds_store_test.dart`
Expected: PASS (all six tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/window/window_bounds_store.dart test/core/window/window_bounds_store_test.dart
git commit -m "feat(window): let the bounds store address a named file"
```

---

### Task 2: WindowMode enum and the native-window seam

`windowManager` is a plugin singleton and unreachable in tests, so the controller talks to a narrow interface instead.

**Files:**
- Create: `lib/core/window/window_mode.dart`
- Create: `lib/core/window/native_window.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `enum WindowMode { full, pill }`; `abstract interface class NativeWindow` with `setSize`, `setPosition`, `setMinimumSize`, `setResizable`, `setAlwaysOnTop`, `setTitleBarHidden`, `getBounds`, `getDisplaySize`; `class WindowManagerNativeWindow implements NativeWindow`.

- [ ] **Step 1: Create the enum**

Create `lib/core/window/window_mode.dart`:

```dart
/// Which shape the single Hickory window currently has. See
/// docs/superpowers/specs/2026-09-10-timer-pill-design.md.
enum WindowMode {
  /// The normal app window: resizable, title bar, minimum 480x960.
  full,

  /// The frameless 320x56 always-on-top timer pill.
  pill,
}
```

- [ ] **Step 2: Create the interface and its production implementation**

Create `lib/core/window/native_window.dart`:

```dart
import 'dart:ui' show Offset, Rect, Size;

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// The slice of the native window Hickory drives when switching between
/// [WindowMode]s. Exists so WindowModeController is testable: `windowManager`
/// is a plugin singleton backed by a platform channel and cannot be exercised
/// in a unit test.
abstract interface class NativeWindow {
  Future<void> setSize(Size size);
  Future<void> setPosition(Offset position);
  Future<void> setMinimumSize(Size size);
  Future<void> setResizable(bool resizable);
  Future<void> setAlwaysOnTop(bool alwaysOnTop);

  /// Hides or restores the OS title bar (and its window buttons).
  Future<void> setTitleBarHidden(bool hidden);

  Future<Rect> getBounds();

  /// Logical size of the display the window is currently on, used to place
  /// the pill top-right the first time it is shown.
  Future<Size> getDisplaySize();
}

/// Production [NativeWindow], delegating to window_manager / screen_retriever.
class WindowManagerNativeWindow implements NativeWindow {
  const WindowManagerNativeWindow();

  @override
  Future<void> setSize(Size size) => windowManager.setSize(size);

  @override
  Future<void> setPosition(Offset position) => windowManager.setPosition(position);

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> setResizable(bool resizable) => windowManager.setResizable(resizable);

  @override
  Future<void> setAlwaysOnTop(bool alwaysOnTop) =>
      windowManager.setAlwaysOnTop(alwaysOnTop);

  @override
  Future<void> setTitleBarHidden(bool hidden) => windowManager.setTitleBarStyle(
    hidden ? TitleBarStyle.hidden : TitleBarStyle.normal,
    windowButtonVisibility: !hidden,
  );

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<Size> getDisplaySize() async {
    final display = await screenRetriever.getPrimaryDisplay();
    return display.visibleSize ?? display.size;
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/core/window/`
Expected: "No issues found." If `screen_retriever` is not importable, add it to `pubspec.yaml` `dependencies` **without a version pin beyond what `pubspec.lock` already resolves** (`screen_retriever: any` is wrong — copy the resolved version's caret range) and re-run.

- [ ] **Step 4: Commit**

```bash
git add lib/core/window/window_mode.dart lib/core/window/native_window.dart
git commit -m "feat(window): add window mode enum and native window seam"
```

---

### Task 3: WindowModeController

The heart of the feature, and the part the spike's findings are encoded in: minimum size must come **down before** the size, and the position must be set **explicitly after** the title bar changes, because the frame origin shifts by the title-bar height (spec §8.1).

**Files:**
- Create: `lib/core/window/window_mode_controller.dart`
- Test: `test/core/window/window_mode_controller_test.dart`

**Interfaces:**
- Consumes: `NativeWindow`, `WindowMode` (Task 2), `WindowBoundsStore` with `fileName` (Task 1)
- Produces: `WindowModeController({required NativeWindow window, required WindowBoundsStore fullBounds, required WindowBoundsStore pillBounds})` with `WindowMode get mode`, `Future<void> collapse()`, `Future<void> expand()`, `Future<void> persistCurrentBounds()`, and the constants `WindowModeController.pillSize` (`Size(320, 56)`) and `WindowModeController.fullMinimumSize` (`Size(480, 960)`).

- [ ] **Step 1: Write the failing test**

Create `test/core/window/window_mode_controller_test.dart`:

```dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/native_window.dart';
import 'package:hickory/core/window/window_bounds_store.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockNativeWindow extends Mock implements NativeWindow {}

void main() {
  late Directory tempDir;
  late _MockNativeWindow window;
  late WindowBoundsStore fullBounds;
  late WindowBoundsStore pillBounds;
  late WindowModeController controller;

  setUpAll(() {
    registerFallbackValue(Size.zero);
    registerFallbackValue(Offset.zero);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_window_mode_test_');
    window = _MockNativeWindow();
    when(() => window.setSize(any())).thenAnswer((_) async {});
    when(() => window.setPosition(any())).thenAnswer((_) async {});
    when(() => window.setMinimumSize(any())).thenAnswer((_) async {});
    when(() => window.setResizable(any())).thenAnswer((_) async {});
    when(() => window.setAlwaysOnTop(any())).thenAnswer((_) async {});
    when(() => window.setTitleBarHidden(any())).thenAnswer((_) async {});
    when(() => window.getBounds())
        .thenAnswer((_) async => const Rect.fromLTWH(200, 100, 480, 960));
    when(() => window.getDisplaySize()).thenAnswer((_) async => const Size(1920, 1080));

    fullBounds = WindowBoundsStore(supportDirectory: tempDir);
    pillBounds = WindowBoundsStore(
      supportDirectory: tempDir,
      fileName: 'pill_bounds.json',
    );
    controller = WindowModeController(
      window: window,
      fullBounds: fullBounds,
      pillBounds: pillBounds,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('starts in full mode', () {
    expect(controller.mode, WindowMode.full);
  });

  test('collapse lowers the minimum size before setting the size', () async {
    await controller.collapse();

    verifyInOrder([
      () => window.setMinimumSize(WindowModeController.pillSize),
      () => window.setSize(WindowModeController.pillSize),
    ]);
    expect(controller.mode, WindowMode.pill);
  });

  test('collapse sets the position after hiding the title bar', () async {
    // The frame origin shifts by the title-bar height when it disappears
    // (spec 8.1), so the position must be applied once the frame is final.
    await controller.collapse();

    verifyInOrder([
      () => window.setTitleBarHidden(true),
      () => window.setPosition(any()),
    ]);
  });

  test('collapse makes the window a fixed always-on-top pill', () async {
    await controller.collapse();

    verify(() => window.setResizable(false)).called(1);
    verify(() => window.setAlwaysOnTop(true)).called(1);
  });

  test('collapse saves the full-window bounds so expand can restore them', () async {
    await controller.collapse();

    expect(await fullBounds.read(), const Rect.fromLTWH(200, 100, 480, 960));
  });

  test('first collapse places the pill top-right of the display', () async {
    await controller.collapse();

    // 1920 - 320 - 16 margin = 1584, 16 margin from the top.
    verify(() => window.setPosition(const Offset(1584, 16))).called(1);
  });

  test('a later collapse restores the pill where the user left it', () async {
    await pillBounds.write(const Rect.fromLTWH(640, 900, 320, 56));

    await controller.collapse();

    verify(() => window.setPosition(const Offset(640, 900))).called(1);
  });

  test('expand restores minimum size, resizable, title bar and always-on-top', () async {
    await fullBounds.write(const Rect.fromLTWH(200, 100, 480, 960));
    await controller.collapse();

    await controller.expand();

    verify(() => window.setAlwaysOnTop(false)).called(1);
    verify(() => window.setResizable(true)).called(1);
    verify(() => window.setTitleBarHidden(false)).called(1);
    verify(() => window.setMinimumSize(WindowModeController.fullMinimumSize)).called(1);
    verify(() => window.setSize(const Size(480, 960))).called(1);
    verify(() => window.setPosition(const Offset(200, 100))).called(1);
    expect(controller.mode, WindowMode.full);
  });

  test('expand raises the minimum size before setting the size', () async {
    await controller.collapse();

    await controller.expand();

    verifyInOrder([
      () => window.setMinimumSize(WindowModeController.fullMinimumSize),
      () => window.setSize(WindowModeController.fullMinimumSize),
    ]);
  });

  test('expand falls back to the minimum size when nothing was saved', () async {
    controller = WindowModeController(
      window: window,
      fullBounds: WindowBoundsStore(
        supportDirectory: tempDir,
        fileName: 'absent.json',
      ),
      pillBounds: pillBounds,
    );

    await controller.expand();

    verify(() => window.setSize(WindowModeController.fullMinimumSize)).called(1);
  });

  test('persistCurrentBounds writes to the pill store while in pill mode', () async {
    await controller.collapse();
    when(() => window.getBounds())
        .thenAnswer((_) async => const Rect.fromLTWH(700, 300, 320, 56));

    await controller.persistCurrentBounds();

    expect(await pillBounds.read(), const Rect.fromLTWH(700, 300, 320, 56));
  });

  test('persistCurrentBounds writes to the full store while in full mode', () async {
    when(() => window.getBounds())
        .thenAnswer((_) async => const Rect.fromLTWH(50, 60, 700, 1000));

    await controller.persistCurrentBounds();

    expect(await fullBounds.read(), const Rect.fromLTWH(50, 60, 700, 1000));
    expect(await pillBounds.read(), isNull);
  });

  test('a failing store never blocks the mode switch', () async {
    controller = WindowModeController(
      window: window,
      fullBounds: WindowBoundsStore(
        supportDirectory: Directory('/definitely/not/writable'),
      ),
      pillBounds: pillBounds,
    );

    await controller.collapse();

    expect(controller.mode, WindowMode.pill);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/window/window_mode_controller_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hickory/core/window/window_mode_controller.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/window/window_mode_controller.dart`:

```dart
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart' show debugPrint;

import 'native_window.dart';
import 'window_bounds_store.dart';
import 'window_mode.dart';

/// Drives the single Hickory window between [WindowMode.full] and
/// [WindowMode.pill]. The only place that reshapes the window for the timer
/// pill, and the seam where a future "show over full-screen apps" setting
/// belongs (spec section 3).
///
/// Side effects: every method touches the native window and the two bounds
/// stores. Store failures are swallowed on purpose -- a window that refuses
/// to change shape because a preference file could not be written would be a
/// worse bug than a forgotten position.
class WindowModeController {
  WindowModeController({
    required NativeWindow window,
    required WindowBoundsStore fullBounds,
    required WindowBoundsStore pillBounds,
  }) : _window = window,
       _fullBounds = fullBounds,
       _pillBounds = pillBounds;

  /// Fixed pill footprint. Wide enough for the elapsed time, three icon
  /// buttons and an ellipsized "client - project" line.
  static const pillSize = Size(320, 56);

  /// Mirrors WindowTrayController's minimum for the normal window.
  static const fullMinimumSize = Size(480, 960);

  /// Gap from the display edge when the pill has never been dragged.
  static const _defaultMargin = 16.0;

  final NativeWindow _window;
  final WindowBoundsStore _fullBounds;
  final WindowBoundsStore _pillBounds;

  WindowMode _mode = WindowMode.full;
  WindowMode get mode => _mode;

  /// Shrinks the window to the pill. Restores the pill's last position, or
  /// places it top-right of the display the first time.
  Future<void> collapse() async {
    if (_mode == WindowMode.pill) return;
    await _persist(_fullBounds);
    final position = await _pillPosition();

    // Order matters: the minimum size has to come down first or the window
    // stays stuck at 480 wide. The position is applied last because hiding
    // the title bar shifts the frame origin by its height (spec 8.1).
    await _window.setMinimumSize(pillSize);
    await _window.setTitleBarHidden(true);
    await _window.setSize(pillSize);
    await _window.setPosition(position);
    await _window.setResizable(false);
    await _window.setAlwaysOnTop(true);
    _mode = WindowMode.pill;
  }

  /// Restores the normal window, putting it back where it was before the
  /// last [collapse].
  Future<void> expand() async {
    if (_mode == WindowMode.pill) await _persist(_pillBounds);
    final saved = await _fullBounds.read();
    final size = saved == null ? fullMinimumSize : Size(saved.width, saved.height);

    await _window.setAlwaysOnTop(false);
    await _window.setResizable(true);
    await _window.setTitleBarHidden(false);
    await _window.setMinimumSize(fullMinimumSize);
    await _window.setSize(size);
    if (saved != null) await _window.setPosition(saved.topLeft);
    _mode = WindowMode.full;
  }

  /// Writes the current bounds to whichever store owns the current mode.
  /// Called from the window's move/resize listeners.
  Future<void> persistCurrentBounds() =>
      _persist(_mode == WindowMode.pill ? _pillBounds : _fullBounds);

  Future<Offset> _pillPosition() async {
    final saved = await _pillBounds.read();
    if (saved != null) return saved.topLeft;
    try {
      final display = await _window.getDisplaySize();
      return Offset(display.width - pillSize.width - _defaultMargin, _defaultMargin);
    } catch (e) {
      debugPrint('Display size unavailable, placing pill at the margin: $e');
      return const Offset(_defaultMargin, _defaultMargin);
    }
  }

  Future<void> _persist(WindowBoundsStore store) async {
    try {
      await store.write(await _window.getBounds());
    } catch (e) {
      // Best-effort, matching WindowTrayController._persistBounds.
      debugPrint('Window bounds not persisted: $e');
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/window/window_mode_controller_test.dart`
Expected: PASS — 13 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/window/window_mode_controller.dart test/core/window/window_mode_controller_test.dart
git commit -m "feat(window): add window mode controller for the timer pill"
```

---

### Task 4: Expose the mode to the widget tree and route bounds writes

`WindowTrayController` currently writes every move and resize to the main-window store. In pill mode it must write to the pill store instead — otherwise dragging the pill overwrites the main window's remembered size.

**Files:**
- Create: `lib/core/window/window_mode_provider.dart`
- Modify: `lib/core/window/window_tray_controller.dart`
- Modify: `lib/main.dart`
- Test: `test/core/window/window_mode_provider_test.dart`

**Interfaces:**
- Consumes: `WindowModeController` (Task 3)
- Produces: `windowModeControllerProvider` (a `Provider<WindowModeController>` that must be overridden at startup), `windowModeProvider` (`NotifierProvider<WindowModeNotifier, WindowMode>`) with `collapse()` and `expand()` methods on the notifier.

- [ ] **Step 1: Write the failing test**

Create `test/core/window/window_mode_provider_test.dart`:

```dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/native_window.dart';
import 'package:hickory/core/window/window_bounds_store.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_controller.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:mocktail/mocktail.dart';

class _MockNativeWindow extends Mock implements NativeWindow {}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(Size.zero);
    registerFallbackValue(Offset.zero);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_window_mode_provider_');
    final window = _MockNativeWindow();
    when(() => window.setSize(any())).thenAnswer((_) async {});
    when(() => window.setPosition(any())).thenAnswer((_) async {});
    when(() => window.setMinimumSize(any())).thenAnswer((_) async {});
    when(() => window.setResizable(any())).thenAnswer((_) async {});
    when(() => window.setAlwaysOnTop(any())).thenAnswer((_) async {});
    when(() => window.setTitleBarHidden(any())).thenAnswer((_) async {});
    when(() => window.getBounds())
        .thenAnswer((_) async => const Rect.fromLTWH(0, 0, 480, 960));
    when(() => window.getDisplaySize()).thenAnswer((_) async => const Size(1920, 1080));

    container = ProviderContainer(
      overrides: [
        windowModeControllerProvider.overrideWithValue(
          WindowModeController(
            window: window,
            fullBounds: WindowBoundsStore(supportDirectory: tempDir),
            pillBounds: WindowBoundsStore(
              supportDirectory: tempDir,
              fileName: 'pill_bounds.json',
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('starts in full mode', () {
    expect(container.read(windowModeProvider), WindowMode.full);
  });

  test('collapse then expand round-trips the exposed mode', () async {
    await container.read(windowModeProvider.notifier).collapse();
    expect(container.read(windowModeProvider), WindowMode.pill);

    await container.read(windowModeProvider.notifier).expand();
    expect(container.read(windowModeProvider), WindowMode.full);
  });

  test('collapsing twice is a no-op, not an error', () async {
    final notifier = container.read(windowModeProvider.notifier);
    await notifier.collapse();
    await notifier.collapse();
    expect(container.read(windowModeProvider), WindowMode.pill);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/window/window_mode_provider_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hickory/core/window/window_mode_provider.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/window/window_mode_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'window_mode.dart';
import 'window_mode_controller.dart';

/// The app's single [WindowModeController]. Overridden in main() with an
/// instance built against the real support directory; reading it without an
/// override is a programming error, hence the throw rather than a fallback.
final windowModeControllerProvider = Provider<WindowModeController>((ref) {
  throw StateError('windowModeControllerProvider must be overridden in main()');
});

/// The current window shape, for widgets that render differently per mode.
/// Call [WindowModeNotifier.collapse] / [WindowModeNotifier.expand] rather
/// than touching the controller directly, so the exposed state and the native
/// window can never disagree.
class WindowModeNotifier extends Notifier<WindowMode> {
  @override
  WindowMode build() => ref.read(windowModeControllerProvider).mode;

  Future<void> collapse() async {
    final controller = ref.read(windowModeControllerProvider);
    await controller.collapse();
    state = controller.mode;
  }

  Future<void> expand() async {
    final controller = ref.read(windowModeControllerProvider);
    await controller.expand();
    state = controller.mode;
  }
}

final windowModeProvider = NotifierProvider<WindowModeNotifier, WindowMode>(
  WindowModeNotifier.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/window/window_mode_provider_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Route the tray controller's bounds writes through the mode controller**

In `lib/core/window/window_tray_controller.dart`, add a field next to `backgroundNoticeMessage`:

```dart
  /// Persists the current bounds into whichever store owns the current window
  /// mode. Set by `main()` for the same reason as [onBeforeQuit]: this
  /// controller deliberately has no provider access. Null until then, in which
  /// case move/resize events fall back to the main-window store below.
  Future<void> Function()? persistBoundsForCurrentMode;
```

Then replace the body of `_persistBounds`:

```dart
  Future<void> _persistBounds() async {
    final persist = persistBoundsForCurrentMode;
    if (persist != null) {
      await persist();
      return;
    }
    final store = _boundsStore;
    if (store == null) return;
    try {
      final bounds = await windowManager.getBounds();
      await store.write(bounds);
    } catch (_) {
      // Best-effort -- see doc comment above.
    }
  }
```

- [ ] **Step 6: Wire it up in main()**

In `lib/main.dart`, after `final container = ProviderContainer();` is created, replace that line with an override-carrying container and connect the callback. Insert the import `import 'core/window/native_window.dart';`, `import 'core/window/window_mode_controller.dart';`, `import 'core/window/window_mode_provider.dart';` and `import 'package:path_provider/path_provider.dart';` (if not already imported), then:

```dart
  final supportDir = await getApplicationSupportDirectory();
  final windowModeController = WindowModeController(
    window: const WindowManagerNativeWindow(),
    fullBounds: WindowBoundsStore(supportDirectory: supportDir),
    pillBounds: WindowBoundsStore(
      supportDirectory: supportDir,
      fileName: 'pill_bounds.json',
    ),
  );
  final container = ProviderContainer(
    overrides: [
      windowModeControllerProvider.overrideWithValue(windowModeController),
    ],
  );
```

and after `windowTrayController.onBeforeQuit = ...`:

```dart
  windowTrayController.persistBoundsForCurrentMode =
      windowModeController.persistCurrentBounds;
```

Add `import 'core/window/window_bounds_store.dart';` if it is not already there.

- [ ] **Step 7: Run the full suite and the analyzer**

Run: `flutter analyze && flutter test`
Expected: "No issues found." and all tests passing.

- [ ] **Step 8: Commit**

```bash
git add lib/core/window/window_mode_provider.dart lib/core/window/window_tray_controller.dart lib/main.dart test/core/window/window_mode_provider_test.dart
git commit -m "feat(window): expose window mode and route bounds per mode"
```

---

### Task 5: Lift TimerScreen's background subscriptions

**This task fixes a latent bug and must land before the tree can be swapped.** `TimerScreen.build()` starts `syncWatcherProvider`, `jiraAutoSyncProvider` and two listeners, relying on the tab always being mounted inside `NavShell`'s `IndexedStack`. Once the pill replaces the tree, `TimerScreen` unmounts and idle detection, activity sampling and Jira auto-sync would stop exactly while a timer runs.

**Files:**
- Create: `lib/features/shell/background_services.dart`
- Modify: `lib/features/timer/timer_screen.dart`
- Modify: `lib/app.dart`
- Test: `test/features/shell/background_services_test.dart`

**Interfaces:**
- Consumes: `syncWatcherProvider` (`lib/core/di/sync_providers.dart`), `jiraAutoSyncProvider` (`lib/core/di/jira_providers.dart`), `idleSecondsProvider` and `activeWindowChangesProvider` (`lib/features/timer/idle_tracking.dart`), `runningEntryProvider` (`lib/features/timer/timer_providers.dart`)
- Produces: `class BackgroundServices extends ConsumerStatefulWidget` taking a required `Widget child`, plus a required `void Function(int idleSeconds) onIdle` and `void Function(ActivitySample sample) onActivity` so the existing handlers keep their current homes.

- [ ] **Step 1: Write the failing test**

Create `test/features/shell/background_services_test.dart`:

```dart
import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/shell/background_services.dart';
import 'package:hickory/features/timer/idle_tracking.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          idleSecondsProvider.overrideWith((ref) => const Stream<int>.empty()),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
        ],
        child: MaterialApp(
          home: BackgroundServices(
            onIdle: (_) {},
            onActivity: (_) {},
            child: const Text('child'),
          ),
        ),
      ),
    );

    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('forwards idle seconds to the callback', (tester) async {
    final seen = <int>[];
    final idle = StreamController<int>();
    addTearDown(idle.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          idleSecondsProvider.overrideWith((ref) => idle.stream),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
        ],
        child: MaterialApp(
          home: BackgroundServices(
            onIdle: seen.add,
            onActivity: (_) {},
            child: const SizedBox(),
          ),
        ),
      ),
    );

    idle.add(400);
    await tester.pump();

    expect(seen, [400]);
  });

  testWidgets('keeps forwarding after the child is replaced', (tester) async {
    // The whole point of this widget: the pill swaps the child, and the
    // subscriptions must survive that swap.
    final seen = <int>[];
    final idle = StreamController<int>();
    addTearDown(idle.close);

    Widget build(Widget child) => ProviderScope(
      overrides: [
        idleSecondsProvider.overrideWith((ref) => idle.stream),
        activeWindowChangesProvider
            .overrideWith((ref) => const Stream<ActivitySample>.empty()),
      ],
      child: MaterialApp(
        home: BackgroundServices(
          onIdle: seen.add,
          onActivity: (_) {},
          child: child,
        ),
      ),
    );

    await tester.pumpWidget(build(const Text('full')));
    await tester.pumpWidget(build(const Text('pill')));

    idle.add(500);
    await tester.pump();

    expect(find.text('pill'), findsOneWidget);
    expect(seen, [500]);
  });
}
```

Add `import 'dart:async';` at the top of that test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/shell/background_services_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hickory/features/shell/background_services.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/shell/background_services.dart`:

```dart
import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../timer/idle_tracking.dart';

/// Holds the subscriptions that must outlive any screen: the sync folder
/// watcher, Jira auto-sync, idle detection and activity sampling.
///
/// These used to live in TimerScreen.build(), which worked only because
/// NavShell's IndexedStack keeps that tab mounted forever. The timer pill
/// replaces the whole tree, so anything anchored to a screen would stop
/// exactly while a timer runs. Side effects: starts four subscriptions for
/// as long as this widget is mounted.
class BackgroundServices extends ConsumerWidget {
  const BackgroundServices({
    super.key,
    required this.child,
    required this.onIdle,
    required this.onActivity,
  });

  final Widget child;
  final void Function(int idleSeconds) onIdle;
  final void Function(ActivitySample sample) onActivity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncWatcherProvider);
    ref.watch(jiraAutoSyncProvider);

    ref.listen<AsyncValue<int>>(idleSecondsProvider, (previous, next) {
      final idleSeconds = next.value;
      if (idleSeconds != null) onIdle(idleSeconds);
    });
    ref.listen<AsyncValue<ActivitySample>>(activeWindowChangesProvider, (
      previous,
      next,
    ) {
      final sample = next.value;
      if (sample != null) onActivity(sample);
    });

    return child;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/shell/background_services_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Move the two handlers into their own always-mounted widget**

`showIdlePromptDialog` needs a `BuildContext` below `MaterialApp`, and both handlers need
`ref`. Create `lib/features/timer/timer_background_handlers.dart`, moving
`_handleIdleSecondsChanged`, `_recordActivitySample`, `_idlePromptShowing` and
`_idleThresholdSeconds` verbatim out of `_TimerScreenState`:

```dart
import 'package:activity_tracker/activity_tracker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../shell/background_services.dart';
import 'idle_prompt_dialog.dart';
import 'timer_providers.dart';

/// Idle time is prompted about once it reaches this threshold, on desktop
/// only (see [isDesktopTrackingSupported]).
const _idleThresholdSeconds = 5 * 60;

/// Owns the idle prompt and activity sampling for the whole app.
///
/// Lives directly under MaterialApp rather than inside the timer tab: the
/// pill replaces the tab, and both concerns must keep working while it does.
/// Its context is below MaterialApp, so showIdlePromptDialog still has a
/// Navigator.
class TimerBackgroundHandlers extends ConsumerStatefulWidget {
  const TimerBackgroundHandlers({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TimerBackgroundHandlers> createState() =>
      TimerBackgroundHandlersState();
}

class TimerBackgroundHandlersState
    extends ConsumerState<TimerBackgroundHandlers> {
  bool _idlePromptShowing = false;

  Future<void> handleIdleSecondsChanged(int idleSeconds) async {
    if (idleSeconds < _idleThresholdSeconds) {
      _idlePromptShowing = false;
      return;
    }
    if (_idlePromptShowing) return;
    final running = ref.read(runningEntryProvider).value;
    if (running == null || running.pausedAt != null) return;

    _idlePromptShowing = true;
    final idleDuration = Duration(seconds: idleSeconds);
    final shouldTrim = await showIdlePromptDialog(context, idleDuration);
    if (!mounted) return;
    if (shouldTrim) {
      final writes = await ref.read(syncedWritesProvider.future);
      final idleStart = DateTime.now().subtract(idleDuration);
      await writes.updateEntry(running.id, endAt: Value(idleStart.toUtc()));
    }
    _idlePromptShowing = false;
  }

  Future<void> recordActivitySample(ActivitySample sample) async {
    final running = ref.read(runningEntryProvider).value;
    if (running == null || running.pausedAt != null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.recordActivitySample(
      deviceId: deviceId,
      appName: sample.appName,
      windowTitle: sample.windowTitle,
      observedAt: sample.observedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundServices(
      onIdle: handleIdleSecondsChanged,
      onActivity: recordActivitySample,
      child: widget.child,
    );
  }
}
```

- [ ] **Step 6: Strip the moved code out of TimerScreen**

In `lib/features/timer/timer_screen.dart`, delete from `build()`:

```dart
    ref.watch(syncWatcherProvider);
    // Both background triggers are activated here, from the tab that is
    // always mounted (AppShell uses an IndexedStack), so they live as long
    // as the app does.
    ref.watch(jiraAutoSyncProvider);

    ref.listen<AsyncValue<int>>(idleSecondsProvider, (previous, next) {
      final idleSeconds = next.value;
      if (idleSeconds != null) _handleIdleSecondsChanged(idleSeconds);
    });
    ref.listen<AsyncValue<ActivitySample>>(activeWindowChangesProvider, (previous, next) {
      final sample = next.value;
      if (sample != null) _recordActivitySample(sample);
    });
```

Then delete the whole `_handleIdleSecondsChanged` method, the whole `_recordActivitySample`
method, the `bool _idlePromptShowing = false;` field, and the file-level
`const _idleThresholdSeconds = 5 * 60;` declaration together with its doc comment.

Keep `ref.watch(timerTickProvider);` and everything else.

Run `flutter analyze` and delete exactly the imports it reports as unused — expected to be
`package:activity_tracker/activity_tracker.dart`, `../../core/di/device_id_provider.dart`,
`../../core/di/jira_providers.dart`, `idle_prompt_dialog.dart` and `idle_tracking.dart`.
Do **not** remove `../../core/di/sync_providers.dart` (still used for `syncedWritesProvider`)
or `package:drift/drift.dart` (still used by `_stop`/`_pause` paths) unless the analyzer
says so.

- [ ] **Step 7: Verify nothing else broke**

Run: `flutter analyze && flutter test`
Expected: "No issues found." and all tests passing.

- [ ] **Step 8: Commit**

```bash
git add lib/features/shell/background_services.dart lib/features/timer/timer_background_handlers.dart lib/features/timer/timer_screen.dart test/features/shell/background_services_test.dart
git commit -m "refactor(timer): move background subscriptions out of the timer tab"
```

---

### Task 6: The pill widget

**Files:**
- Create: `lib/features/timer/pill/pill_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/timer/pill/pill_screen_test.dart`

**Interfaces:**
- Consumes: `runningEntryProvider`, `timerTickProvider` (`lib/features/timer/timer_providers.dart`), `activeProjectsProvider` (`lib/features/projects/projects_providers.dart`), `allClientsProvider` (`lib/features/clients/clients_providers.dart`), `TimeEntryDuration.workedDuration`, `formatDuration`, `HickoryColors`
- Produces: `class PillScreen extends ConsumerWidget` with required `VoidCallback onPause`, `VoidCallback onResume`, `VoidCallback onStop`, `VoidCallback onExpand`.

- [ ] **Step 1: Add the localization keys**

In `lib/l10n/app_de.arb` add (keeping the file's existing key order convention — append before the closing brace):

```json
  "pillPause": "Pausieren",
  "pillResume": "Fortsetzen",
  "pillStop": "Stoppen",
  "pillExpand": "Hauptfenster öffnen",
  "timerCollapseToPill": "Auf Pille verkleinern"
```

`app_en.arb`:

```json
  "pillPause": "Pause",
  "pillResume": "Resume",
  "pillStop": "Stop",
  "pillExpand": "Open the main window",
  "timerCollapseToPill": "Shrink to pill"
```

`app_es.arb`:

```json
  "pillPause": "Pausar",
  "pillResume": "Reanudar",
  "pillStop": "Detener",
  "pillExpand": "Abrir la ventana principal",
  "timerCollapseToPill": "Reducir a píldora"
```

`app_fr.arb`:

```json
  "pillPause": "Mettre en pause",
  "pillResume": "Reprendre",
  "pillStop": "Arrêter",
  "pillExpand": "Ouvrir la fenêtre principale",
  "timerCollapseToPill": "Réduire en pastille"
```

`app_it.arb`:

```json
  "pillPause": "Metti in pausa",
  "pillResume": "Riprendi",
  "pillStop": "Ferma",
  "pillExpand": "Apri la finestra principale",
  "timerCollapseToPill": "Riduci a pillola"
```

`app_nl.arb`:

```json
  "pillPause": "Pauzeren",
  "pillResume": "Hervatten",
  "pillStop": "Stoppen",
  "pillExpand": "Hoofdvenster openen",
  "timerCollapseToPill": "Verklein tot pil"
```

Note: if the template file uses `@key` description entries for its existing keys, add matching `@pillPause` etc. blocks to `app_de.arb` only, following whatever shape the neighbouring keys use.

Run: `flutter gen-l10n` (or `flutter pub get`, which triggers it) and confirm `AppLocalizations.pillPause` exists.

- [ ] **Step 2: Write the failing test**

Create `test/features/timer/pill/pill_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/clients/clients_providers.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/pill/pill_screen.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({DateTime? pausedAt, String? projectId}) => TimeEntry(
  id: 'e1',
  deviceId: 'd1',
  startAt: DateTime.utc(2026, 9, 10, 8),
  endAt: null,
  pausedAt: pausedAt,
  totalPausedSeconds: 0,
  projectId: projectId,
  description: null,
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 8),
);

Project _project() => Project(
  id: 'p1',
  name: 'Website-Relaunch',
  colorHex: '#2F6B4F',
  clientId: 'c1',
  archived: false,
  billable: true,
  hourlyRateCents: null,
  currency: null,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Client _client() => Client(
  id: 'c1',
  name: 'Müller GmbH',
  archived: false,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Widget _host({
  required TimeEntry entry,
  List<Project> projects = const [],
  List<Client> clients = const [],
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onStop,
  VoidCallback? onExpand,
}) => ProviderScope(
  overrides: [
    runningEntryProvider.overrideWith((ref) => Stream.value(entry)),
    activeProjectsProvider.overrideWith((ref) => Stream.value(projects)),
    allClientsProvider.overrideWith((ref) => Stream.value(clients)),
    timerTickProvider.overrideWith((ref) => Stream.value(0)),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PillScreen(
      onPause: onPause ?? () {},
      onResume: onResume ?? () {},
      onStop: onStop ?? () {},
      onExpand: onExpand ?? () {},
    ),
  ),
);

void main() {
  testWidgets('shows the elapsed time', (tester) async {
    await tester.pumpWidget(_host(entry: _entry(pausedAt: DateTime.utc(2026, 9, 10, 9, 23, 45))));
    await tester.pumpAndSettle();

    expect(find.text('01:23:45'), findsOneWidget);
  });

  testWidgets('shows client and project when both are known', (tester) async {
    await tester.pumpWidget(
      _host(
        entry: _entry(projectId: 'p1'),
        projects: [_project()],
        clients: [_client()],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Müller GmbH · Website-Relaunch'), findsOneWidget);
  });

  testWidgets('shows the project alone when it has no client', (tester) async {
    await tester.pumpWidget(
      _host(entry: _entry(projectId: 'p1'), projects: [_project().copyWith(clientId: null)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Website-Relaunch'), findsOneWidget);
  });

  testWidgets('running state offers pause, paused state offers resume', (tester) async {
    var paused = 0;
    await tester.pumpWidget(_host(entry: _entry(), onPause: () => paused++));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    expect(paused, 1);

    var resumed = 0;
    await tester.pumpWidget(
      _host(entry: _entry(pausedAt: DateTime.utc(2026, 9, 10, 9)), onResume: () => resumed++),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(resumed, 1);
  });

  testWidgets('stop and expand fire their callbacks', (tester) async {
    var stopped = 0;
    var expanded = 0;
    await tester.pumpWidget(
      _host(entry: _entry(), onStop: () => stopped++, onExpand: () => expanded++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.stop));
    await tester.tap(find.byIcon(Icons.open_in_full));

    expect(stopped, 1);
    expect(expanded, 1);
  });

  testWidgets('every icon button carries a tooltip', (tester) async {
    await tester.pumpWidget(_host(entry: _entry()));
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsNWidgets(3));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/timer/pill/pill_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hickory/features/timer/pill/pill_screen.dart'`.

- [ ] **Step 4: Write minimal implementation**

Create `lib/features/timer/pill/pill_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/format/duration_format.dart';
import '../../../core/theme/hickory_colors.dart';
import '../../../data/drift/database.dart';
import '../../../data/drift/time_entry_extensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../clients/clients_providers.dart';
import '../../projects/projects_providers.dart';
import '../timer_providers.dart';

/// The 320x56 always-on-top timer pill. Shown instead of AppShell while
/// [WindowMode.pill] is active; the window itself is reshaped by
/// WindowModeController, this widget only paints into it.
///
/// The whole surface outside the buttons drags the window.
class PillScreen extends ConsumerWidget {
  const PillScreen({
    super.key,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onExpand,
  });

  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = HickoryColors.of(context);
    // Forces a rebuild every second so the elapsed time counts up; the
    // duration itself is always derived from the entry, never accumulated.
    ref.watch(timerTickProvider);
    final running = ref.watch(runningEntryProvider).value;
    final isPaused = running?.pausedAt != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: tokens.surfaceGradient,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDuration(running?.workedDuration ?? Duration.zero),
                      style: TextStyle(
                        fontFamily: Theme.of(context).textTheme.displayLarge?.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        height: 1.1,
                        color: isPaused ? tokens.textMuted : tokens.timerNumeral,
                      ),
                    ),
                    _ProjectLine(entry: running, muted: tokens.textMuted),
                  ],
                ),
              ),
              _PillButton(
                icon: isPaused ? Icons.play_arrow : Icons.pause,
                label: isPaused ? l10n.pillResume : l10n.pillPause,
                onPressed: isPaused ? onResume : onPause,
              ),
              _PillButton(icon: Icons.stop, label: l10n.pillStop, onPressed: onStop),
              _PillButton(
                icon: Icons.open_in_full,
                label: l10n.pillExpand,
                onPressed: onExpand,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Client - Project", the project alone when it has no client, and nothing
/// at all when the entry has no project.
class _ProjectLine extends ConsumerWidget {
  const _ProjectLine({required this.entry, required this.muted});

  final TimeEntry? entry;
  final Color muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = entry?.projectId;
    if (projectId == null) return const SizedBox.shrink();

    final projects = ref.watch(activeProjectsProvider).value ?? const <Project>[];
    Project? project;
    for (final candidate in projects) {
      if (candidate.id == projectId) project = candidate;
    }
    if (project == null) return const SizedBox.shrink();

    final clientId = project.clientId;
    String? clientName;
    if (clientId != null) {
      final clients = ref.watch(allClientsProvider).value ?? const <Client>[];
      for (final client in clients) {
        if (client.id == clientId) clientName = client.name;
      }
    }

    final label = clientName == null ? project.name : '$clientName · ${project.name}';
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: muted),
    );
  }
}

/// Icon-only button with the accessible name the pill's width has no room to
/// show. Tooltip and Semantics both carry it: the tooltip for sighted users,
/// the semantic label for screen readers.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        tooltip: null,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        iconSize: 20,
        splashRadius: 18,
      ),
    );
  }
}
```

Wrap the `IconButton` in `Semantics(label: label, button: true, ...)` if the tooltip alone does not satisfy the "every icon button carries a tooltip" test's intent — verify with `flutter test` and adjust.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/timer/pill/pill_screen_test.dart`
Expected: PASS — 6 tests. If the `TimeEntry`/`Project`/`Client` constructors in the test do not match the generated Drift row classes, correct the test's constructor arguments against `lib/data/drift/database.g.dart` — the row classes are generated and are the source of truth.

- [ ] **Step 6: Commit**

```bash
git add lib/features/timer/pill/pill_screen.dart test/features/timer/pill/pill_screen_test.dart lib/l10n/
git commit -m "feat(timer): add the floating timer pill widget"
```

---

### Task 7: Switch the tree by mode, and collapse when a timer starts

**Files:**
- Create: `lib/features/timer/pill/timer_pill_coordinator.dart`
- Modify: `lib/features/timer/pill/pill_screen.dart` (adds `PillHost`)
- Modify: `lib/app.dart`
- Test: `test/features/timer/pill/timer_pill_coordinator_test.dart`

**Interfaces:**
- Consumes: `windowModeProvider` (Task 4), `runningEntryProvider`, `BackgroundServices` (Task 5), `PillScreen` (Task 6)
- Produces: `class TimerPillCoordinator extends ConsumerStatefulWidget` taking a required `Widget child`; it drives the mode and renders `child`.

- [ ] **Step 1: Write the failing test**

Create `test/features/timer/pill/timer_pill_coordinator_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/timer/pill/timer_pill_coordinator.dart';
import 'package:hickory/features/timer/timer_providers.dart';

class _FakeWindowModeNotifier extends WindowModeNotifier {
  final calls = <String>[];

  @override
  WindowMode build() => WindowMode.full;

  @override
  Future<void> collapse() async {
    calls.add('collapse');
    state = WindowMode.pill;
  }

  @override
  Future<void> expand() async {
    calls.add('expand');
    state = WindowMode.full;
  }
}

TimeEntry _entry() => TimeEntry(
  id: 'e1',
  deviceId: 'd1',
  startAt: DateTime.utc(2026, 9, 10, 8),
  endAt: null,
  pausedAt: null,
  totalPausedSeconds: 0,
  projectId: null,
  description: null,
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 8),
);

void main() {
  testWidgets('collapses when an entry starts running', (tester) async {
    final notifier = _FakeWindowModeNotifier();
    final running = StreamController<TimeEntry?>();
    addTearDown(running.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => running.stream),
        ],
        child: const MaterialApp(
          home: TimerPillCoordinator(child: Text('shell')),
        ),
      ),
    );

    running.add(null);
    await tester.pump();
    expect(notifier.calls, isEmpty);

    running.add(_entry());
    await tester.pump();
    expect(notifier.calls, ['collapse']);
  });

  testWidgets('expands when the running entry stops', (tester) async {
    final notifier = _FakeWindowModeNotifier();
    final running = StreamController<TimeEntry?>();
    addTearDown(running.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => running.stream),
        ],
        child: const MaterialApp(
          home: TimerPillCoordinator(child: Text('shell')),
        ),
      ),
    );

    running.add(_entry());
    await tester.pump();
    running.add(null);
    await tester.pump();

    expect(notifier.calls, ['collapse', 'expand']);
  });

  testWidgets('pausing does not change the mode', (tester) async {
    final notifier = _FakeWindowModeNotifier();
    final running = StreamController<TimeEntry?>();
    addTearDown(running.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => running.stream),
        ],
        child: const MaterialApp(
          home: TimerPillCoordinator(child: Text('shell')),
        ),
      ),
    );

    running.add(_entry());
    await tester.pump();
    running.add(_entry().copyWith(pausedAt: Value(DateTime.utc(2026, 9, 10, 9))));
    await tester.pump();

    expect(notifier.calls, ['collapse']);
  });
}
```

Add `import 'package:drift/drift.dart' show Value;` to that test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/timer/pill/timer_pill_coordinator_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hickory/features/timer/pill/timer_pill_coordinator.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/timer/pill/timer_pill_coordinator.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/window/window_mode.dart';
import '../../../core/window/window_mode_provider.dart';
import '../../../data/drift/database.dart';
import '../timer_providers.dart';

/// Collapses the window to the pill when a timer starts, and expands it again
/// when that entry stops. Deliberately reacts only to the presence of a
/// running entry: pausing keeps the pill, and expanding by hand (the pill's
/// expand button) is not undone by this widget.
///
/// Mounted above the mode switch so it survives the tree swap it causes.
class TimerPillCoordinator extends ConsumerStatefulWidget {
  const TimerPillCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TimerPillCoordinator> createState() => _TimerPillCoordinatorState();
}

class _TimerPillCoordinatorState extends ConsumerState<TimerPillCoordinator> {
  bool? _wasRunning;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TimeEntry?>>(runningEntryProvider, (previous, next) {
      next.whenData(_onRunningChanged);
    });
    return widget.child;
  }

  void _onRunningChanged(TimeEntry? running) {
    final isRunning = running != null;
    if (_wasRunning == isRunning) return;
    final hadPreviousValue = _wasRunning != null;
    _wasRunning = isRunning;
    // The very first emission is the current state, not a transition -- a
    // start that already happened before this widget mounted (an app launch
    // with an entry still running) must not collapse the window, see spec 4.3.
    if (!hadPreviousValue) return;

    final notifier = ref.read(windowModeProvider.notifier);
    if (isRunning) {
      notifier.collapse();
      return;
    }
    if (ref.read(windowModeProvider) == WindowMode.pill) notifier.expand();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/timer/pill/timer_pill_coordinator_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Add the pill host**

Append to `lib/features/timer/pill/pill_screen.dart` — the widget that supplies
`PillScreen`'s four callbacks, using the same writes `TimerScreen` uses:

```dart
/// Supplies [PillScreen] with the running entry's controls. Separate from
/// PillScreen so that widget stays a pure rendering of four callbacks.
class PillHost extends ConsumerWidget {
  const PillHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(runningEntryProvider).value;

    Future<void> withWrites(Future<void> Function(SyncedWrites writes) action) async {
      final writes = await ref.read(syncedWritesProvider.future);
      await action(writes);
    }

    void ifRunning(Future<void> Function(SyncedWrites writes, TimeEntry entry) action) {
      final entry = running;
      if (entry == null) return;
      withWrites((writes) => action(writes, entry));
    }

    return PillScreen(
      onPause: () => ifRunning((writes, entry) => writes.pauseEntry(entry.id)),
      onResume: () => ifRunning((writes, entry) => writes.resumeEntry(entry.id)),
      onStop: () => ifRunning((writes, entry) => writes.stopEntry(entry.id)),
      onExpand: () => ref.read(windowModeProvider.notifier).expand(),
    );
  }
}
```

Add the imports it needs to that file: `../../../core/di/sync_providers.dart` (for
`syncedWritesProvider` and the `SyncedWrites` type) and
`../../../core/window/window_mode_provider.dart`.

- [ ] **Step 6: Wire the switch into app.dart**

In `lib/app.dart`, add the imports:

```dart
import 'core/window/window_mode.dart';
import 'core/window/window_mode_provider.dart';
import 'features/timer/pill/pill_screen.dart';
import 'features/timer/pill/timer_pill_coordinator.dart';
import 'features/timer/timer_background_handlers.dart';
```

and replace `home: const AppShell(),` with:

```dart
      home: TimerBackgroundHandlers(
        child: TimerPillCoordinator(
          child: switch (ref.watch(windowModeProvider)) {
            WindowMode.full => const AppShell(),
            WindowMode.pill => const PillHost(),
          },
        ),
      ),
```

`TimerBackgroundHandlers` wraps `BackgroundServices` internally (Task 5), so the four
subscriptions and both handlers now sit above the mode switch and survive it.

- [ ] **Step 7: Verify the whole app still builds and the suite is green**

Run: `flutter analyze && flutter test`
Expected: "No issues found." and all tests passing.

- [ ] **Step 8: Commit**

```bash
git add lib/app.dart lib/features/timer/pill/ test/features/timer/pill/
git commit -m "feat(timer): collapse to the pill while a timer runs"
```

---

### Task 8: Collapse button in the main window

The client-phone-call scenario from the spec: expand to check Reports, then collapse again — so the button must be reachable from every tab, not just the timer tab. `NavShell` already has an unused `fabBuilder` hook for exactly this.

**Files:**
- Modify: `lib/features/shell/app_shell.dart`
- Test: `test/features/shell/app_shell_test.dart` (create if absent)

**Interfaces:**
- Consumes: `runningEntryProvider`, `windowModeProvider`, `NavShell.fabBuilder`, `l10n.timerCollapseToPill` (Task 6)
- Produces: nothing new

- [ ] **Step 1: Write the failing test**

Create `test/features/shell/app_shell_test.dart` with a test that the FAB appears only while an entry runs. Use `NavShell` directly to keep the test off the real screens:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/shell/nav_shell.dart';

void main() {
  testWidgets('fabBuilder result is rendered for the selected tab', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavShell(
          destinations: const [
            NavigationDestination(icon: Icon(Icons.timer), label: 'a'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'b'),
          ],
          children: const [Text('one'), Text('two')],
          fabBuilder: (_) => FloatingActionButton.small(
            onPressed: () {},
            child: const Icon(Icons.close_fullscreen),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();

    // Still there: the collapse button is not tab-specific.
    expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `flutter test test/features/shell/app_shell_test.dart`
Expected: PASS immediately — `fabBuilder` already exists. This test pins the behaviour the next step depends on; if it fails, fix `NavShell` before continuing.

- [ ] **Step 3: Add the collapse FAB to AppShell**

In `lib/features/shell/app_shell.dart`, change `AppShell` from `StatelessWidget` to `ConsumerWidget`, add the imports for `flutter_riverpod`, `../../core/window/window_mode_provider.dart` and `../timer/timer_providers.dart`, and pass:

```dart
      fabBuilder: (_) {
        final isRunning = ref.watch(runningEntryProvider).value != null;
        if (!isRunning) return null;
        return FloatingActionButton.small(
          tooltip: l10n.timerCollapseToPill,
          onPressed: () => ref.read(windowModeProvider.notifier).collapse(),
          child: const Icon(Icons.close_fullscreen),
        );
      },
```

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: "No issues found." and all tests passing.

- [ ] **Step 5: Commit**

```bash
git add lib/features/shell/app_shell.dart test/features/shell/app_shell_test.dart
git commit -m "feat(shell): add a collapse-to-pill button while a timer runs"
```

---

### Task 9: Dialogs expand the window first

`showIdlePromptDialog` cannot open over a 320x56 window (spec section 4.2). The expand
happens at the **call site**, not inside the dialog: a dialog function has no business
knowing about window modes, and the rule is meant to apply to every future dialog too.

**Files:**
- Modify: `lib/features/timer/timer_background_handlers.dart`
- Test: `test/features/timer/timer_background_handlers_test.dart`

**Interfaces:**
- Consumes: `windowModeProvider`, `WindowModeNotifier` (Task 4), `TimerBackgroundHandlers` (Task 5)
- Produces: nothing new. `showIdlePromptDialog(BuildContext, Duration)` keeps its current signature.

- [ ] **Step 1: Write the failing test**

Create `test/features/timer/timer_background_handlers_test.dart`:

```dart
import 'dart:async';

import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/timer/idle_tracking.dart';
import 'package:hickory/features/timer/timer_background_handlers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

class _PillModeNotifier extends WindowModeNotifier {
  final calls = <String>[];

  @override
  WindowMode build() => WindowMode.pill;

  @override
  Future<void> collapse() async {
    calls.add('collapse');
    state = WindowMode.pill;
  }

  @override
  Future<void> expand() async {
    calls.add('expand');
    state = WindowMode.full;
  }
}

TimeEntry _running() => TimeEntry(
  id: 'e1',
  deviceId: 'd1',
  startAt: DateTime.utc(2026, 9, 10, 8),
  endAt: null,
  pausedAt: null,
  totalPausedSeconds: 0,
  projectId: null,
  description: null,
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 8),
);

void main() {
  testWidgets('expands the window before showing the idle prompt', (tester) async {
    final notifier = _PillModeNotifier();
    final key = GlobalKey<TimerBackgroundHandlersState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => Stream.value(_running())),
          idleSecondsProvider.overrideWith((ref) => const Stream<int>.empty()),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TimerBackgroundHandlers(key: key, child: const SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(key.currentState!.handleIdleSecondsChanged(600));
    await tester.pumpAndSettle();

    expect(notifier.calls, contains('expand'));
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('does not expand when already in full mode', (tester) async {
    final notifier = _PillModeNotifier();
    // Drive it to full first, then clear the record.
    final key = GlobalKey<TimerBackgroundHandlersState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => Stream.value(_running())),
          idleSecondsProvider.overrideWith((ref) => const Stream<int>.empty()),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TimerBackgroundHandlers(key: key, child: const SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() => notifier.expand());
    notifier.calls.clear();
    await tester.pumpAndSettle();

    unawaited(key.currentState!.handleIdleSecondsChanged(600));
    await tester.pumpAndSettle();

    expect(notifier.calls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('below the threshold nothing happens at all', (tester) async {
    final notifier = _PillModeNotifier();
    final key = GlobalKey<TimerBackgroundHandlersState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => Stream.value(_running())),
          idleSecondsProvider.overrideWith((ref) => const Stream<int>.empty()),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TimerBackgroundHandlers(key: key, child: const SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await key.currentState!.handleIdleSecondsChanged(10);
    await tester.pumpAndSettle();

    expect(notifier.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/timer/timer_background_handlers_test.dart`
Expected: FAIL on the first test — `expand` is never called.

- [ ] **Step 3: Implement**

In `lib/features/timer/timer_background_handlers.dart`, inside
`handleIdleSecondsChanged`, immediately after `_idlePromptShowing = true;` and before
`showIdlePromptDialog`:

```dart
    // A dialog cannot open over the 320x56 pill -- and "you were away, should
    // I trim that?" is a question answered at full size anyway (spec 4.2).
    // The window stays expanded afterwards; collapsing again is the user's
    // call, via the FAB.
    if (ref.read(windowModeProvider) == WindowMode.pill) {
      await ref.read(windowModeProvider.notifier).expand();
    }
    if (!mounted) return;
```

Add the imports `../../core/window/window_mode.dart` and
`../../core/window/window_mode_provider.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/timer/timer_background_handlers_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Full verification**

Run: `flutter analyze && flutter test`
Expected: "No issues found." and every test passing.

- [ ] **Step 6: Commit**

```bash
git add lib/features/timer/timer_background_handlers.dart test/features/timer/timer_background_handlers_test.dart
git commit -m "feat(timer): expand the window before showing a dialog"
```

---

### Task 10: Manual verification on macOS, and the memory update

Automated tests cannot prove the native behaviour; the spike did that for a bare window, and this task repeats it for the real app.

**Files:**
- Create: `docs/memory/features/timer-pill.md`
- Modify: `docs/memory/features.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the app and walk the flow**

Run: `flutter run -d macos`

Check each of these by hand and note the result:
1. Start a timer → the window collapses to a frameless pill within a second
2. The pill shows the counting time and "Client · Project"
3. Drag the pill to another corner; quit and relaunch; start a timer → the pill reappears where it was dropped
4. Pause on the pill → time freezes, the button becomes ▶, the pill dims
5. Expand → the full window returns **with its title bar**, at its previous size and position, and the timer is still running
6. Switch to Reports, then press the collapse FAB → back to the pill, timer untouched
7. Stop on the pill → the full window returns
8. Quit with a running timer, relaunch → the app opens in full mode (spec §4.3)

- [ ] **Step 2: Fix anything that failed, then re-run Step 1**

Do not proceed with a failing item. If the title bar does not come back (spike §8 says it does on macOS), stop and escalate — that is the fallback scenario the spec names, and it changes the design.

- [ ] **Step 3: Write the feature memory file**

Create `docs/memory/features/timer-pill.md` with, in the project's fact-based bullet style: the files involved, the decision that the pill is a window *mode* rather than a second window and why, the frame-origin shift finding from the spike, the reason `BackgroundServices` exists, that Windows is unverified, and the three deferred follow-ups (window-level setting, global hotkey, right-click menu).

- [ ] **Step 4: Add the index entry**

In `docs/memory/features.md`, add a row:

```markdown
| Timer pill | Frameless always-on-top mini window while a timer runs | [timer-pill.md](features/timer-pill.md) |
```

- [ ] **Step 5: Add the CHANGELOG entry**

Under the `[Unreleased]` heading's `### Added` section (create the heading if the file has no Unreleased block), in present tense:

```markdown
- Add a floating timer pill: while a timer runs, the window collapses to a small always-on-top pill with the elapsed time, client and project, and pause/stop/expand controls
```

- [ ] **Step 6: Commit**

```bash
git add docs/memory/ CHANGELOG.md
git commit -m "docs: record the timer pill feature"
```

---

## Notes for the executor

- **Windows is unverified.** Tasks 1-9 are platform-neutral Dart, but the frameless round trip has only been proven on macOS. Do not add Windows claims to comments, the CHANGELOG, or the README.
- **Task 5 is not optional and not a refactor you can defer.** Swapping the tree without it silently stops idle detection, activity sampling and Jira auto-sync while a timer runs.
- **Drift row classes are generated.** If a test's `TimeEntry(...)`, `Project(...)` or `Client(...)` constructor does not compile, read `lib/data/drift/database.g.dart` and match it — do not change the production code to fit a guessed constructor.
- **SnackBars need no work.** Spec section 4.2 says they are suppressed in pill mode; every remaining `showSnackBar` call site was checked during planning and all of them are triggered from screens that only exist in full mode (Settings, Clients, Projects, entries, absences), plus the tray controller's hide-to-tray notice, which the pill cannot reach.
