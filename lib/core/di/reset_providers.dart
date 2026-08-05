import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reset/app_reset_service.dart';
import '../../data/sync/sync_paths.dart';
import 'database_provider.dart';
import 'device_id_provider.dart';
import 'jira_providers.dart';
import 'locale_provider.dart';
import 'personio_providers.dart';
import 'sync_providers.dart';

// Plain (non-generated) provider -- same reasoning as sync_providers.dart:
// AppResetService's constructor touches AppDatabase (drift-generated).

final appResetServiceProvider = FutureProvider<AppResetService>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final deviceId = await ref.watch(deviceIdProvider.future);
  final effectiveRoot = await ref.watch(effectiveSyncRootProvider.future);
  final localeStore = await ref.watch(localeStoreProvider.future);
  return AppResetService(
    db: db,
    deviceId: deviceId,
    effectiveSyncRoot: effectiveRoot,
    defaultSyncRoot: await defaultSyncRoot(),
    clearSyncFolder: ref.watch(syncFolderProviderProvider).clearPersistedFolder,
    jiraCredentialsStore: ref.watch(jiraCredentialsStoreProvider),
    personioCredentialsStore: ref.watch(personioCredentialsStoreProvider),
    localeStore: localeStore,
  );
});
