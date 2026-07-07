import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/core/theme/hickory_colors.dart';

/// Runs [action] in its own error zone so a google_fonts font-load failure
/// can never leak out as unowned async work.
///
/// AppTheme pulls in buildAppTextTheme, which calls GoogleFonts.unbounded()/
/// manrope(). Each of those kicks off an internal, fire-and-forget font-load
/// Future (see google_fonts' own `pendingFontFutures` set in
/// google_fonts_base.dart). That code tracks completion with a bare
/// `.then((_) => pendingFontFutures.remove(loadingFuture))` and no
/// `onError`, so when a load fails, the error propagates into a *new*,
/// untracked Future that nothing - not even `GoogleFonts.pendingFonts()`,
/// the package's own public drain API - ever attaches a listener to. There
/// is no public API that awaits this derived Future, so from outside the
/// package it can only be caught the way Dart defines "unhandled error"
/// recovery: by owning the zone the code ran in and providing `onError`.
///
/// Unbounded/Manrope aren't bundled as test assets, and
/// `GoogleFonts.config.allowRuntimeFetching` is disabled in setUpAll below
/// (to keep this test fully offline), so every load attempt is expected to
/// fail with "font ... was not found in the application assets". Without
/// this wrapper that failure either races process teardown and gets
/// silently dropped, or - if explicitly awaited via
/// `GoogleFonts.pendingFonts()` - still leaves the untracked derived
/// Future's rejection to be reported by package:test's per-test zone,
/// which fails whichever test happens to be active when it resolves. This
/// wrapper intercepts it at the source instead.
///
/// (Mirrors the identical wrapper in app_text_theme_test.dart, which
/// buildAppTextTheme's own tests need for the same reason.)
Future<T> _isolatingFontLoadErrors<T>(T Function() action) {
  final completer = Completer<T>();
  runZonedGuarded(
    () {
      final result = action();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    },
    (error, stack) {
      // Only swallow the specific, expected google_fonts asset-loading
      // failure. Anything else must still fail the test loudly instead of
      // being silently absorbed here.
      if (!error.toString().contains('was not found in the application assets')) {
        Error.throwWithStackTrace(error, stack);
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );
  return completer.future;
}

void main() {
  // A Flutter binding is required for GoogleFonts calls (used internally by
  // AppTheme via buildAppTextTheme) to work (they touch rootBundle/
  // AssetManifest), even though these tests never pump a widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Disable runtime fetching for tests to avoid network requests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('light/dark themes report the right brightness', () async {
    await _isolatingFontLoadErrors(() {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });
  });

  test('HickoryColors is registered as a theme extension on both themes', () async {
    await _isolatingFontLoadErrors(() {
      expect(AppTheme.light.extension<HickoryColors>(), HickoryColors.light);
      expect(AppTheme.dark.extension<HickoryColors>(), HickoryColors.dark);
    });
  });

  test('buttons are pill-shaped and cards use 24px corners', () async {
    await _isolatingFontLoadErrors(() {
      final buttonShape = AppTheme.dark.filledButtonTheme.style?.shape?.resolve({});
      expect(buttonShape, isA<StadiumBorder>());

      final cardShape = AppTheme.dark.cardTheme.shape as RoundedRectangleBorder?;
      expect(cardShape?.borderRadius, BorderRadius.circular(24));
    });
  });

  test('nav bar always shows labels so the active/inactive layout never shifts', () async {
    await _isolatingFontLoadErrors(() {
      expect(
        AppTheme.dark.navigationBarTheme.labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
    });
  });
}
