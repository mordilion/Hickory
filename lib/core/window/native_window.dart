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
