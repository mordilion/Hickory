import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';

Future<void> showSyncSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SyncSettingsDialog(),
  );
}

class _SyncSettingsDialog extends ConsumerStatefulWidget {
  const _SyncSettingsDialog();

  @override
  ConsumerState<_SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends ConsumerState<_SyncSettingsDialog> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _pickFolder() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final picked = await pickAndApplySyncFolder(ref);
      setState(() {
        _statusMessage = picked == null ? null : 'Ordner gewählt: $picked';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final ingestor = await ref.read(syncIngestorProvider.future);
      await ingestor.syncNow();
      setState(() => _statusMessage = 'Synchronisierung abgeschlossen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final folderAsync = ref.watch(configuredSyncFolderPathProvider);

    return AlertDialog(
      title: const Text('Sync-Einstellungen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            folderAsync.when(
              data: (path) => Text(
                path == null
                    ? 'Kein Ordner gewählt – Daten bleiben nur lokal auf diesem Gerät.'
                    : 'Sync-Ordner: $path',
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Fehler: $e'),
            ),
            const SizedBox(height: 8),
            Text(
              'Wähle einen Ordner, der bereits von iCloud Drive, Google Drive, '
              'Dropbox o.ä. synchronisiert wird. Hickory schreibt dort nur '
              'eigene Dateien und synchronisiert sich selbst nicht mit der Cloud.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(_statusMessage!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _syncNow,
          child: const Text('Jetzt synchronisieren'),
        ),
        FilledButton(
          onPressed: _busy ? null : _pickFolder,
          child: const Text('Ordner wählen'),
        ),
      ],
    );
  }
}
