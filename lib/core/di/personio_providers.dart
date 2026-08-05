import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/personio/http_personio_client.dart';
import '../../features/personio/personio_client.dart';
import '../../features/personio/personio_credentials_store.dart';
import '../../features/personio/personio_sync_service.dart';
import '../../features/personio/secure_personio_credentials_store.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

// Plain (non-generated) providers -- see jira_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final personioCredentialsStoreProvider = Provider<PersonioCredentialsStore>(
  (ref) => SecurePersonioCredentialsStore(),
);

/// The configured Personio credentials, or null if Personio hasn't been set
/// up on this device yet. Invalidate this provider after writing new
/// credentials to pick them up immediately.
final personioCredentialsProvider = FutureProvider<PersonioCredentials?>((ref) async {
  final store = ref.watch(personioCredentialsStoreProvider);
  return store.read();
});

/// The Personio API client, or null until credentials are configured.
final personioClientProvider = FutureProvider<PersonioClient?>((ref) async {
  final credentials = await ref.watch(personioCredentialsProvider.future);
  if (credentials == null) return null;
  return HttpPersonioClient(credentials: credentials);
});

/// The push reconciliation service, or null until credentials are
/// configured.
final personioSyncServiceProvider = FutureProvider<PersonioSyncService?>((ref) async {
  final client = await ref.watch(personioClientProvider.future);
  if (client == null) return null;
  final db = ref.watch(appDatabaseProvider);
  final writes = await ref.watch(syncedWritesProvider.future);
  return PersonioSyncService(db: db, client: client, writes: writes);
});

/// The latest successful push's timestamp across all tracked attendances, or
/// null if nothing has been pushed yet -- used to default the Sync screen's
/// push-range picker to "the day after the last successful push".
final personioLatestSyncedAtProvider = FutureProvider<DateTime?>((ref) {
  return ref.watch(appDatabaseProvider).personioAttendancesDao.latestSyncedAt();
});
