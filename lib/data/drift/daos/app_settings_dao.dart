import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/app_settings_table.dart';

part 'app_settings_dao.g.dart';

@DriftAccessor(tables: [AppSettings])
class AppSettingsDao extends DatabaseAccessor<AppDatabase> with _$AppSettingsDaoMixin {
  AppSettingsDao(super.db);

  /// Streams the current settings row, or the app's hardcoded defaults
  /// (iso date, 24h time) if no row has been written yet — matches
  /// Hickory's pre-existing output so nobody sees an unannounced change
  /// until they actually pick something in Settings.
  Stream<AppSettingsRow> watchSettings() {
    return (select(appSettings)..where((s) => s.id.equals(appSettingsRowId)))
        .watchSingleOrNull()
        .map((row) => row ?? _defaultRow());
  }

  /// Upserts the singleton row, changing only the fields passed in.
  ///
  /// Non-nullable fields take a plain nullable parameter (`null` = leave
  /// alone). The four nullable balance fields take a [Value] instead,
  /// because `null` there has to stay usable as a real value — clearing a
  /// carry-over bound is a legitimate edit, and `??` could never express it.
  Future<AppSettingsRow> updateSettings({
    String? dateFormat,
    String? timeFormat,
    String? quickAddDurationsMinutes,
    bool? countPausedTimeAsBreak,
    int? targetMinutesMonday,
    int? targetMinutesTuesday,
    int? targetMinutesWednesday,
    int? targetMinutesThursday,
    int? targetMinutesFriday,
    int? targetMinutesSaturday,
    int? targetMinutesSunday,
    String? targetInputMode,
    String? balanceResetMode,
    Value<int?> balanceResetDay = const Value.absent(),
    Value<int?> balanceResetMonth = const Value.absent(),
    Value<int?> carryOverMaxMinutes = const Value.absent(),
    Value<int?> carryOverMinMinutes = const Value.absent(),
    bool? absenceTrackingEnabled,
  }) async {
    final current =
        await (select(appSettings)..where((s) => s.id.equals(appSettingsRowId))).getSingleOrNull() ??
            _defaultRow();
    final updated = AppSettingsRow(
      id: appSettingsRowId,
      dateFormat: dateFormat ?? current.dateFormat,
      timeFormat: timeFormat ?? current.timeFormat,
      quickAddDurationsMinutes: quickAddDurationsMinutes ?? current.quickAddDurationsMinutes,
      countPausedTimeAsBreak: countPausedTimeAsBreak ?? current.countPausedTimeAsBreak,
      targetMinutesMonday: targetMinutesMonday ?? current.targetMinutesMonday,
      targetMinutesTuesday: targetMinutesTuesday ?? current.targetMinutesTuesday,
      targetMinutesWednesday: targetMinutesWednesday ?? current.targetMinutesWednesday,
      targetMinutesThursday: targetMinutesThursday ?? current.targetMinutesThursday,
      targetMinutesFriday: targetMinutesFriday ?? current.targetMinutesFriday,
      targetMinutesSaturday: targetMinutesSaturday ?? current.targetMinutesSaturday,
      targetMinutesSunday: targetMinutesSunday ?? current.targetMinutesSunday,
      targetInputMode: targetInputMode ?? current.targetInputMode,
      balanceResetMode: balanceResetMode ?? current.balanceResetMode,
      balanceResetDay:
          balanceResetDay.present ? balanceResetDay.value : current.balanceResetDay,
      balanceResetMonth:
          balanceResetMonth.present ? balanceResetMonth.value : current.balanceResetMonth,
      carryOverMaxMinutes:
          carryOverMaxMinutes.present ? carryOverMaxMinutes.value : current.carryOverMaxMinutes,
      carryOverMinMinutes:
          carryOverMinMinutes.present ? carryOverMinMinutes.value : current.carryOverMinMinutes,
      absenceTrackingEnabled: absenceTrackingEnabled ?? current.absenceTrackingEnabled,
      updatedAt: DateTime.now().toUtc(),
    );
    await into(appSettings).insertOnConflictUpdate(updated);
    return updated;
  }

  AppSettingsRow _defaultRow() => AppSettingsRow(
        id: appSettingsRowId,
        dateFormat: 'iso',
        timeFormat: '24h',
        quickAddDurationsMinutes: '15,30,45,60',
        countPausedTimeAsBreak: false,
        targetMinutesMonday: 0,
        targetMinutesTuesday: 0,
        targetMinutesWednesday: 0,
        targetMinutesThursday: 0,
        targetMinutesFriday: 0,
        targetMinutesSaturday: 0,
        targetMinutesSunday: 0,
        targetInputMode: 'perWeekday',
        balanceResetMode: 'none',
        absenceTrackingEnabled: false,
        updatedAt: DateTime.now().toUtc(),
      );
}
