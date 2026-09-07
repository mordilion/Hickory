// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'balance_adjustments_dao.dart';

// ignore_for_file: type=lint
mixin _$BalanceAdjustmentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $BalanceAdjustmentsTable get balanceAdjustments =>
      attachedDatabase.balanceAdjustments;
  BalanceAdjustmentsDaoManager get managers =>
      BalanceAdjustmentsDaoManager(this);
}

class BalanceAdjustmentsDaoManager {
  final _$BalanceAdjustmentsDaoMixin _db;
  BalanceAdjustmentsDaoManager(this._db);
  $$BalanceAdjustmentsTableTableManager get balanceAdjustments =>
      $$BalanceAdjustmentsTableTableManager(
        _db.attachedDatabase,
        _db.balanceAdjustments,
      );
}
