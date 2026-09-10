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
