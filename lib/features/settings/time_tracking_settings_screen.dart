import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'break_rule_tiers_editor.dart';
import 'quick_add_durations_editor.dart';
import 'settings_sub_page.dart';

class TimeTrackingSettingsScreen extends StatelessWidget {
  const TimeTrackingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSubPage(
      title: l10n.settingsCategoryTimeTracking,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: QuickAddDurationsEditor(),
            ),
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BreakRuleTiersEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
