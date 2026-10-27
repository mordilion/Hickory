import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/update_providers.dart';
import '../../core/update/update_checker.dart';
import '../../core/window/window_mode_provider.dart';
import '../../l10n/app_localizations.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_navigation.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_screen.dart';
import '../timer/timer_providers.dart';
import '../timer/timer_screen.dart';
import 'nav_shell.dart';

/// Wires the real Timer/Reports/Sync/Settings screens into NavShell. This
/// is Hickory's app-level navigation root (used as MaterialApp.home in
/// lib/app.dart). Manual-entry creation lives in QuickAddBar (pinned to
/// the Timer tab), not a shell-level FAB — see
/// docs/superpowers/specs/2026-08-03-quick-entry-redesign-design.md.
///
/// Also owns the startup update prompt: it is the lowest widget that can
/// both show a dialog and switch tabs, which is what answering the prompt
/// with OK has to do.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Index of the Settings tab in [_destinations] / the children list below.
  static const _settingsTabIndex = 3;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // The startup check is a network round trip, so in practice it lands
    // well after this widget is built and the listener in build() catches
    // it. If it ever resolves first, that listener would never see a
    // change, so the pending value is picked up once here instead -- after
    // the first frame, because showing a dialog needs a mounted Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(startupUpdatePromptProvider);
      if (pending != null) _consumeUpdatePrompt(pending);
    });
  }

  /// Clears the pending update first: the provider doubles as the "not
  /// offered yet" marker, so leaving it set would re-open the dialog on the
  /// next rebuild.
  void _consumeUpdatePrompt(UpdateInfo update) {
    ref.read(startupUpdatePromptProvider.notifier).state = null;
    unawaited(_showUpdatePrompt(update));
  }

  Future<void> _showUpdatePrompt(UpdateInfo update) async {
    final l10n = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.updatePromptTitle),
        content: Text(l10n.settingsUpdateAvailable(update.version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
    // Also covers a barrier tap or Escape, both of which pop with null.
    if (accepted != true || !mounted) return;

    setState(() => _selectedIndex = _settingsTabIndex);
    // The Settings tab owns a private Navigator, so it has to push its own
    // update page -- see settings_navigation.dart.
    ref.read(openUpdatePageRequestedProvider.notifier).state = true;
  }

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

    ref.listen<UpdateInfo?>(startupUpdatePromptProvider, (_, update) {
      if (update != null) _consumeUpdatePrompt(update);
    });

    return NavShell(
      destinations: _destinations(l10n),
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      children: const [TimerScreen(), ReportsScreen(), SyncScreen(), SettingsScreen()],
      // Reachable from every tab, not just Timer -- the spec's scenario is
      // expanding to check Reports mid-call and then collapsing again from
      // there (see task-8-brief.md), so this ignores selectedIndex on
      // purpose rather than gating on it.
      fabBuilder: (_) {
        final isRunning = ref.watch(runningEntryProvider).value != null;
        if (!isRunning) return null;
        return FloatingActionButton.small(
          tooltip: l10n.timerCollapseToPill,
          onPressed: () => ref.read(windowModeProvider.notifier).collapse(),
          child: const Icon(Icons.close_fullscreen),
        );
      },
    );
  }
}
