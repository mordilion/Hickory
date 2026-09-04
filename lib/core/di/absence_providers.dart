import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import 'database_provider.dart';

// Plain (non-generated) providers -- see app_settings_provider.dart for why
// @riverpod codegen is avoided for providers whose type touches drift's
// generated classes in this codebase (rrousselGit/riverpod#4323).

final absenceTypesProvider = StreamProvider<List<AbsenceType>>((ref) {
  return ref.watch(appDatabaseProvider).absenceTypesDao.watchAllTypes();
});

/// The same types keyed by id, for the calculation and for rendering an
/// absence row's type name. Empty while the types are still loading, which
/// callers read as "this absence's type is unknown" -- an absence with an
/// unresolvable type contributes nothing rather than being guessed at.
final absenceTypesByIdProvider = Provider<Map<String, AbsenceType>>((ref) {
  final types = ref.watch(absenceTypesProvider).value ?? const <AbsenceType>[];
  return {for (final type in types) type.id: type};
});

final absencesProvider = StreamProvider<List<Absence>>((ref) {
  return ref.watch(appDatabaseProvider).absencesDao.watchAllAbsences();
});
