import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/absences_table.dart';

part 'absences_dao.g.dart';

@DriftAccessor(tables: [Absences])
class AbsencesDao extends DatabaseAccessor<AppDatabase> with _$AbsencesDaoMixin {
  AbsencesDao(super.db);

  static const _uuid = Uuid();

  Stream<List<Absence>> watchAllAbsences() {
    return (select(absences)..orderBy([(a) => OrderingTerm.asc(a.date)])).watch();
  }

  Future<Absence> createAbsence({
    required String deviceId,
    required DateTime date,
    required String absenceTypeId,
    required String portion,
    DateTime? startAt,
    DateTime? endAt,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await into(absences).insert(
      AbsencesCompanion.insert(
        id: id,
        date: date,
        absenceTypeId: absenceTypeId,
        portion: portion,
        startAt: Value(startAt),
        endAt: Value(endAt),
        note: Value(note),
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (select(absences)..where((a) => a.id.equals(id))).getSingle();
  }

  /// Updates only what is passed in; an absent parameter leaves its column
  /// alone, and an explicit `Value(null)` clears it — the time range has to
  /// be erasable when a range absence becomes a whole day. The day the row
  /// covers is deliberately not editable: `date` is the key the balance and
  /// the entries list group by, and moving a row between days is recording
  /// a different absence. Always bumps [updatedAt], because the sync log
  /// orders events by it.
  Future<Absence> updateAbsence(
    String id, {
    String? absenceTypeId,
    String? portion,
    Value<DateTime?> startAt = const Value.absent(),
    Value<DateTime?> endAt = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) async {
    await (update(absences)..where((a) => a.id.equals(id))).write(
      AbsencesCompanion(
        absenceTypeId: absenceTypeId == null ? const Value.absent() : Value(absenceTypeId),
        portion: portion == null ? const Value.absent() : Value(portion),
        startAt: startAt,
        endAt: endAt,
        note: note,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return (select(absences)..where((a) => a.id.equals(id))).getSingle();
  }

  Future<void> deleteAbsence(String id) {
    return (delete(absences)..where((a) => a.id.equals(id))).go();
  }

  /// How many absence rows still reference [absenceTypeId]. Settings uses
  /// this to refuse deleting a type that is in use, rather than leaving
  /// rows pointing at a type that no longer exists — the tables carry no
  /// foreign key, so nothing else would stop it.
  Future<int> countByType(String absenceTypeId) async {
    final count = absences.id.count();
    final query = selectOnly(absences)
      ..addColumns([count])
      ..where(absences.absenceTypeId.equals(absenceTypeId));
    return (await query.getSingle()).read(count) ?? 0;
  }
}
