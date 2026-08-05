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

  /// (Re)builds the tray context menu; called at startup with German
  /// defaults and again by `main()` whenever the locale changes.
  Future<void> updateContextMenu({
    String openLabel = 'Öffnen',
    String quitLabel = 'Beenden',
  }) async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: openLabel, onClick: (_) => _restore()),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: quitLabel, onClick: (_) => _quit()),
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
        SnackBar(
          content: Text(
            backgroundNoticeMessage?.call() ?? 'Hickory läuft im Hintergrund weiter.',
          ),
        ),
      );
    }
  }

  Future<void> _quit() async {
    try {
      await onBeforeQuit?.call();
    } catch (_) {
      // Best-effort: quitting must always succeed even if finalizing a
      // paused entry fails (e.g. the sync folder is temporarily
      // unreachable) — the alternative is an unquittable app.
    }
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

  @override
  void onTrayIconMouseDown() {
    _restore();
  }

  @override
  void onTrayIconRightMouseDown() {
    // setContextMenu() alone doesn't show the menu on Windows — tray_manager
    // only displays it when explicitly popped up from the right-click event.
    trayManager.popUpContextMenu();
  }
}
