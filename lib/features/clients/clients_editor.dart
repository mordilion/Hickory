import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart' show ClientHasProjectsException;
import '../../l10n/app_localizations.dart';
import 'client_form_dialog.dart';
import 'clients_providers.dart';

/// Settings-screen client manager: create/edit/archive active clients,
/// reactivate archived ones, delete unused ones. Lives in the `clients`
/// feature (not `settings/`), same placement rationale as `ProjectsEditor` --
/// see docs/superpowers/specs/2026-08-13-client-management-design.md.
class ClientsEditor extends ConsumerStatefulWidget {
  const ClientsEditor({super.key});

  @override
  ConsumerState<ClientsEditor> createState() => _ClientsEditorState();
}

class _ClientsEditorState extends ConsumerState<ClientsEditor> {
  bool _busy = false;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save client change: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsClientsSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.archiveClient(id);
      });

  Future<void> _unarchive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.unarchiveClient(id);
      });

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clientsDeleteConfirmTitle),
        content: Text(l10n.clientsDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      try {
        await writes.deleteClient(id);
      } on ClientHasProjectsException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.clientsDeleteHasProjectsError)),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeClients = ref.watch(activeClientsProvider).value ?? const <Client>[];
    final archivedClients = ref.watch(archivedClientsProvider).value ?? const <Client>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsClientsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsClientsDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final client in activeClients)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(client.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.clientsEditTooltip,
                  onPressed: _busy
                      ? null
                      : () => showClientFormDialog(context, ref, client: client),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  tooltip: l10n.clientsArchiveTooltip,
                  onPressed: _busy ? null : () => _archive(client.id),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.clientsDeleteTooltip,
                  onPressed: _busy ? null : () => _delete(client.id),
                ),
              ],
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsClientsAddLabel),
          onPressed: _busy ? null : () => showClientFormDialog(context, ref),
        ),
        if (archivedClients.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.settingsClientsArchivedSection),
            children: [
              for (final client in archivedClients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    client.name,
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.unarchive_outlined),
                        tooltip: l10n.clientsUnarchiveTooltip,
                        onPressed: _busy ? null : () => _unarchive(client.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.clientsDeleteTooltip,
                        onPressed: _busy ? null : () => _delete(client.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
