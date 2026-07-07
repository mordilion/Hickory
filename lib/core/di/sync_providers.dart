import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:storage_access/storage_access.dart';

import '../../data/sync/sync_folder_migration.dart';
import '../../data/sync/sync_ingestor.dart';
import '../../data/sync/sync_log_writer.dart';
import '../../data/sync/sync_paths.dart';
import '../../data/sync/synced_writes.dart';
import 'database_provider.dart';
import 'device_id_provider.dart';

// Plain (non-generated) providers — see timer_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final syncFolderProviderProvider = Provider<SyncFolderProvider>((ref) => SyncFolderProvider());

/// The user-picked, persisted sync folder path, or null if none has been
/// chosen yet. Invalidated by [pickAndApplySyncFolder] after a successful
/// pick, which cascades to every provider derived from it below.
final configuredSyncFolderPathProvider = FutureProvider<String?>((ref) async {
  final folderProvider = ref.watch(syncFolderProviderProvider);
  return folderProvider.restorePersistedFolder();
});

/// The directory Hickory actually reads/writes the event log in: the
/// user-configured folder if one is set, otherwise a local-only default —
/// so the app works before the user ever opens sync settings.
final effectiveSyncRootProvider = FutureProvider<Directory>((ref) async {
  final configuredPath = await ref.watch(configuredSyncFolderPathProvider.future);
  if (configuredPath != null) return Directory(configuredPath);
  return defaultSyncRoot();
});

final syncLogWriterProvider = FutureProvider<SyncLogWriter>((ref) async {
  final root = await ref.watch(effectiveSyncRootProvider.future);
  final deviceId = await ref.watch(deviceIdProvider.future);
  return SyncLogWriter(syncRoot: root, deviceId: deviceId);
});

final syncIngestorProvider = FutureProvider<SyncIngestor>((ref) async {
  final root = await ref.watch(effectiveSyncRootProvider.future);
  final db = ref.watch(appDatabaseProvider);
  return SyncIngestor(db: db, syncRoot: root);
});

final syncedWritesProvider = FutureProvider<SyncedWrites>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final logWriter = await ref.watch(syncLogWriterProvider.future);
  return SyncedWrites(db: db, logWriter: logWriter);
});

/// Runs an initial sync on startup, then watches the effective folder for
/// changes and re-syncs whenever it fires. The subscription lives for as
/// long as this provider stays referenced (a plain top-level provider is
/// kept alive once watched, so simply watching it from the UI is enough to
/// activate it for the app's lifetime).
final syncWatcherProvider = FutureProvider<void>((ref) async {
  final root = await ref.watch(effectiveSyncRootProvider.future);
  final folderProvider = ref.watch(syncFolderProviderProvider);
  final ingestor = await ref.watch(syncIngestorProvider.future);

  await ingestor.syncNow();

  final subscription = folderProvider.watch(root.path).listen((_) {
    ingestor.syncNow();
  });
  ref.onDispose(subscription.cancel);
});

/// Opens the native folder picker, migrates any pre-existing local-only
/// data into the chosen folder, persists the choice, and refreshes every
/// provider derived from it. Returns the picked path, or null if the user
/// cancelled the picker.
Future<String?> pickAndApplySyncFolder(WidgetRef ref) async {
  final folderProvider = ref.read(syncFolderProviderProvider);
  final picked = await folderProvider.pickFolder();
  if (picked == null) return null;

  final oldRoot = await ref.read(effectiveSyncRootProvider.future);
  await migrateLocalDataIfNeeded(oldRoot: oldRoot, newRoot: Directory(picked));

  await folderProvider.persistFolderPath(picked);
  ref.invalidate(configuredSyncFolderPathProvider);
  return picked;
}
