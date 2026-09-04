import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/absence_types_table.dart';

part 'absence_types_dao.g.dart';

@DriftAccessor(tables: [AbsenceTypes])
class AbsenceTypesDao extends DatabaseAccessor<AppDatabase> with _$AbsenceTypesDaoMixin {
  AbsenceTypesDao(super.db);

  static const _uuid = Uuid();

  Stream<List<AbsenceType>> watchAllTypes() {
    return (select(absenceTypes)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Future<List<AbsenceType>> getAllTypes() {
    return (select(absenceTypes)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  Future<AbsenceType> createType({
    required String deviceId,
    required String name,
    required bool paid,
    required int sortOrder,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await into(absenceTypes).insert(
      AbsenceTypesCompanion.insert(
        id: id,
        name: name,
        paid: paid,
        sortOrder: sortOrder,
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (select(absenceTypes)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Updates only the fields passed in; a null parameter leaves its column
  /// alone. Always bumps [updatedAt], because the sync log orders events by
  /// it — an edit that kept the old timestamp could lose to the row it
  /// replaced.
  Future<AbsenceType> updateType(
    String id, {
    String? name,
    bool? paid,
    int? sortOrder,
  }) async {
    await (update(absenceTypes)..where((t) => t.id.equals(id))).write(
      AbsenceTypesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        paid: paid == null ? const Value.absent() : Value(paid),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return (select(absenceTypes)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> deleteType(String id) {
    return (delete(absenceTypes)..where((t) => t.id.equals(id))).go();
  }
}
