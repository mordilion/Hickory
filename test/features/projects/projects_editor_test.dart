import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/projects/projects_editor.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

Future<void> pumpUntilTrue(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_projects_editor_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // activeProjectsProvider/archivedProjectsProvider are overridden with
  // static streams rather than derived from a real drift database -- see
  // this plan's Global Constraints (avoids a known flutter_test false
  // positive with live drift QueryStreams). Tests that need to see an
  // updated list after a write remount with a fresh override, same
  // technique as quick_add_bar_test.dart.
  Widget makeApp({
    List<Project> active = const [],
    List<Project> archived = const [],
  }) => ProviderScope(
        overrides: [
          activeProjectsProvider.overrideWith((ref) => Stream.value(active)),
          archivedProjectsProvider.overrideWith((ref) => Stream.value(archived)),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: SingleChildScrollView(child: ProjectsEditor())),
        ),
      );

  Future<Project> seedProject({bool archived = false}) async {
    final project = await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF');
    if (archived) await db.projectsDao.archiveProject(project.id);
    return (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
  }

  testWidgets('renders active projects with edit and archive actions', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    expect(find.text('Website Relaunch'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
  });

  testWidgets('archived section is hidden when there are no archived projects', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Archived projects'), findsNothing);
  });

  testWidgets('tapping archive marks the project archived in the database', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.archive_outlined));
      await pumpUntilTrue(tester, () async {
        final row =
            await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
        return row.archived;
      });
    });

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isTrue);
  });

  testWidgets('archived projects render under the collapsible section with a reactivate action', (
    tester,
  ) async {
    final project = await seedProject(archived: true);
    await tester.pumpWidget(makeApp(archived: [project]));
    await tester.pumpAndSettle();

    expect(find.text('Archived projects'), findsOneWidget);
    await tester.tap(find.text('Archived projects'));
    await tester.pumpAndSettle();

    expect(find.text('Website Relaunch'), findsOneWidget);
    expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
  });

  testWidgets('tapping reactivate clears the archived flag in the database', (tester) async {
    final project = await seedProject(archived: true);
    await tester.pumpWidget(makeApp(archived: [project]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived projects'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.unarchive_outlined));
      await pumpUntilTrue(tester, () async {
        final row =
            await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
        return !row.archived;
      });
    });

    final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
    expect(row.archived, isFalse);
  });

  testWidgets('tapping "Add project" opens the create dialog', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
  });

  testWidgets('tapping edit opens the edit dialog pre-filled with the project name', (tester) async {
    final project = await seedProject();
    await tester.pumpWidget(makeApp(active: [project]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Edit project'), findsOneWidget);
    expect(find.text('Website Relaunch'), findsWidgets);
  });
}
