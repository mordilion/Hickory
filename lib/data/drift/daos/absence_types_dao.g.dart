// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'absence_types_dao.dart';

// ignore_for_file: type=lint
mixin _$AbsenceTypesDaoMixin on DatabaseAccessor<AppDatabase> {
  $AbsenceTypesTable get absenceTypes => attachedDatabase.absenceTypes;
  AbsenceTypesDaoManager get managers => AbsenceTypesDaoManager(this);
}

class AbsenceTypesDaoManager {
  final _$AbsenceTypesDaoMixin _db;
  AbsenceTypesDaoManager(this._db);
  $$AbsenceTypesTableTableManager get absenceTypes =>
      $$AbsenceTypesTableTableManager(_db.attachedDatabase, _db.absenceTypes);
}
