import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';

// Plain (non-generated) provider — see timer_providers.dart for why: a
// generated @riverpod provider returning a drift row type can trip
// riverpod_generator's InvalidTypeException (rrousselGit/riverpod#4323).

final activeClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(appDatabaseProvider).clientsDao.watchActiveClients();
});

final archivedClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(appDatabaseProvider).clientsDao.watchArchivedClients();
});

/// Every client, archived included — reporting attributes revenue to the
/// client a project carried at the time, which may since have been
/// archived.
final allClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(appDatabaseProvider).clientsDao.watchAllClients();
});
