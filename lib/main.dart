import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/di/database_provider.dart';
import 'core/di/sync_providers.dart';
import 'core/window/quit_behavior.dart';
import 'core/window/window_tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AutostartService().setup();

  final container = ProviderContainer();
  final windowTrayController = WindowTrayController();
  windowTrayController.onBeforeQuit = () async {
    final db = container.read(appDatabaseProvider);
    final writes = await container.read(syncedWritesProvider.future);
    await stopPausedEntryOnQuit(db, writes);
  };
  await windowTrayController.initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );
}
