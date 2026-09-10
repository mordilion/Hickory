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
