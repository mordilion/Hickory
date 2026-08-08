import 'package:flutter/material.dart';

import 'settings_home_screen.dart';

/// The Settings tab's own Navigator, so pushing a category sub-page (see
/// SettingsHomeScreen) only replaces this tab's content -- NavShell's
/// shared bottomNavigationBar and the other three tabs are untouched. See
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 3.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => const SettingsHomeScreen()),
    );
  }
}
