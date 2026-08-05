import 'package:drift/drift.dart';

/// Values used in [PersonioAttendanceRow.status].
abstract final class PersonioAttendanceStatus {
  static const pending = 'pending';
  static const synced = 'synced';
  static const error = 'error';
  static const pendingDelete = 'pendingDelete';
}

/// Tracks the Personio attendance-period push state for one time entry (1:1,
/// keyed by the entry's own id). Deliberately has no `.references(TimeEntries,
/// #id)` -- this row must be able to outlive its time entry so a delete can
/// still be pushed to Personio after the entry itself is gone locally (see
/// [PersonioAttendanceStatus.pendingDelete]).
///
/// Synced across the user's own devices via the event log (see
/// EntityTypes.personioAttendance) -- otherwise a second device wouldn't know
/// an entry was already pushed and would create a duplicate attendance period
/// on its own next push. See
/// docs/superpowers/specs/2026-08-05-personio-sync-design.md.
@DataClassName('PersonioAttendanceRow')
class PersonioAttendances extends Table {
  TextColumn get id => text()();
  // Personio-assigned attendance-period id; null until the first successful push.
  TextColumn get personioAttendanceId => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant(PersonioAttendanceStatus.pending))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
