import 'dart:io';

import '../../core/locale/locale_store.dart';
import '../../features/jira/jira_credentials_store.dart';
import '../../features/personio/personio_credentials_store.dart';
import '../drift/database.dart';
import '../sync/sync_paths.dart';

/// Returns this device to a fresh-install state: every local drift row is
/// deleted, this device's own sync event-log files are deleted (so the next
/// sync pass can't re-ingest and resurrect its own history -- see
/// docs/superpowers/specs/2026-08-05-project-delete-and-full-reset-design.md
/// section 3.1 for why that matters), the configured sync folder is
/// forgotten, and third-party credentials plus the locale preference are
/// cleared. Deliberately bypasses SyncedWrites/the event log entirely: this
/// *is* the sync state being cleared, so it can't go through that pipeline.
/// Table deletion order in `resetEverything` is arbitrary -- safe only
/// because this app never enables `PRAGMA foreign_keys`; enabling it later
/// would require ordering these deletes.
class AppResetService {
  AppResetService({
    required this.db,
    required this.deviceId,
    required this.effectiveSyncRoot,
    required this.defaultSyncRoot,
    required this.clearSyncFolder,
    required this.jiraCredentialsStore,
    required this.personioCredentialsStore,
    required this.localeStore,
  });

  final AppDatabase db;
  final String deviceId;
  final Directory effectiveSyncRoot;
  final Directory defaultSyncRoot;
  final Future<void> Function() clearSyncFolder;
  final JiraCredentialsStore jiraCredentialsStore;
  final PersonioCredentialsStore personioCredentialsStore;
  final LocaleStore localeStore;

  Future<void> resetEverything() async {
    await _deleteDeviceLogDir(effectiveSyncRoot);
    await _deleteDeviceLogDir(defaultSyncRoot);
    await db.transaction(() async {
      for (final table in db.allTables) {
        await db.delete(table).go();
      }
    });
    await clearSyncFolder();
    await jiraCredentialsStore.clear();
    await personioCredentialsStore.clear();
    await localeStore.clear();
  }

  Future<void> _deleteDeviceLogDir(Directory root) async {
    final dir = deviceLogDir(root, deviceId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
