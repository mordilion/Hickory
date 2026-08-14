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
  return showDialog<Client?>(
    context: context,
    builder: (dialogContext) => _ClientFormDialogContent(ref: ref, client: client),
  );
}

/// Dialog body for [showClientFormDialog]. A StatefulWidget so its
/// [TextEditingController] is disposed via the framework's own element
/// teardown (State.dispose(), which only runs once this widget is actually
/// unmounted) rather than eagerly via `.whenComplete()` on the showDialog
/// future -- that future resolves as soon as Navigator.pop() is called,
/// which is before the dialog's exit transition finishes, so disposing the
/// controller there raced with the still-mounted TextField touching it
/// during the last few transition frames ("used after dispose").
class _ClientFormDialogContent extends StatefulWidget {
  const _ClientFormDialogContent({required this.ref, required this.client});

  final WidgetRef ref;
  final Client? client;

  @override
  State<_ClientFormDialogContent> createState() => _ClientFormDialogContentState();
}

class _ClientFormDialogContentState extends State<_ClientFormDialogContent> {
  late final _nameController = TextEditingController(text: widget.client?.name ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final client = widget.client;
    return AlertDialog(
      title: Text(client == null ? l10n.clientsNewClientTitle : l10n.clientsEditTitle),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.clientsNameLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            final writes = await widget.ref.read(syncedWritesProvider.future);
            final Client saved;
            if (client == null) {
              saved = await writes.createClient(name: name);
            } else {
              saved = await writes.updateClient(client.id, name: Value(name));
            }
            if (context.mounted) Navigator.of(context).pop(saved);
          },
          child: Text(client == null ? l10n.clientsCreateButton : l10n.commonSave),
        ),
      ],
    );
  }
}
