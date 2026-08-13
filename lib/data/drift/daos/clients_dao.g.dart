// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clients_dao.dart';

// ignore_for_file: type=lint
mixin _$ClientsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ClientsTable get clients => attachedDatabase.clients;
  ClientsDaoManager get managers => ClientsDaoManager(this);
}

class ClientsDaoManager {
  final _$ClientsDaoMixin _db;
  ClientsDaoManager(this._db);
  $$ClientsTableTableManager get clients =>
      $$ClientsTableTableManager(_db.attachedDatabase, _db.clients);
}
