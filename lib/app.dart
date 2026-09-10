import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/locale_provider.dart';
import 'core/locale/locale_resolution.dart';
import 'core/theme/app_theme.dart';
import 'core/window/window_mode.dart';
import 'core/window/window_mode_provider.dart';
import 'features/shell/app_shell.dart';
import 'features/timer/pill/pill_screen.dart';
import 'features/timer/pill/timer_pill_coordinator.dart';
import 'features/timer/timer_background_handlers.dart';
import 'l10n/app_localizations.dart';

class HickoryApp extends ConsumerWidget {
  const HickoryApp({super.key, required this.scaffoldMessengerKey});

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null (loading or "follow system") lets localeResolutionCallback pick.
    final locale = ref.watch(localeControllerProvider).value;

    return MaterialApp(
      title: 'Hickory',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (deviceLocale, _) => resolveLocale(deviceLocale),
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: TimerBackgroundHandlers(
        child: TimerPillCoordinator(
          child: switch (ref.watch(windowModeProvider)) {
            WindowMode.full => const AppShell(),
            WindowMode.pill => const PillHost(),
          },
        ),
      ),
    );
  }
}
