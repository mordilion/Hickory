import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/activity_samples_dao.dart';
import 'daos/events_dao.dart';
import 'daos/projects_dao.dart';
import 'daos/time_entries_dao.dart';
import 'tables/activity_samples_table.dart';
import 'tables/clients_table.dart';
import 'tables/events_table.dart';
import 'tables/projects_table.dart';
import 'tables/sync_file_states_table.dart';
import 'tables/tags_table.dart';
import 'tables/time_entries_table.dart';
import 'tables/time_entry_tags_table.dart';

part 'database.g.dart';

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
  ],
  daos: [ProjectsDao, TimeEntriesDao, EventsDao, ActivitySamplesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'hickory.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
