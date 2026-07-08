import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/app_shell.dart';

class HickoryApp extends StatelessWidget {
  const HickoryApp({super.key, required this.scaffoldMessengerKey});

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hickory',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const AppShell(),
    );
  }
}
