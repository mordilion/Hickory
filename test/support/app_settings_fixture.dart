import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/app_settings_table.dart' show appSettingsRowId;

/// Builds an [AppSettingsRow] for tests, every field defaulting to what a
/// fresh install holds.
///
/// Tests go through this instead of drift's generated constructor so that
/// adding a non-nullable settings column stays a one-file change: the
/// generated constructor requires every non-nullable field, so each new
/// column would otherwise break every literal in the suite at once.
AppSettingsRow appSettingsFixture({
  String id = appSettingsRowId,
  String dateFormat = 'iso',
  String timeFormat = '24h',
  String quickAddDurationsMinutes = '15,30,45,60',
  bool countPausedTimeAsBreak = false,
  int targetMinutesMonday = 0,
  int targetMinutesTuesday = 0,
  int targetMinutesWednesday = 0,
  int targetMinutesThursday = 0,
  int targetMinutesFriday = 0,
  int targetMinutesSaturday = 0,
  int targetMinutesSunday = 0,
  String targetInputMode = 'perWeekday',
  String balanceResetMode = 'none',
  int? balanceResetDay,
  int? balanceResetMonth,
  int? carryOverMaxMinutes,
  int? carryOverMinMinutes,
  bool absenceTrackingEnabled = false,
  DateTime? updatedAt,
}) {
  return AppSettingsRow(
    id: id,
    dateFormat: dateFormat,
    timeFormat: timeFormat,
    quickAddDurationsMinutes: quickAddDurationsMinutes,
    countPausedTimeAsBreak: countPausedTimeAsBreak,
    targetMinutesMonday: targetMinutesMonday,
    targetMinutesTuesday: targetMinutesTuesday,
    targetMinutesWednesday: targetMinutesWednesday,
    targetMinutesThursday: targetMinutesThursday,
    targetMinutesFriday: targetMinutesFriday,
    targetMinutesSaturday: targetMinutesSaturday,
    targetMinutesSunday: targetMinutesSunday,
    targetInputMode: targetInputMode,
    balanceResetMode: balanceResetMode,
    balanceResetDay: balanceResetDay,
    balanceResetMonth: balanceResetMonth,
    carryOverMaxMinutes: carryOverMaxMinutes,
    carryOverMinMinutes: carryOverMinMinutes,
    absenceTrackingEnabled: absenceTrackingEnabled,
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  );
}
