import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_screen.dart';
import '../timer/timer_screen.dart';
import 'nav_shell.dart';

/// Wires the real Timer/Reports/Sync/Settings screens into NavShell. This
/// is Hickory's app-level navigation root (used as MaterialApp.home in
/// lib/app.dart). Manual-entry creation lives in QuickAddBar (pinned to
/// the Timer tab), not a shell-level FAB — see
/// docs/superpowers/specs/2026-08-03-quick-entry-redesign-design.md.
class AppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NavShell(
      destinations: _destinations(l10n),
      children: const [TimerScreen(), ReportsScreen(), SyncScreen(), SettingsScreen()],
    );
  }
}
