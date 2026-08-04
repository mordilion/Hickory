import 'package:drift/drift.dart';

/// A single break-time requirement: once a day's worked time reaches
/// [afterMinutes], at least [requiredBreakMinutes] of break time is
/// required that day. Multiple tiers let the user model tiered rules (e.g.
/// 30 min after 6h, 45 min after 9h) -- evaluation picks the tier with the
/// highest [afterMinutes] that the day's worked time has reached. Synced
/// across the user's own devices via the event log, like every other
/// entity. See docs/superpowers/specs/2026-08-04-break-rule-tiers-design.md.
@DataClassName('BreakRuleTier')
class BreakRuleTiers extends Table {
  TextColumn get id => text()();
  IntColumn get afterMinutes => integer()();
  IntColumn get requiredBreakMinutes => integer()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
