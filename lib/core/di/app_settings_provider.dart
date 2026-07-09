import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import 'database_provider.dart';

// Plain (non-generated) provider — see timer_providers.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final appSettingsProvider = StreamProvider<AppSettingsRow>((ref) {
  return ref.watch(appDatabaseProvider).appSettingsDao.watchSettings();
});
