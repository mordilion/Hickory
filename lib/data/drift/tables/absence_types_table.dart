import 'package:drift/drift.dart';

/// A user-defined kind of absence — vacation, sickness, a public holiday,
/// unpaid leave. Nothing is hard-coded: Hickory is used internationally
/// and against different employment contracts, so the same reasoning that
/// keeps labour law out of BreakRuleTiers keeps absence kinds out of here.
///
/// [paid] decides how a day carrying this absence is scored. A paid
/// absence credits time toward the day's target; an unpaid one reduces the
/// target instead. Both leave a full day neutral in the balance, but the
/// reported target differs — which is the whole point of the flag.
///
/// Synced across the user's own devices via the event log, like every
/// other entity. See
/// docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md.
@DataClassName('AbsenceType')
class AbsenceTypes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get paid => boolean()();
  // Display order in Settings and in the recording form. Ties are broken
  // by name, so a fresh set of types created in one batch still lists
  // predictably.
  IntColumn get sortOrder => integer()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
