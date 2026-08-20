import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import '../../features/jira/http_jira_client.dart';
import '../../features/jira/jira_client.dart';
import '../../features/jira/jira_credentials_store.dart';
import '../../features/jira/jira_sync_service.dart';
import '../../features/jira/secure_jira_credentials_store.dart';
import '../../data/sync/auto_sync_trigger.dart';
import '../../features/timer/timer_providers.dart';
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

/// How long the automatic reconciliation waits after a change before it
/// runs, so editing several entries in a row costs one run instead of one
/// per edit. Overridden in tests to keep them fast.
final jiraAutoSyncDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// Runs [JiraSyncService.syncNow] at app start and, debounced, after every
/// time-entry write — otherwise a user who never opens the Sync tab never
/// books to Jira, and an edit to an already-booked entry is never pushed
/// (see docs/superpowers/specs/2026-08-19-sync-error-visibility-design.md
/// §3). Deliberately no periodic timer: every run answers a real change,
/// which keeps the load on Jira's per-account rate limit proportional to
/// what the user actually did.
///
/// Silent by design. `syncNow` is idempotent and records its own per-entry
/// outcome in the worklog row, which the entries list already shows, so a
/// background run needs no dialog and a redundant one cannot corrupt
/// state. Does nothing while Jira is unconfigured: no credentials must
/// mean "skip", never an error written to every row.
///
/// Activated by watching it for the app's lifetime (see TimerScreen, which
/// does the same for [syncWatcherProvider]).
final jiraAutoSyncProvider = Provider<AutoSyncTrigger>((ref) {
  final trigger = AutoSyncTrigger(
    () async {
      final service = await ref.read(jiraSyncServiceProvider.future);
      if (service == null) return;
      await service.syncNow();
    },
    debounce: ref.watch(jiraAutoSyncDebounceProvider),
  );
  ref.onDispose(trigger.dispose);

  // Every local write lands in this stream, as does every entry ingested
  // from another device — both are changes this device may have to push.
  ref.listen(allEntriesProvider, (previous, next) {
    if (next.hasValue) trigger.schedule();
  });

  trigger.schedule();
  return trigger;
});
