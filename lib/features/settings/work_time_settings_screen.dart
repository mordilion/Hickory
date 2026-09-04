import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'balance_rule_editor.dart';
import 'settings_sub_page.dart';
import 'work_time_targets_editor.dart';

/// Target work time and, from Task 8, the balance reset rule.
class WorkTimeSettingsScreen extends StatelessWidget {
  const WorkTimeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSubPage(
      title: l10n.settingsCategoryWorkTime,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: WorkTimeTargetsEditor(),
            ),
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BalanceRuleEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
