import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/app_directories.dart';

import 'daos/absence_types_dao.dart';
import 'daos/absences_dao.dart';
import 'daos/activity_samples_dao.dart';
import 'daos/app_settings_dao.dart';
import 'daos/balance_adjustments_dao.dart';
import 'daos/break_rule_tiers_dao.dart';
import 'daos/clients_dao.dart';
import 'daos/events_dao.dart';
import 'daos/jira_worklogs_dao.dart';
import 'daos/personio_attendances_dao.dart';
import 'daos/projects_dao.dart';
import 'daos/time_entries_dao.dart';
import 'tables/absence_types_table.dart';
import 'tables/absences_table.dart';
import 'tables/balance_adjustments_table.dart';
import 'tables/activity_samples_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/break_rule_tiers_table.dart';
import 'tables/clients_table.dart';
import 'tables/events_table.dart';
import 'tables/jira_worklogs_table.dart';
import 'tables/personio_attendances_table.dart';
import 'tables/projects_table.dart';
import 'tables/sync_file_states_table.dart';
import 'tables/tags_table.dart';
import 'tables/time_entries_table.dart';
import 'tables/time_entry_tags_table.dart';

part 'database.g.dart';

/// Adds [column] to [table], treating "the column is already there" as
/// done rather than as a failure.
///
/// Two things make this necessary. A step that creates a table builds it
/// from that table's *current* definition, so a database arriving from
/// before that step already carries every column a later step adds —
/// `absences` and `half_day_part` were exactly that pair, and it broke
/// every upgrade from 1.3.x. And 1.4.0 shipped without the transaction
/// below, so databases exist that were half migrated and left with an old
/// `user_version`: they run these steps again over work already done.
///
/// Only that one message is swallowed; anything else is a real failure and
/// is rethrown so the transaction rolls the migration back.
Future<void> _addColumnIfMissing(
  Migrator m,
  TableInfo<Table, dynamic> table,
  GeneratedColumn<Object> column,
) async {
  try {
    await m.addColumn(table, column);
  } catch (error) {
    if (!error.toString().contains('duplicate column name')) rethrow;
  }
}

@DriftDatabase(
  tables: [
    Clients,
    Projects,
    Tags,
    TimeEntries,
    TimeEntryTags,
    Events,
    SyncFileStates,
    ActivitySamples,
    AppSettings,
    JiraWorklogs,
    BreakRuleTiers,
    PersonioAttendances,
    AbsenceTypes,
    Absences,
    BalanceAdjustments,
  ],
  daos: [
    ClientsDao,
    ProjectsDao,
    TimeEntriesDao,
    EventsDao,
    ActivitySamplesDao,
    AppSettingsDao,
    JiraWorklogsDao,
    BreakRuleTiersDao,
    PersonioAttendancesDao,
    AbsenceTypesDao,
    AbsencesDao,
    BalanceAdjustmentsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Migrations are all-or-nothing. SQLite has transactional DDL, so a
    // step that throws leaves the file exactly as it was; without this a
    // failure halfway leaves tables and columns behind while
    // `user_version` still names the old schema, and the next start walks
    // the same steps over work that is already done. 1.4.0 shipped that
    // way and bricked every upgrade from 1.3.x.
    //
    // BEGIN/COMMIT go through customStatement rather than `transaction()`
    // because that is the path drift itself uses while a migration holds
    // the database; a regular transaction queues behind the migration
    // asking for it and never returns.
    onUpgrade: (m, from, to) async {
      await m.database.customStatement('BEGIN');
      try {
        await _upgrade(m, from);
        await m.database.customStatement('COMMIT');
      } catch (_) {
        await m.database.customStatement('ROLLBACK');
        rethrow;
      }
    },
  );

  Future<void> _upgrade(Migrator m, int from) async {
      if (from < 2) {
        await _addColumnIfMissing(m, timeEntries, timeEntries.pausedAt);
        await _addColumnIfMissing(m, timeEntries, timeEntries.totalPausedSeconds);
      }
      if (from < 3) {
        await m.createTable(appSettings);
      }
      if (from < 4) {
        await _addColumnIfMissing(m, timeEntries, timeEntries.jiraTicketKey);
        await m.createTable(jiraWorklogs);
      }
      if (from < 5) {
        await _addColumnIfMissing(m, appSettings, appSettings.quickAddDurationsMinutes);
      }
      if (from < 6) {
        await m.createTable(breakRuleTiers);
      }
      if (from < 7) {
        await _addColumnIfMissing(m, appSettings, appSettings.countPausedTimeAsBreak);
      }
      if (from < 8) {
        await m.createTable(personioAttendances);
      }
      if (from < 9) {
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesMonday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesTuesday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesWednesday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesThursday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesFriday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesSaturday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetMinutesSunday);
        await _addColumnIfMissing(m, appSettings, appSettings.targetInputMode);
        await _addColumnIfMissing(m, appSettings, appSettings.balanceResetMode);
        await _addColumnIfMissing(m, appSettings, appSettings.balanceResetDay);
        await _addColumnIfMissing(m, appSettings, appSettings.balanceResetMonth);
        await _addColumnIfMissing(m, appSettings, appSettings.carryOverMaxMinutes);
        await _addColumnIfMissing(m, appSettings, appSettings.carryOverMinMinutes);
        await _addColumnIfMissing(m, appSettings, appSettings.absenceTrackingEnabled);
      }
      if (from < 10) {
        await m.createTable(absenceTypes);
      }
      if (from < 11) {
        await m.createTable(absences);
      }
      if (from < 12) {
        await _addColumnIfMissing(m, absences, absences.halfDayPart);
      }
      if (from < 13) {
        await m.createTable(balanceAdjustments);
      }
  }

  /// Shared with the sandbox-container migration, which has to name the file to
  /// know whether the target directory already holds live data.
  static const databaseFileName = 'hickory.sqlite';

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      // Not getApplicationDocumentsDirectory() any more: on macOS that now
      // means the user's own ~/Documents. See appDataDirectory().
      final dbFolder = await appDataDirectory();
      final file = File(p.join(dbFolder.path, databaseFileName));
      return NativeDatabase.createInBackground(file);
    });
  }
}
