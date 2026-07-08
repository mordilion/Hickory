import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/window/window_tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final windowTrayController = WindowTrayController();
  await windowTrayController.initialize();

  runApp(
    ProviderScope(
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );
}
