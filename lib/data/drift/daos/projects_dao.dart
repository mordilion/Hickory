import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/projects_table.dart';

part 'projects_dao.g.dart';

@DriftAccessor(tables: [Projects])
class ProjectsDao extends DatabaseAccessor<AppDatabase> with _$ProjectsDaoMixin {
  ProjectsDao(super.db);

  static const _uuid = Uuid();

  Stream<List<Project>> watchActiveProjects() {
    return (select(projects)
          ..where((p) => p.archived.equals(false))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Includes archived projects — reports need to resolve the name/rate of
  /// a project an old entry points to even after it's been archived.
  Stream<List<Project>> watchAllProjects() {
    return (select(projects)..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
  }

  Future<Project> createProject({
    required String name,
    required String colorHex,
    String? clientId,
    bool billable = true,
    int? hourlyRateCents,
    String? currency,
  }) async {
    final now = DateTime.now().toUtc();
    final entry = ProjectsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      colorHex: colorHex,
      clientId: Value(clientId),
      billable: Value(billable),
      hourlyRateCents: Value(hourlyRateCents),
      currency: Value(currency),
      createdAt: now,
      updatedAt: now,
    );
    await into(projects).insert(entry);
    return (select(projects)..where((p) => p.id.equals(entry.id.value))).getSingle();
  }

  Future<void> archiveProject(String id) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now().toUtc())),
    );
  }
}
