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
import 'core/storage/app_directories.dart';
import 'core/storage/support_directory_migration.dart';
import 'data/drift/database.dart';
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
  for (final localeName in [
    'de_DE',
    'en_US',
    'de',
    'en',
    'fr',
    'es',
    'it',
    'nl',
  ]) {
    await initializeDateFormatting(localeName);
  }

  // Before anything touches storage: carry data out of the macOS sandbox
  // container, which the sandboxed builds up to 1.3.0 wrote into. A failure
  // here must stop the launch -- starting anyway would create an empty
  // database at the new location, and that database is exactly the marker
  // that tells the next start "already migrated", stranding the real data.
  final migrationError = await _migrateSandboxData();
  if (migrationError != null) {
    runApp(_MigrationFailureApp(details: migrationError));
    return;
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
    final locale =
        explicit ??
        resolveLocale(WidgetsBinding.instance.platformDispatcher.locale);
    return lookupAppLocalizations(locale);
  }

  windowTrayController.backgroundNoticeMessage = () =>
      trayL10n().trayBackgroundNotice;
  container.listen<AsyncValue<Locale?>>(localeControllerProvider, (_, _) {
    final l10n = trayL10n();
    unawaited(
      windowTrayController.updateContextMenu(
        openLabel: l10n.trayOpen,
        quitLabel: l10n.trayQuit,
      ),
    );
  }, fireImmediately: true);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HickoryApp(
        scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey,
      ),
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

/// The path that failed and why, for [_MigrationFailureApp].
typedef _MigrationError = ({String path, String error});

/// Copies data out of the macOS sandbox container, returning null when there
/// was nothing to do or it succeeded.
///
/// macOS only: no other platform was ever sandboxed, so no other platform has a
/// container to migrate from.
Future<_MigrationError?> _migrateSandboxData() async {
  if (!Platform.isMacOS) return null;

  final target = await appDataDirectory();
  // A sandboxed build resolves its support directory *into* the container, so
  // there is nothing to migrate out of -- and its HOME is redirected there too,
  // which is why the home directory is derived from this path instead.
  if (isSandboxContainerPath(target.path)) {
    debugPrint('Sandbox container migration: still sandboxed, nothing to do');
    return null;
  }
  final home = homeOfSupportDirectory(target.path);
  final bundleId = bundleIdOfSupportDirectory(target.path);
  final legacySupport = legacyContainerSupportDirectory(home, bundleId);
  try {
    final outcome = await migrateOutOfSandboxContainer(
      legacySupport: legacySupport,
      legacyDocuments: legacyContainerDocumentsDirectory(home, bundleId),
      target: target,
      databaseFileName: AppDatabase.databaseFileName,
    );
    // Paths only, never contents: the sync configuration and device id are not
    // log material.
    debugPrint('Sandbox container migration: ${outcome.name}');
    return null;
  } catch (error) {
    return (path: legacySupport.parent.parent.path, error: '$error');
  }
}

/// Shown instead of the app when the migration failed, naming where the data
/// still is. Deliberately a dead end: the alternative is a silently empty app
/// that looks like data loss and then blocks the retry.
class _MigrationFailureApp extends StatelessWidget {
  const _MigrationFailureApp({required this.details});

  final _MigrationError details;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.migrationFailedTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        l10n.migrationFailedMessage(
                          details.path,
                          details.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
