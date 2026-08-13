import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';

/// Shows the create/edit dialog for a client. Pass [client] to edit an
/// existing one (field pre-filled, submit calls SyncedWrites.updateClient);
/// omit it to create a new one (submit calls SyncedWrites.createClient).
/// Resolves to the created/updated [Client] on submit, or `null` if the
/// dialog is cancelled -- callers that need the result (e.g. the project
/// form's inline "create client" picker entry) can await it directly.
Future<Client?> showClientFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Client? client,
}) {
  final nameController = TextEditingController(text: client?.name ?? '');
  return showDialog<Client?>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(client == null ? l10n.clientsNewClientTitle : l10n.clientsEditTitle),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.clientsNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final writes = await ref.read(syncedWritesProvider.future);
              final Client saved;
              if (client == null) {
                saved = await writes.createClient(name: name);
              } else {
                saved = await writes.updateClient(client.id, name: Value(name));
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop(saved);
            },
            child: Text(client == null ? l10n.clientsCreateButton : l10n.commonSave),
          ),
        ],
      );
    },
  ).whenComplete(nameController.dispose);
}
