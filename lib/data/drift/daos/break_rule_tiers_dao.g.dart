// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'break_rule_tiers_dao.dart';

// ignore_for_file: type=lint
mixin _$BreakRuleTiersDaoMixin on DatabaseAccessor<AppDatabase> {
  $BreakRuleTiersTable get breakRuleTiers => attachedDatabase.breakRuleTiers;
  BreakRuleTiersDaoManager get managers => BreakRuleTiersDaoManager(this);
}

class BreakRuleTiersDaoManager {
  final _$BreakRuleTiersDaoMixin _db;
  BreakRuleTiersDaoManager(this._db);
  $$BreakRuleTiersTableTableManager get breakRuleTiers =>
      $$BreakRuleTiersTableTableManager(
        _db.attachedDatabase,
        _db.breakRuleTiers,
      );
}
