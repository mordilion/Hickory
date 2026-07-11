import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hickory_colors.dart';
import '../../core/widgets/gradient_buttons.dart';
import '../../l10n/app_localizations.dart';
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

  static List<NavigationDestination> _destinations(AppLocalizations l10n) => [
    NavigationDestination(
      icon: const Icon(Icons.timer_outlined),
      selectedIcon: const Icon(Icons.timer),
      label: l10n.navTimer,
    ),
    NavigationDestination(
      icon: const Icon(Icons.bar_chart_outlined),
      selectedIcon: const Icon(Icons.bar_chart),
      label: l10n.navReports,
    ),
    NavigationDestination(
      icon: const Icon(Icons.sync_outlined),
      selectedIcon: const Icon(Icons.sync),
      label: l10n.navSync,
    ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      label: l10n.navSettings,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return NavShell(
      destinations: _destinations(l10n),
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
