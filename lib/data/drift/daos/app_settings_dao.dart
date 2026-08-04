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

  Future<AppSettingsRow> updateSettings({
    String? dateFormat,
    String? timeFormat,
    String? quickAddDurationsMinutes,
    bool? countPausedTimeAsBreak,
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
        updatedAt: DateTime.now().toUtc(),
      );
}
