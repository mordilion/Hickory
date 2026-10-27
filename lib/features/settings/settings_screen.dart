import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_home_screen.dart';
import 'settings_navigation.dart';
import 'update_settings_screen.dart';

/// The Settings tab's own Navigator, so pushing a category sub-page (see
/// SettingsHomeScreen) only replaces this tab's content -- NavShell's
/// shared bottomNavigationBar and the other three tabs are untouched. See
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 3. Wrapped in NavigatorPopHandler so a system back gesture pops
/// this nested stack (e.g. off a sub-page back to the category list)
/// instead of bypassing it and hitting the app's root Navigator.
///
/// Riverpod-aware only to serve [openUpdatePageRequestedProvider]: the
/// startup update prompt cannot reach this private Navigator itself.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(openUpdatePageRequestedProvider, (_, requested) {
      if (!requested) return;
      // Cleared before pushing, so coming back to this tab later doesn't
      // push the page a second time.
      ref.read(openUpdatePageRequestedProvider.notifier).state = false;
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const UpdateSettingsScreen()),
      );
    });

    return NavigatorPopHandler(
      onPopWithResult: (result) => _navigatorKey.currentState?.pop(),
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) =>
            MaterialPageRoute(builder: (_) => const SettingsHomeScreen()),
      ),
    );
  }
}
