// lib/features/sync/sync_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _pickFolder() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final picked = await pickAndApplySyncFolder(ref);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _statusMessage = picked == null ? null : l10n.syncFolderChosen(picked);
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
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _statusMessage = l10n.syncCompleted);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final folderAsync = ref.watch(configuredSyncFolderPathProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.syncTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  folderAsync.when(
                    data: (path) => Text(
                      path == null
                          ? l10n.syncNoFolderSelected
                          : l10n.syncFolderPath(path),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(l10n.syncError('$e')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.syncFolderDescription,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_statusMessage!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _syncNow,
                        child: Text(l10n.syncNowButton),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _pickFolder,
                        child: Text(l10n.syncChooseFolderButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
