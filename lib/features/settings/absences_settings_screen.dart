import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'absence_types_editor.dart';
import 'settings_sub_page.dart';

/// The absence switch and the user's absence types.
class AbsencesSettingsScreen extends StatelessWidget {
  const AbsencesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSubPage(
      title: l10n.settingsCategoryAbsences,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: AbsenceTypesEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
