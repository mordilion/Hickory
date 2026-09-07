import 'package:drift/drift.dart';

/// The three shapes an absence can take. Stored as text rather than a
/// drift enum so an older peer ingesting a value it does not know reads a
/// harmless string instead of failing to decode the row.
const absencePortionFullDay = 'fullDay';
const absencePortionHalfDay = 'halfDay';
const absencePortionRange = 'range';

/// Which half of the day a `halfDay` absence covers. Null on every other
/// portion, and on half days recorded before this was asked for — the
/// credited time is half the target either way, so an older row and an
/// older peer both stay correct without it.
const absenceHalfDayMorning = 'morning';
const absenceHalfDayAfternoon = 'afternoon';

/// One day of absence: a vacation day, a sick day, a two-hour doctor's
/// appointment. Always **one row per calendar day** — a fortnight of
/// vacation entered once in the form becomes ten rows, skipping days whose
/// target is zero. That keeps the calculation a per-day lookup and lets a
/// single day be removed later; the cost is that a bulk entry is several
/// writes, which the write-through sync handles like any other batch.
///
/// [portion] is `fullDay`, `halfDay` or `range`. The first two store **no
/// minute figure** — only the portion — so the credited time is derived
/// from the day's target when it is read. An absence therefore stays
/// correct if the target is changed afterwards. `range` is the exception:
/// it carries [startAt] and [endAt] because its length is its own, not the
/// day's.
///
/// Synced across the user's own devices via the event log, like every
/// other entity. See
/// docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md.
@DataClassName('Absence')
class Absences extends Table {
  TextColumn get id => text()();
  // The calendar day this absence covers, stored as that day's *local*
  // midnight — the same key totalsByDay groups worked time by, so the two
  // line up without conversion.
  DateTimeColumn get date => dateTime()();
  // References AbsenceTypes.id. Deliberately no foreign key: the synced
  // tables carry none, so a row can outlive a peer's ordering of events.
  // Settings refuses to delete a type that is still referenced.
  TextColumn get absenceTypeId => text()();
  TextColumn get portion => text()();
  // `morning` or `afternoon`, set only when portion == absencePortionHalfDay.
  // Informational: it says which half was taken, not how much is credited.
  TextColumn get halfDayPart => text().nullable()();
  // UTC, set only when portion == absencePortionRange.
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get endAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
