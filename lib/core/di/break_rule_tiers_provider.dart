import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import 'database_provider.dart';

// Plain (non-generated) provider -- see app_settings_provider.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final breakRuleTiersProvider = StreamProvider<List<BreakRuleTier>>((ref) {
  return ref.watch(appDatabaseProvider).breakRuleTiersDao.watchAllTiers();
});
