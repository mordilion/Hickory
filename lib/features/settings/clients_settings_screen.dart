import 'package:flutter/material.dart';

import '../clients/clients_editor.dart';
import 'settings_sub_page.dart';

/// No page title -- ClientsEditor already renders l10n.settingsClientsTitle
/// as its own heading (see settings_sub_page.dart's doc comment).
class ClientsSettingsScreen extends StatelessWidget {
  const ClientsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubPage(
      child: SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(padding: EdgeInsets.all(16), child: ClientsEditor()),
        ),
      ),
    );
  }
}
