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

  Future<void> unarchiveProject(String id) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(archived: const Value(false), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  /// Partial update: every parameter left as [Value.absent] keeps that
  /// column's current value -- same shape as [TimeEntriesDao.updateEntry].
  Future<void> updateProject(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String> colorHex = const Value.absent(),
    Value<String?> clientId = const Value.absent(),
    Value<bool> billable = const Value.absent(),
    Value<int?> hourlyRateCents = const Value.absent(),
    Value<String?> currency = const Value.absent(),
  }) {
    return (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: name,
        colorHex: colorHex,
        clientId: clientId,
        billable: billable,
        hourlyRateCents: hourlyRateCents,
        currency: currency,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Same shape as [watchActiveProjects] but the inverse filter -- backs the
  /// Settings project manager's "Archived projects" section.
  Stream<List<Project>> watchArchivedProjects() {
    return (select(projects)
          ..where((p) => p.archived.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  Future<void> deleteProject(String id) => (delete(projects)..where((p) => p.id.equals(id))).go();

  /// Checks whether any project references [clientId] -- including archived
  /// projects, not just active ones -- since an archived project still
  /// blocks deleting the client it belongs to.
  Future<bool> hasProjectsForClient(String clientId) async {
    final row = await (select(projects)..where((p) => p.clientId.equals(clientId))..limit(1)).getSingleOrNull();
    return row != null;
  }
}
