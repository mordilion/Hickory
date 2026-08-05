import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:matcher/matcher.dart' as matcher;

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('updateProject updates only the fields passed', () async {
    final project = await db.projectsDao.createProject(
      name: 'Old Name',
      colorHex: '#5B8DEF',
      hourlyRateCents: 5000,
      currency: 'USD',
    );

    await db.projectsDao.updateProject(project.id, name: const Value('New Name'));

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.name, 'New Name');
    expect(updated.colorHex, '#5B8DEF');
    expect(updated.billable, isTrue);
    expect(updated.hourlyRateCents, 5000);
    expect(updated.currency, 'USD');
  });

  test('updateProject can set hourlyRateCents and currency to null', () async {
    final project = await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#5B8DEF',
      hourlyRateCents: 5000,
      currency: 'USD',
    );

    await db.projectsDao.updateProject(
      project.id,
      hourlyRateCents: const Value(null),
      currency: const Value(null),
    );

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.hourlyRateCents, matcher.isNull);
    expect(updated.currency, matcher.isNull);
  });

  test('archiveProject sets archived to true', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');

    await db.projectsDao.archiveProject(project.id);

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.archived, isTrue);
  });

  test('unarchiveProject sets archived back to false', () async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    await db.projectsDao.archiveProject(project.id);

    await db.projectsDao.unarchiveProject(project.id);

    final updated =
        await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(updated.archived, isFalse);
  });

  test('watchArchivedProjects only returns archived projects, ordered by name', () async {
    final active = await db.projectsDao.createProject(name: 'Active Project', colorHex: '#5B8DEF');
    final archivedB = await db.projectsDao.createProject(name: 'Zeta', colorHex: '#EF5B5B');
    final archivedA = await db.projectsDao.createProject(name: 'Alpha', colorHex: '#5BEF8D');
    await db.projectsDao.archiveProject(archivedB.id);
    await db.projectsDao.archiveProject(archivedA.id);

    final archived = await db.projectsDao.watchArchivedProjects().first;

    expect(archived.map((p) => p.name), ['Alpha', 'Zeta']);
    expect(archived.any((p) => p.id == active.id), isFalse);
  });
}
