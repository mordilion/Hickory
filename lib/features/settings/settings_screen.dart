import 'package:flutter/material.dart';

import 'settings_home_screen.dart';

/// The Settings tab's own Navigator, so pushing a category sub-page (see
/// SettingsHomeScreen) only replaces this tab's content -- NavShell's
/// shared bottomNavigationBar and the other three tabs are untouched. See
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 3. Wrapped in NavigatorPopHandler so a system back gesture pops
/// this nested stack (e.g. off a sub-page back to the category list)
/// instead of bypassing it and hitting the app's root Navigator.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
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
