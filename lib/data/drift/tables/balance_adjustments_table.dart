import 'package:drift/drift.dart';

/// A dated, signed correction to the flex-time balance: three days paid
/// out, an hour granted, a figure carried over from the system this one
/// replaced.
///
/// Corrections are recorded rather than applied by rewriting history —
/// every one of them stays visible, dated and annotated, and can be taken
/// back by deleting the row. [deltaMinutes] is signed: negative takes time
/// off the balance, positive adds it.
///
/// Available whatever the reset rule says. A cutoff that resets or clamps
/// the balance is a rule; a correction is a fact about one day, and the
/// two are applied in that order — the correction lands on its date, then
/// that date's cutoff is evaluated (see `runningBalance`).
///
/// Synced across the user's own devices via the event log, like every
/// other entity. See
/// docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md.
@DataClassName('BalanceAdjustment')
class BalanceAdjustments extends Table {
  TextColumn get id => text()();
  // The day the correction takes effect, stored as that day's *local*
  // midnight — the same convention Absences.date follows, so the balance
  // pass can compare the two without converting.
  DateTimeColumn get date => dateTime()();
  IntColumn get deltaMinutes => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
