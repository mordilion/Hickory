import 'package:flutter/material.dart';

import '../projects/projects_editor.dart';
import 'settings_sub_page.dart';

/// No page title -- ProjectsEditor already renders l10n.settingsProjectsTitle
/// as its own heading (see settings_sub_page.dart's doc comment).
class ProjectsSettingsScreen extends StatelessWidget {
  const ProjectsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubPage(
      child: SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(padding: EdgeInsets.all(16), child: ProjectsEditor()),
        ),
      ),
    );
  }
}
