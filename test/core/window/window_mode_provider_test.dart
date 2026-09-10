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
