import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/projects/project_form_dialog.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_project_form_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp({Project? project}) => ProviderScope(
        overrides: [
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
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showProjectFormDialog(context, ref, project: project),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('create mode: submitting with a name creates a project', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final projects = await db.select(db.projects).get();
    expect(projects, hasLength(1));
    expect(projects.single.name, 'Website Relaunch');
    expect(projects.single.billable, isTrue);
  });

  testWidgets('create mode: submitting with an empty name does not create a project', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    expect(await db.select(db.projects).get(), isEmpty);
  });

  testWidgets('edit mode: fields are pre-filled from the passed project', (tester) async {
    final project = await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#EF5B5B',
      hourlyRateCents: 9500,
      currency: 'EUR',
    );
    await tester.pumpWidget(makeApp(project: project));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit project'), findsOneWidget);
    expect(find.text('Website Relaunch'), findsOneWidget);
    expect(find.text('95.00'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
  });

  testWidgets('edit mode: submitting updates the existing project rather than creating a new one', (
    tester,
  ) async {
    final project = await db.projectsDao.createProject(name: 'Old Name', colorHex: '#5B8DEF');
    await tester.pumpWidget(makeApp(project: project));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Name');

    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await pumpUntilTrue(tester, () async {
        final rows = await db.select(db.projects).get();
        return rows.length == 1 && rows.single.name == 'New Name';
      });
    });

    final projects = await db.select(db.projects).get();
    expect(projects, hasLength(1));
    expect(projects.single.name, 'New Name');
  });

  testWidgets('entering a non-numeric hourly rate shows an inline error and does not submit', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.enterText(find.byType(TextField).at(1), 'abc');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    expect(find.text('Please enter a valid amount.'), findsWidgets);
    expect(await db.select(db.projects).get(), isEmpty);
  });

  testWidgets('entering a negative hourly rate shows an inline error and does not submit', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.enterText(find.byType(TextField).at(1), '-50');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsOneWidget);
    expect(find.text('Please enter a valid amount.'), findsWidgets);
    expect(await db.select(db.projects).get(), isEmpty);
  });
}
