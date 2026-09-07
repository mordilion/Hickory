import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import 'database_provider.dart';

/// Every manual balance correction, ascending by date.
///
/// A plain provider rather than `@riverpod`, like every other provider
/// that touches a drift type: mixing riverpod_generator with drift's
/// generator in one build_runner pass trips rrousselGit/riverpod#4323.
final balanceAdjustmentsProvider = StreamProvider<List<BalanceAdjustment>>((ref) {
  return ref.watch(appDatabaseProvider).balanceAdjustmentsDao.watchAllAdjustments();
});
