import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hickory/core/theme/app_text_theme.dart';

/// Runs [action] in its own error zone so a google_fonts font-load failure
/// can never leak out as unowned async work.
///
/// GoogleFonts.unbounded()/manrope() each kick off an internal, fire-and-
/// forget font-load Future (see google_fonts' own `pendingFontFutures` set
/// in google_fonts_base.dart). That code tracks completion with a bare
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
      // failure (confirmed via manual run: a plain `Exception` whose message
      // reads "...font ... was not found in the application assets...").
      // Anything else - e.g. a genuine synchronous bug in
      // [buildAppTextTheme], or a `TestFailure` from a `returnsNormally`
      // expectation inside [action] - must still fail the test loudly
      // instead of being silently absorbed here.
      if (!error.toString().contains('was not found in the application assets')) {
        Error.throwWithStackTrace(error, stack);
      }
      // Expected: the fonts aren't bundled as test assets. Swallow it; if
      // [action] already returned, this is a no-op.
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );
  return completer.future;
}

void main() {
  // A Flutter binding is required for GoogleFonts calls to work (they touch
  // rootBundle/AssetManifest), even though these tests never pump a widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Disable runtime fetching for tests to avoid network requests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('display and headline roles use Unbounded', () async {
    final theme = await _isolatingFontLoadErrors(() => buildAppTextTheme(Brightness.dark));
    expect(theme.displayLarge!.fontFamily, contains('Unbounded'));
    expect(theme.displayMedium!.fontFamily, contains('Unbounded'));
    expect(theme.headlineMedium!.fontFamily, contains('Unbounded'));
    expect(theme.titleLarge!.fontFamily, contains('Unbounded'));
  });

  test('body and label roles use Manrope', () async {
    final theme = await _isolatingFontLoadErrors(() => buildAppTextTheme(Brightness.dark));
    expect(theme.bodyLarge!.fontFamily, contains('Manrope'));
    expect(theme.bodyMedium!.fontFamily, contains('Manrope'));
    expect(theme.labelSmall!.fontFamily, contains('Manrope'));
    expect(theme.titleMedium!.fontFamily, contains('Manrope'));
  });

  test('builds for both brightnesses without throwing', () async {
    await _isolatingFontLoadErrors(() {
      expect(() => buildAppTextTheme(Brightness.light), returnsNormally);
      expect(() => buildAppTextTheme(Brightness.dark), returnsNormally);
    });
  });
}
