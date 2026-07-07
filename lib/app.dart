import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/timer/timer_screen.dart';

class HickoryApp extends StatelessWidget {
  const HickoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hickory',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const TimerScreen(),
    );
  }
}
