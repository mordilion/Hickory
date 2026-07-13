import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import '../../features/jira/http_jira_client.dart';
import '../../features/jira/jira_client.dart';
import '../../features/jira/jira_credentials_store.dart';
import '../../features/jira/jira_sync_service.dart';
import '../../features/jira/secure_jira_credentials_store.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

// Plain (non-generated) providers — see timer_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final jiraCredentialsStoreProvider = Provider<JiraCredentialsStore>(
  (ref) => SecureJiraCredentialsStore(),
);

/// The configured Jira credentials, or null if Jira hasn't been set up on
/// this device yet. Invalidate this provider after writing new credentials
/// to pick them up immediately.
final jiraCredentialsProvider = FutureProvider<JiraCredentials?>((ref) async {
  final store = ref.watch(jiraCredentialsStoreProvider);
  return store.read();
});

/// The Jira API client, or null until credentials are configured.
final jiraClientProvider = FutureProvider<JiraClient?>((ref) async {
  final credentials = await ref.watch(jiraCredentialsProvider.future);
  if (credentials == null) return null;
  return HttpJiraClient(credentials: credentials);
});

/// The sync reconciliation service, or null until credentials are
/// configured.
final jiraSyncServiceProvider = FutureProvider<JiraSyncService?>((ref) async {
  final client = await ref.watch(jiraClientProvider.future);
  if (client == null) return null;
  final db = ref.watch(appDatabaseProvider);
  final writes = await ref.watch(syncedWritesProvider.future);
  return JiraSyncService(db: db, client: client, writes: writes);
});

/// All Jira worklog tracking rows keyed by time-entry id, for the entries
/// list's per-entry status indicator.
final jiraWorklogsByEntryIdProvider = StreamProvider<Map<String, JiraWorklogRow>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .jiraWorklogsDao
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row});
});
