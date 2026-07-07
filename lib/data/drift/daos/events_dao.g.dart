// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_dao.dart';

// ignore_for_file: type=lint
mixin _$EventsDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventsTable get events => attachedDatabase.events;
  $SyncFileStatesTable get syncFileStates => attachedDatabase.syncFileStates;
  EventsDaoManager get managers => EventsDaoManager(this);
}

class EventsDaoManager {
  final _$EventsDaoMixin _db;
  EventsDaoManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
  $$SyncFileStatesTableTableManager get syncFileStates =>
      $$SyncFileStatesTableTableManager(
        _db.attachedDatabase,
        _db.syncFileStates,
      );
}
