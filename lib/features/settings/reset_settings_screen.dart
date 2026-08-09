import 'package:flutter/material.dart';

import 'app_reset_section.dart';
import 'settings_sub_page.dart';

/// No page title -- AppResetSection already renders l10n.settingsResetTitle
/// as its own heading (see settings_sub_page.dart's doc comment).
class ResetSettingsScreen extends StatelessWidget {
  const ResetSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubPage(
      child: SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(padding: EdgeInsets.all(16), child: AppResetSection()),
        ),
      ),
    );
  }
}
