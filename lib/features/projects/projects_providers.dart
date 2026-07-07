import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';

// Plain (non-generated) provider — see timer_providers.dart for why: a
// generated @riverpod provider returning a drift row type can trip
// riverpod_generator's InvalidTypeException (rrousselGit/riverpod#4323).

final activeProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(appDatabaseProvider).projectsDao.watchActiveProjects();
});
