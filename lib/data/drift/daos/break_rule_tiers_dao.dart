import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/break_rule_tiers_table.dart';

part 'break_rule_tiers_dao.g.dart';

@DriftAccessor(tables: [BreakRuleTiers])
class BreakRuleTiersDao extends DatabaseAccessor<AppDatabase> with _$BreakRuleTiersDaoMixin {
  BreakRuleTiersDao(super.db);

  static const _uuid = Uuid();

  Stream<List<BreakRuleTier>> watchAllTiers() {
    return (select(breakRuleTiers)..orderBy([(t) => OrderingTerm.asc(t.afterMinutes)])).watch();
  }

  Future<List<BreakRuleTier>> getAllTiers() =>
      (select(breakRuleTiers)..orderBy([(t) => OrderingTerm.asc(t.afterMinutes)])).get();

  Future<BreakRuleTier> createTier({
    required String deviceId,
    required int afterMinutes,
    required int requiredBreakMinutes,
  }) async {
    final now = DateTime.now().toUtc();
    final tier = BreakRuleTiersCompanion.insert(
      id: _uuid.v4(),
      afterMinutes: afterMinutes,
      requiredBreakMinutes: requiredBreakMinutes,
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await into(breakRuleTiers).insert(tier);
    return (select(breakRuleTiers)..where((t) => t.id.equals(tier.id.value))).getSingle();
  }

  Future<void> deleteTier(String id) {
    return (delete(breakRuleTiers)..where((t) => t.id.equals(id))).go();
  }
}
