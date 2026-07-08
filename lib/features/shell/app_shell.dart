import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hickory_colors.dart';
import '../../core/widgets/gradient_buttons.dart';
import '../entries/manual_entry_dialog.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_screen.dart';
import '../timer/timer_screen.dart';
import 'nav_shell.dart';

/// Wires the real Timer/Reports/Sync screens and the manual-entry FAB into
/// NavShell. This is Hickory's app-level navigation root (used as
/// MaterialApp.home in lib/app.dart).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.timer_outlined),
      selectedIcon: Icon(Icons.timer),
      label: 'Timer',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Reports',
    ),
    NavigationDestination(
      icon: Icon(Icons.sync_outlined),
      selectedIcon: Icon(Icons.sync),
      label: 'Sync',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Einstellungen',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavShell(
      destinations: _destinations,
      children: const [TimerScreen(), ReportsScreen(), SyncScreen(), SettingsScreen()],
      fabBuilder: (selectedIndex) => selectedIndex == 0
          ? GradientFab(
              icon: Icons.add,
              gradient: HickoryColors.of(context).primaryGradient,
              foregroundColor: HickoryColors.of(context).onPrimaryGradient,
              onPressed: () => showManualEntryDialog(context, ref),
            )
          : null,
    );
  }
}
