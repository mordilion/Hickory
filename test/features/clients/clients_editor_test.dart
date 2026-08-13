import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/clients/clients_editor.dart';
import 'package:hickory/features/clients/clients_providers.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_clients_editor_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // Same static-stream-override technique as projects_editor_test.dart --
  // avoids a known flutter_test false positive with live drift QueryStreams.
  Widget makeApp({
    List<Client> active = const [],
    List<Client> archived = const [],
  }) => ProviderScope(
        overrides: [
          activeClientsProvider.overrideWith((ref) => Stream.value(active)),
          archivedClientsProvider.overrideWith((ref) => Stream.value(archived)),
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
          home: const Scaffold(body: SingleChildScrollView(child: ClientsEditor())),
        ),
      );

  Future<Client> seedClient({bool archived = false}) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    if (archived) await db.clientsDao.archiveClient(client.id);
    return (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
  }

  testWidgets('renders active clients with edit, archive, and delete actions', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    expect(find.text('Acme Inc'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('archived section is hidden when there are no archived clients', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Archived clients'), findsNothing);
  });

  testWidgets('tapping archive marks the client archived in the database', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.archive_outlined));
      await pumpUntilTrue(tester, () async {
        final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
        return row.archived;
      });
    });

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isTrue);
  });

  testWidgets('archived clients render under the collapsible section with a reactivate action', (
    tester,
  ) async {
    final client = await seedClient(archived: true);
    await tester.pumpWidget(makeApp(archived: [client]));
    await tester.pumpAndSettle();

    expect(find.text('Archived clients'), findsOneWidget);
    await tester.tap(find.text('Archived clients'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Inc'), findsOneWidget);
    expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
  });

  testWidgets('tapping reactivate clears the archived flag in the database', (tester) async {
    final client = await seedClient(archived: true);
    await tester.pumpWidget(makeApp(archived: [client]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived clients'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.unarchive_outlined));
      await pumpUntilTrue(tester, () async {
        final row =
            await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
        return !row.archived;
      });
    });

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isFalse);
  });

  testWidgets('tapping "Add client" opens the create dialog', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add client'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
  });

  testWidgets('tapping edit opens the edit dialog pre-filled with the client name', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Edit client'), findsOneWidget);
    expect(find.text('Acme Inc'), findsWidgets);
  });

  testWidgets('confirming delete removes a client with no projects from the database', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete client?'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntilTrue(tester, () async {
        final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
        return remaining.isEmpty;
      });
    });

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, isEmpty);
  });

  testWidgets('cancelling the delete confirmation leaves the client untouched', (tester) async {
    final client = await seedClient();
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, hasLength(1));
  });

  testWidgets('attempting to delete a client with projects shows the blocked-delete error', (
    tester,
  ) async {
    final client = await seedClient();
    await db.projectsDao.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF', clientId: client.id);
    await tester.pumpWidget(makeApp(active: [client]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntilTrue(tester, () async {
        await tester.pump();
        return find.text("This client still has projects assigned and can't be deleted.").evaluate().isNotEmpty;
      });
    });

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, hasLength(1));
  });
}
