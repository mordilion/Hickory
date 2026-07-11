import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/di/database_provider.dart';
import 'core/di/locale_provider.dart';
import 'core/di/sync_providers.dart';
import 'core/locale/locale_resolution.dart';
import 'core/window/quit_behavior.dart';
import 'core/window/window_tray_controller.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
}
