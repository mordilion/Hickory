import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/di/database_provider.dart';
import 'core/di/locale_provider.dart';
import 'core/di/sync_providers.dart';
import 'core/di/update_providers.dart';
import 'core/locale/locale_resolution.dart';
import 'core/theme/app_text_theme.dart';
import 'core/window/quit_behavior.dart';
import 'core/window/window_tray_controller.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // google_fonts loads Unbounded/Manrope from disk cache or network on first
  // use; without this, the first frame paints with a fallback font and
  // reflows once the real font arrives (visible as e.g. the Timer/Manual
  // toggle's label wrapping until the next rebuild). Triggering the same
  // TextTheme build main() will later use, then awaiting it, closes that gap.
  // Best-effort only: on a sandboxed macOS build without network access the
  // fetch throws (google_fonts rethrows), which must not block runApp() —
  // that would leave the native window showing with nothing ever painted.
  try {
    buildAppTextTheme(Brightness.light);
    await GoogleFonts.pendingFonts();
  } catch (e) {
    debugPrint('Font preload failed, continuing with fallback fonts: $e');
  }
  for (final localeName in ['de_DE', 'en_US', 'de', 'en', 'fr', 'es', 'it', 'nl']) {
    await initializeDateFormatting(localeName);
  }

  final container = ProviderContainer();

  await container.read(autostartServiceProvider).setup();

  final windowTrayController = WindowTrayController();
  windowTrayController.onBeforeQuit = () async {
    final db = container.read(appDatabaseProvider);
    final writes = await container.read(syncedWritesProvider.future);
    await stopPausedEntryOnQuit(db, writes);
  };
  await windowTrayController.initialize();

  AppLocalizations trayL10n() {
    final explicit = container.read(localeControllerProvider).value;
    final locale = explicit ??
        resolveLocale(WidgetsBinding.instance.platformDispatcher.locale);
    return lookupAppLocalizations(locale);
  }

  windowTrayController.backgroundNoticeMessage = () => trayL10n().trayBackgroundNotice;
  container.listen<AsyncValue<Locale?>>(
    localeControllerProvider,
    (_, _) {
      final l10n = trayL10n();
      unawaited(
        windowTrayController.updateContextMenu(
          openLabel: l10n.trayOpen,
          quitLabel: l10n.trayQuit,
        ),
      );
    },
    fireImmediately: true,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );

  // Silent by design: only ever sets availableUpdateProvider when a real
  // update is found (Settings surfaces it) -- never shown as an error or
  // any other visible feedback if the check itself fails.
  if (Platform.isMacOS || Platform.isWindows) {
    unawaited(
      container.read(updateCheckerProvider).checkForUpdate().then((update) {
        if (update != null) {
          container.read(availableUpdateProvider.notifier).state = update;
        }
      }),
    );
  }
}
