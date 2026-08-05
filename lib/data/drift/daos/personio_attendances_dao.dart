import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/personio_attendances_table.dart';

part 'personio_attendances_dao.g.dart';

@DriftAccessor(tables: [PersonioAttendances])
class PersonioAttendancesDao extends DatabaseAccessor<AppDatabase>
    with _$PersonioAttendancesDaoMixin {
  PersonioAttendancesDao(super.db);

  Stream<List<PersonioAttendanceRow>> watchAll() => select(personioAttendances).watch();

  Future<List<PersonioAttendanceRow>> getAll() => select(personioAttendances).get();

  Future<PersonioAttendanceRow?> getForEntry(String timeEntryId) {
    return (select(personioAttendances)..where((a) => a.id.equals(timeEntryId)))
        .getSingleOrNull();
  }

  Future<void> upsert(Insertable<PersonioAttendanceRow> row) {
    return into(personioAttendances).insertOnConflictUpdate(row);
  }

  Future<void> deleteForEntry(String timeEntryId) {
    return (delete(personioAttendances)..where((a) => a.id.equals(timeEntryId))).go();
  }

  /// Latest [PersonioAttendanceRow.syncedAt] among rows with
  /// `status == synced`, or null if nothing has ever been pushed. Used to
  /// default the Sync screen's push-range picker to "the day after the last
  /// successful push".
  Future<DateTime?> latestSyncedAt() async {
    final rows = await (select(personioAttendances)
          ..where((a) => a.status.equals(PersonioAttendanceStatus.synced)))
        .get();
    if (rows.isEmpty) return null;
    return rows.map((r) => r.syncedAt!).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
