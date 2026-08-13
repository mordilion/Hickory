import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/clients/client_form_dialog.dart';
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_client_form_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp({Client? client}) => ProviderScope(
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
                  onPressed: () => showClientFormDialog(context, ref, client: client),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('create mode: submitting with a name creates a client', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Acme Inc');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.clients).get()).isNotEmpty);
    });

    final clients = await db.select(db.clients).get();
    expect(clients, hasLength(1));
    expect(clients.single.name, 'Acme Inc');
  });

  testWidgets('create mode: submitting with an empty name does not create a client', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    expect(await db.select(db.clients).get(), isEmpty);
  });

  testWidgets('edit mode: field is pre-filled from the passed client', (tester) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    await tester.pumpWidget(makeApp(client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit client'), findsOneWidget);
    expect(find.text('Acme Inc'), findsOneWidget);
  });

  testWidgets('edit mode: submitting updates the existing client rather than creating a new one', (
    tester,
  ) async {
    final client = await db.clientsDao.createClient(name: 'Old Name');
    await tester.pumpWidget(makeApp(client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Name');

    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await pumpUntilTrue(tester, () async {
        final rows = await db.select(db.clients).get();
        return rows.length == 1 && rows.single.name == 'New Name';
      });
    });

    final clients = await db.select(db.clients).get();
    expect(clients, hasLength(1));
    expect(clients.single.name, 'New Name');
  });
}
