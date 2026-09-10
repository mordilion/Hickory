import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_bounds_store.dart';
import 'package:hickory/core/window/window_tray_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WindowTrayController controller;

  // window_manager's getBounds() talks to the platform over this
  // MethodChannel (name and result shape taken from window_manager 0.5.2's
  // own implementation, which decodes 'x'/'y'/'width'/'height' out of the
  // result map). Faking it out lets the fallback branch of `_persistBounds`
  // actually run under `flutter test` instead of throwing
  // MissingPluginException -- which its own `catch (_)` would otherwise
  // silently swallow, making the fallback write invisible to a test.
  const windowManagerChannel = MethodChannel('window_manager');

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_window_tray_controller_');
    // Deliberately not calling `initialize()`: it touches the windowManager
    // and trayManager platform channels, which aren't available outside a
    // real app. `onWindowResized`/`onWindowMoved` don't need it -- they only
    // read `persistBoundsForCurrentMode` and `_boundsStore` (seeded below via
    // the test-only setter where a test needs it non-null).
    controller = WindowTrayController();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          windowManagerChannel,
          (call) async => call.method == 'getBounds'
              ? {'x': 0.0, 'y': 0.0, 'width': 480.0, 'height': 960.0}
              : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
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
    'onWindowResized does not also write through the fallback store when the '
    'mode callback is set',
    () async {
      // Unlike the two tests above, this one seeds a *live* fallback store
      // (via the test-only setter) and a working window_manager channel
      // mock, so the fallback branch of `_persistBounds` is actually
      // reachable -- not short-circuited by a null `_boundsStore` or a
      // swallowed MissingPluginException. That is what makes this test
      // capable of catching a dropped `return` after `await persist()`: with
      // the `return` removed, `_persistBounds` would fall through and also
      // write `window_bounds.json` here, silently overwriting the main
      // window's remembered bounds with whatever the pill's drag produced.
      controller.boundsStoreForTesting = WindowBoundsStore(
        supportDirectory: tempDir,
      );
      final completer = Completer<void>();
      controller.persistBoundsForCurrentMode = () async {
        completer.complete();
      };

      controller.onWindowResized();
      await awaitCallback(completer);
      // The mode callback resolving doesn't guarantee a *subsequent*
      // fallback branch (if one incorrectly ran) has finished its own
      // awaits (the mocked channel round-trip, then the file write) --
      // give it a generous window to do so before asserting its absence.
      await Future.delayed(const Duration(milliseconds: 100));

      final boundsFile = File('${tempDir.path}/window_bounds.json');
      expect(boundsFile.existsSync(), isFalse);
    },
  );
}
