// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'absences_dao.dart';

// ignore_for_file: type=lint
mixin _$AbsencesDaoMixin on DatabaseAccessor<AppDatabase> {
  $AbsencesTable get absences => attachedDatabase.absences;
  AbsencesDaoManager get managers => AbsencesDaoManager(this);
}

class AbsencesDaoManager {
  final _$AbsencesDaoMixin _db;
  AbsencesDaoManager(this._db);
  $$AbsencesTableTableManager get absences =>
      $$AbsencesTableTableManager(_db.attachedDatabase, _db.absences);
}
