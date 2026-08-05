// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personio_attendances_dao.dart';

// ignore_for_file: type=lint
mixin _$PersonioAttendancesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PersonioAttendancesTable get personioAttendances =>
      attachedDatabase.personioAttendances;
  PersonioAttendancesDaoManager get managers =>
      PersonioAttendancesDaoManager(this);
}

class PersonioAttendancesDaoManager {
  final _$PersonioAttendancesDaoMixin _db;
  PersonioAttendancesDaoManager(this._db);
  $$PersonioAttendancesTableTableManager get personioAttendances =>
      $$PersonioAttendancesTableTableManager(
        _db.attachedDatabase,
        _db.personioAttendances,
      );
}
