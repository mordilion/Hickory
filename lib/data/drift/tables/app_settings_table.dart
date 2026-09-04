import 'package:drift/drift.dart';

/// A singleton settings row — always exactly one record, keyed by the
/// fixed id [appSettingsRowId] rather than a generated UUID, since there is
/// exactly one current value per synced identity. Deliberately holds more
/// than just date/time format so a future setting (e.g. the planned i18n
/// language preference) can be added as a new column without introducing a
/// second synced singleton entity type.
const appSettingsRowId = 'default';

@DataClassName('AppSettingsRow')
class AppSettings extends Table {
  TextColumn get id => text()();
  TextColumn get dateFormat => text().withDefault(const Constant('iso'))();
  TextColumn get timeFormat => text().withDefault(const Constant('24h'))();
  TextColumn get quickAddDurationsMinutes =>
      text().withDefault(const Constant('15,30,45,60'))();
  // Whether a running entry's explicit Timer-pause time (see
  // TimeEntries.totalPausedSeconds) counts toward a day's break time for
  // the break-rule-tiers feature. Off by default: the feature's original
  // definition of "break" is gaps between entries only, and this setting
  // is an opt-in for users who track lunch via the pause button instead of
  // stop/restart. See break_rule_calculations.dart's dayBreakDuration.
  BoolColumn get countPausedTimeAsBreak => boolean().withDefault(const Constant(false))();
  // Per-weekday target work time in minutes. 0 means "not a work day" and
  // doubles as the free-day marker, so no separate flag is needed. These
  // seven values are the single source of truth for every target and
  // balance calculation; a weekly figure entered in Settings is
  // distributed across them on save and never stored separately.
  IntColumn get targetMinutesMonday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesTuesday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesWednesday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesThursday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesFriday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesSaturday => integer().withDefault(const Constant(0))();
  IntColumn get targetMinutesSunday => integer().withDefault(const Constant(0))();
  // 'perWeekday' | 'perWeek' -- affects only how the settings screen
  // renders and reopens, never the calculation.
  TextColumn get targetInputMode => text().withDefault(const Constant('perWeekday'))();
  // 'none' | 'resetToZero' | 'carryOver' -- what happens to the accumulated
  // balance when the yearly cutoff is crossed.
  TextColumn get balanceResetMode => text().withDefault(const Constant('none'))();
  // The recurring cutoff, so a fiscal year end works as well as a calendar
  // one. Both null while balanceResetMode is 'none'.
  IntColumn get balanceResetDay => integer().nullable()();
  IntColumn get balanceResetMonth => integer().nullable()();
  // Bounds of what survives a cutoff in 'carryOver' mode; null means
  // unbounded on that side.
  IntColumn get carryOverMaxMinutes => integer().nullable()();
  IntColumn get carryOverMinMinutes => integer().nullable()();
  // Global switch for the absence feature (phase 2). Declared here so the
  // AppSettings row needs only one migration across the whole design.
  BoolColumn get absenceTrackingEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
