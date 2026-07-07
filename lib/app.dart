import 'package:flutter/material.dart';

import 'features/timer/timer_screen.dart';

class HickoryApp extends StatelessWidget {
  const HickoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hickory',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF5B8DEF), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B8DEF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const TimerScreen(),
    );
  }
}
