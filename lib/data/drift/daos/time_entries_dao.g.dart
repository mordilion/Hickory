// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'time_entries_dao.dart';

// ignore_for_file: type=lint
mixin _$TimeEntriesDaoMixin on DatabaseAccessor<AppDatabase> {
  $ClientsTable get clients => attachedDatabase.clients;
  $ProjectsTable get projects => attachedDatabase.projects;
  $TimeEntriesTable get timeEntries => attachedDatabase.timeEntries;
  TimeEntriesDaoManager get managers => TimeEntriesDaoManager(this);
}

class TimeEntriesDaoManager {
  final _$TimeEntriesDaoMixin _db;
  TimeEntriesDaoManager(this._db);
  $$ClientsTableTableManager get clients =>
      $$ClientsTableTableManager(_db.attachedDatabase, _db.clients);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db.attachedDatabase, _db.projects);
  $$TimeEntriesTableTableManager get timeEntries =>
      $$TimeEntriesTableTableManager(_db.attachedDatabase, _db.timeEntries);
}
