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
