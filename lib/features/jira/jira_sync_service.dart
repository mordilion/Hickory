import 'package:drift/drift.dart' show Value;

import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../data/sync/synced_writes.dart';
import 'jira_client.dart';

/// Outcome of one [JiraSyncService.syncNow] run, for display in the UI.
class JiraSyncResult {
  const JiraSyncResult({
    required this.created,
    required this.updated,
    required this.deleted,
    required this.failed,
  });

  final int created;
  final int updated;
  final int deleted;
  final int failed;

  int get total => created + updated + deleted + failed;
}

enum _Outcome { created, updated, deleted, skipped, failed }

/// Reconciles every finished time entry's `jiraTicketKey` against Jira
/// worklogs, per the algorithm in
/// docs/superpowers/specs/2026-07-12-jira-ticket-booking-design.md. Pure
/// push: never reads worklogs Jira already knows about back into Hickory.
class JiraSyncService {
  JiraSyncService({required this.db, required this.client, required this.writes});

  final AppDatabase db;
  final JiraClient client;
  final SyncedWrites writes;

  Future<JiraSyncResult> syncNow() async {
    final worklogsByEntryId = {for (final w in await db.jiraWorklogsDao.getAll()) w.id: w};
    final counts = <_Outcome, int>{};

    for (final worklog in worklogsByEntryId.values) {
      if (worklog.status != JiraWorklogStatus.pendingDelete) continue;
      final outcome = await _reconcilePendingDelete(worklog);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    final entries = await db.timeEntriesDao.getAllEntries();
    for (final entry in entries) {
      if (entry.endAt == null) continue;
      final worklog = worklogsByEntryId[entry.id];
      if (worklog?.status == JiraWorklogStatus.pendingDelete) continue;
      final outcome = await _reconcileEntry(entry, worklog);
      counts.update(outcome, (n) => n + 1, ifAbsent: () => 1);
    }

    return JiraSyncResult(
      created: counts[_Outcome.created] ?? 0,
      updated: counts[_Outcome.updated] ?? 0,
      deleted: counts[_Outcome.deleted] ?? 0,
      failed: counts[_Outcome.failed] ?? 0,
    );
  }

  /// Reduces any caught error to a message safe for `lastError`, which is
  /// stored locally AND propagated to every device via the synced event
  /// log: [JiraApiException]'s message is caller-safe by construction, but
  /// a raw transport exception's `toString()` (e.g. `SocketException`,
  /// `http.ClientException`) can embed the request URI — including the
  /// user's Jira base URL, one of the credential fields that must never
  /// leave this device (see the design doc's credentials-not-synced rule).
  String _safeErrorMessage(Object error) =>
      error is JiraApiException ? error.message : 'Network or connection error';

  Future<_Outcome> _reconcilePendingDelete(JiraWorklogRow worklog) async {
    try {
      if (worklog.jiraWorklogId != null && worklog.syncedTicketKey != null) {
        await client.deleteWorklog(
          issueKey: worklog.syncedTicketKey!,
          worklogId: worklog.jiraWorklogId!,
        );
      }
      await writes.deleteJiraWorklogState(worklog.id);
      return _Outcome.deleted;
    } catch (e) {
      // Deliberately does NOT change status away from pendingDelete: by the
      // time this row is reconciled, its TimeEntry is already gone (see
      // SyncedWrites.deleteEntry), so it's only ever revisited by the
      // pendingDelete branch above, never by _reconcileEntry's entries loop.
      // Flipping status to `error` here would orphan the row outside both
      // loops forever, leaking the Jira-side worklog and breaking the
      // "retried automatically on the next sync" guarantee.
      await writes.upsertJiraWorklogState(worklog.copyWith(lastError: Value(_safeErrorMessage(e))));
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _reconcileEntry(TimeEntry entry, JiraWorklogRow? worklog) async {
    final ticketKey = entry.jiraTicketKey;

    if (ticketKey == null) {
      return _handleTicketRemoved(entry.id, worklog);
    }
    if (worklog == null) {
      return _pushCreate(entry: entry, ticketKey: ticketKey);
    }
    if (worklog.syncedTicketKey != null && worklog.syncedTicketKey != ticketKey) {
      return _pushMove(entry: entry, ticketKey: ticketKey, oldWorklog: worklog);
    }
    final needsUpdate = worklog.syncedAt == null || entry.updatedAt.isAfter(worklog.syncedAt!);
    if (!needsUpdate) return _Outcome.skipped;
    if (worklog.jiraWorklogId == null) {
      return _pushCreate(entry: entry, ticketKey: ticketKey);
    }
    return _pushUpdate(entry: entry, ticketKey: ticketKey, worklog: worklog);
  }

  Future<_Outcome> _handleTicketRemoved(String entryId, JiraWorklogRow? worklog) async {
    if (worklog == null) return _Outcome.skipped;
    if (worklog.jiraWorklogId == null) {
      await writes.deleteJiraWorklogState(entryId);
      return _Outcome.skipped;
    }
    await writes.upsertJiraWorklogState(worklog.copyWith(status: JiraWorklogStatus.pendingDelete));
    return _Outcome.skipped;
  }

  Future<_Outcome> _pushCreate({required TimeEntry entry, required String ticketKey}) async {
    try {
      final worklogId = await client.createWorklog(
        issueKey: ticketKey,
        timeSpent: entry.workedDuration,
        startedAt: entry.startAt,
        comment: entry.description,
      );
      await writes.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: ticketKey,
          jiraWorklogId: worklogId,
          status: JiraWorklogStatus.synced,
          lastError: null,
          syncedAt: DateTime.now().toUtc(),
        ),
      );
      return _Outcome.created;
    } catch (e) {
      await writes.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: null,
          jiraWorklogId: null,
          status: JiraWorklogStatus.error,
          lastError: _safeErrorMessage(e),
          syncedAt: null,
        ),
      );
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _pushMove({
    required TimeEntry entry,
    required String ticketKey,
    required JiraWorklogRow oldWorklog,
  }) async {
    if (oldWorklog.jiraWorklogId != null) {
      try {
        await client.deleteWorklog(
          issueKey: oldWorklog.syncedTicketKey!,
          worklogId: oldWorklog.jiraWorklogId!,
        );
      } catch (e) {
        // client.deleteWorklog already treats "already gone" (404) as
        // success, so anything reaching this catch is a genuine failure
        // (network/auth/500) — proceeding to create on the new ticket
        // regardless would leave the old worklog booked in Jira forever
        // with no record of it. Keep the old worklog's tracking as-is
        // (still `synced` to the OLD ticket) so this move is retried in
        // full on the next sync, instead of silently losing the old side.
        await writes.upsertJiraWorklogState(
          oldWorklog.copyWith(status: JiraWorklogStatus.error, lastError: Value(_safeErrorMessage(e))),
        );
        return _Outcome.failed;
      }
    }
    final outcome = await _pushCreate(entry: entry, ticketKey: ticketKey);
    return outcome == _Outcome.created ? _Outcome.updated : _Outcome.failed;
  }

  Future<_Outcome> _pushUpdate({
    required TimeEntry entry,
    required String ticketKey,
    required JiraWorklogRow worklog,
  }) async {
    try {
      await client.updateWorklog(
        issueKey: ticketKey,
        worklogId: worklog.jiraWorklogId!,
        timeSpent: entry.workedDuration,
        startedAt: entry.startAt,
        comment: entry.description,
      );
      await writes.upsertJiraWorklogState(
        worklog.copyWith(
          syncedTicketKey: Value(ticketKey),
          status: JiraWorklogStatus.synced,
          syncedAt: Value(DateTime.now().toUtc()),
          lastError: const Value(null),
        ),
      );
      return _Outcome.updated;
    } catch (e) {
      await writes.upsertJiraWorklogState(
        worklog.copyWith(status: JiraWorklogStatus.error, lastError: Value(_safeErrorMessage(e))),
      );
      return _Outcome.failed;
    }
  }
}
