import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_ingestor.dart';
import '../../data/sync/sync_log_writer.dart';
import '../../data/sync/sync_paths.dart';
import '../../data/sync/synced_writes.dart';
import 'database_provider.dart';
import 'device_id_provider.dart';

// Plain (non-generated) providers — see timer_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final syncLogWriterProvider = FutureProvider<SyncLogWriter>((ref) async {
  final root = await defaultSyncRoot();
  final deviceId = await ref.watch(deviceIdProvider.future);
  return SyncLogWriter(syncRoot: root, deviceId: deviceId);
});

final syncIngestorProvider = FutureProvider<SyncIngestor>((ref) async {
  final root = await defaultSyncRoot();
  final db = ref.watch(appDatabaseProvider);
  return SyncIngestor(db: db, syncRoot: root);
});

final syncedWritesProvider = FutureProvider<SyncedWrites>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final logWriter = await ref.watch(syncLogWriterProvider.future);
  return SyncedWrites(db: db, logWriter: logWriter);
});
