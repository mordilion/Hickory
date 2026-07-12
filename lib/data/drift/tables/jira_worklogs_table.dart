import 'package:drift/drift.dart';

/// Values used in [JiraWorklogRow.status].
abstract final class JiraWorklogStatus {
  static const pending = 'pending';
  static const synced = 'synced';
  static const error = 'error';
  static const pendingDelete = 'pendingDelete';
}

/// Tracks the Jira worklog sync state for one time entry (1:1, keyed by the
/// entry's own id). Deliberately has no `.references(TimeEntries, #id)` —
/// this row must be able to outlive its time entry so a delete can still be
/// pushed to Jira after the entry itself is gone locally (see
/// [JiraWorklogStatus.pendingDelete]).
///
/// Synced across the user's own devices via the event log, like every other
/// entity (see EntityTypes.jiraWorklog) — otherwise a second device
/// wouldn't know an entry was already pushed and would create a duplicate
/// worklog on its own next sync.
@DataClassName('JiraWorklogRow')
class JiraWorklogs extends Table {
  TextColumn get id => text()();
  // Issue key the worklog currently exists under in Jira; null until the
  // first successful push.
  TextColumn get syncedTicketKey => text().nullable()();
  // Jira-assigned worklog id; null until the first successful push.
  TextColumn get jiraWorklogId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant(JiraWorklogStatus.pending))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
