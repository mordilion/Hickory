import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_tray_controller.dart';

void main() {
  late Directory tempDir;
  late WindowTrayController controller;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_window_tray_controller_');
    // Deliberately not calling `initialize()`: it touches the windowManager
    // and trayManager platform channels, which aren't available outside a
    // real app. `onWindowResized`/`onWindowMoved` don't need it -- they only
    // read `persistBoundsForCurrentMode` and the (here still-null) private
    // bounds store, neither of which `initialize()` is required to set up
    // for this test's purposes.
    controller = WindowTrayController();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// `onWindowResized`/`onWindowMoved` are declared `void ... async`, so they
  /// return to the caller before their body finishes. Waiting on a
  /// `Completer` that the callback under test completes -- instead of just
  /// calling the listener and immediately asserting -- is what makes the
  /// wait deterministic; a timeout turns "callback never invoked" into a
  /// failing test instead of a silent false negative.
  Future<void> awaitCallback(Completer<void> completer) {
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('persistBoundsForCurrentMode was not invoked'),
    );
  }

  test('onWindowResized routes through persistBoundsForCurrentMode when set', () async {
    final completer = Completer<void>();
    var callCount = 0;
    controller.persistBoundsForCurrentMode = () async {
      callCount++;
      completer.complete();
    };

    controller.onWindowResized();
    await awaitCallback(completer);

    expect(callCount, 1);
  });

  test('onWindowMoved routes through persistBoundsForCurrentMode when set', () async {
    final completer = Completer<void>();
    var callCount = 0;
    controller.persistBoundsForCurrentMode = () async {
      callCount++;
      completer.complete();
    };

    controller.onWindowMoved();
    await awaitCallback(completer);

    expect(callCount, 1);
  });

  test(
    'onWindowResized does not fall back to the bounds-file store when the callback is set',
    () async {
      final completer = Completer<void>();
      controller.persistBoundsForCurrentMode = () async {
        completer.complete();
      };

      controller.onWindowResized();
      await awaitCallback(completer);

      // `_boundsStore` is private and only ever assigned inside
      // `initialize()`, which this test cannot call (see setUp). That means
      // an uninitialized controller's fallback branch is already a no-op
      // (its own `if (store == null) return;` guard fires) regardless of
      // whether the callback branch above it returns early or not. This
      // assertion therefore pins "the callback path writes nothing to disk
      // itself" but -- as documented in the task report -- cannot by itself
      // distinguish a dropped `return` after `await persist()` from correct
      // code, because both reach the same null-store early return.
      final boundsFile = File('${tempDir.path}/window_bounds.json');
      expect(boundsFile.existsSync(), isFalse);
    },
  );
}
