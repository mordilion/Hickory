import 'dart:ui' show Offset, Size;

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
    required this.window,
    required this.fullBounds,
    required this.pillBounds,
  });

  /// Fixed pill footprint. Wide enough for the elapsed time, three icon
  /// buttons and an ellipsized "client - project" line.
  static const pillSize = Size(320, 56);

  /// Mirrors WindowTrayController's minimum for the normal window.
  static const fullMinimumSize = Size(480, 960);

  /// Gap from the display edge when the pill has never been dragged.
  static const _defaultMargin = 16.0;

  final NativeWindow window;
  final WindowBoundsStore fullBounds;
  final WindowBoundsStore pillBounds;

  WindowMode _mode = WindowMode.full;
  WindowMode get mode => _mode;

  /// True for the whole duration of a [collapse] or [expand] call, cleared in
  /// a `finally` so it never sticks after a thrown error. Exists because
  /// [collapse]/[expand]'s own `setSize`/`setPosition` calls make the native
  /// window emit a move event *during* the switch: on macOS, window_manager's
  /// `setSize`/`setPosition` call through to `NSWindow.setFrame`, and AppKit
  /// posts `NSWindowDidMove` for that exactly as it would for a user drag --
  /// which `WindowTrayController.onWindowMoved` routes straight into
  /// [persistCurrentBounds]. At that point [_mode] still names the mode the
  /// switch is leaving, so without this flag a mid-switch bounds write lands
  /// in the wrong store (the pill's shape overwriting the main window's
  /// saved bounds, or vice versa) -- corrupting a user preference on the
  /// very first use of the feature. [persistCurrentBounds] no-ops while this
  /// is true, and [collapse]/[expand] also treat it as a re-entrancy guard
  /// so two overlapping switches (e.g. a double-clicked collapse button)
  /// cannot run their native call sequences concurrently. Do not delete this
  /// without another way to tell a programmatic resize apart from a
  /// user-driven one.
  bool _switching = false;

  /// Shrinks the window to the pill. Restores the pill's last position, or
  /// places it top-right of the display the first time. A no-op while
  /// already in pill mode or while another switch is in flight -- see
  /// [_switching].
  Future<void> collapse() async {
    if (_mode == WindowMode.pill || _switching) return;
    _switching = true;
    try {
      await _persist(fullBounds);
      final position = await _pillPosition();

      // Order matters, per a macOS spike (spec 8.1): the minimum size has to
      // come down before the size is set or the window stays stuck at 480
      // wide, and the position is applied only after the title bar is hidden
      // because hiding it shifts the frame origin by the title-bar height
      // (measured 32px) -- setting position any earlier would target the
      // pre-shift frame and land the pill in the wrong place.
      await window.setMinimumSize(pillSize);
      await window.setTitleBarHidden(true);
      await window.setSize(pillSize);
      await window.setPosition(position);
      await window.setResizable(false);
      await window.setAlwaysOnTop(true);
      _mode = WindowMode.pill;
    } finally {
      _switching = false;
    }
  }

  /// Restores the normal window, putting it back where it was before the
  /// last [collapse]. A no-op while already in full mode or while another
  /// switch is in flight -- see [_switching].
  Future<void> expand() async {
    if (_mode == WindowMode.full || _switching) return;
    _switching = true;
    try {
      await _persist(pillBounds);
      final saved = await fullBounds.read();
      final size = saved == null ? fullMinimumSize : Size(saved.width, saved.height);

      // Same ordering constraint as collapse(), mirrored: minimum size before
      // size, and position set explicitly from the full-window store afterward
      // rather than assumed -- the title bar reappearing shifts the frame
      // origin again, so the window cannot be trusted to still be where it
      // was.
      await window.setAlwaysOnTop(false);
      await window.setResizable(true);
      await window.setTitleBarHidden(false);
      await window.setMinimumSize(fullMinimumSize);
      await window.setSize(size);
      if (saved != null) await window.setPosition(saved.topLeft);
      _mode = WindowMode.full;
    } finally {
      _switching = false;
    }
  }

  /// Writes the current bounds to whichever store owns the current mode.
  /// Called from the window's move/resize listeners. No-ops while a
  /// [collapse]/[expand] switch is in flight (see [_switching]) -- the
  /// window's own native calls fire the very move event that would
  /// otherwise land here mid-switch, routed by a [_mode] that hasn't been
  /// updated yet.
  Future<void> persistCurrentBounds() async {
    if (_switching) return;
    await _persist(_mode == WindowMode.pill ? pillBounds : fullBounds);
  }

  /// Resolves where the pill should appear: its own last saved position, or
  /// top-right of the display with [_defaultMargin] the first time it is
  /// ever shown.
  Future<Offset> _pillPosition() async {
    final saved = await pillBounds.read();
    if (saved != null) return saved.topLeft;
    try {
      final display = await window.getDisplaySize();
      return Offset(display.width - pillSize.width - _defaultMargin, _defaultMargin);
    } catch (e) {
      // Best-effort, same reasoning as _persist below: a display query
      // failure must not block collapse() from completing.
      debugPrint('Display size unavailable, placing pill at the margin: $e');
      return const Offset(_defaultMargin, _defaultMargin);
    }
  }

  /// Best-effort, matching WindowTrayController._persistBounds: a failed
  /// write (e.g. disk full, unwritable directory) isn't user-visible and
  /// must never stop a mode switch from completing.
  Future<void> _persist(WindowBoundsStore store) async {
    try {
      await store.write(await window.getBounds());
    } catch (e) {
      debugPrint('Window bounds not persisted: $e');
    }
  }
}
