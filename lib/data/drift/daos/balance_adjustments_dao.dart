import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/balance_adjustments_table.dart';

part 'balance_adjustments_dao.g.dart';

/// Reads and writes manual balance corrections.
///
/// There is deliberately no update: a correction is a dated fact, so
/// changing one means deleting it and recording the right one — which
/// keeps the event log a truthful account of what the user actually did.
@DriftAccessor(tables: [BalanceAdjustments])
class BalanceAdjustmentsDao extends DatabaseAccessor<AppDatabase>
    with _$BalanceAdjustmentsDaoMixin {
  BalanceAdjustmentsDao(super.db);

  static const _uuid = Uuid();

  Stream<List<BalanceAdjustment>> watchAllAdjustments() {
    return (select(balanceAdjustments)
          ..orderBy([(adjustment) => OrderingTerm.asc(adjustment.date)]))
        .watch();
  }

  Future<BalanceAdjustment> createAdjustment({
    required String deviceId,
    required DateTime date,
    required int deltaMinutes,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await into(balanceAdjustments).insert(
      BalanceAdjustmentsCompanion.insert(
        id: id,
        date: date,
        deltaMinutes: deltaMinutes,
        note: Value(note),
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (select(balanceAdjustments)..where((a) => a.id.equals(id))).getSingle();
  }

  Future<void> deleteAdjustment(String id) {
    return (delete(balanceAdjustments)..where((a) => a.id.equals(id))).go();
  }
}
