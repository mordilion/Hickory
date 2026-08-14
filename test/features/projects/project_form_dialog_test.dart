import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/clients/clients_providers.dart';
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

/// Waits until exactly [expectedCount] `AlertDialog`s are present, driving a
/// short real-time delay (via `runAsync`) between each `pumpAndSettle()`.
/// Needed after a dialog's submit button triggers a write that appends a
/// sync-log event (real file I/O, on top of the DB write) before calling
/// `Navigator.pop()`: `db.select(...).get()` becoming non-empty only proves
/// the DB write landed, not that the write's full async chain -- and
/// therefore the pop -- has actually resumed. A single `pumpAndSettle()`
/// immediately afterwards can run before that continuation gets a real
/// event-loop turn, leaving the dialog's route still stacked on top and
/// absorbing later taps. `pump(duration)` alone can't fix this: it only
/// advances Flutter's virtual test clock (for animations), not real time, so
/// it never gives the pending real Future a chance to progress.
Future<void> pumpUntilDialogCount(
  WidgetTester tester,
  int expectedCount, {
  int maxTries = 20,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (find.byType(AlertDialog).evaluate().length == expectedCount) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
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

  Widget makeApp({Project? project, List<Client> archivedClients = const <Client>[]}) => ProviderScope(
        overrides: [
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          activeClientsProvider.overrideWith((ref) => Stream.value(const <Client>[])),
          archivedClientsProvider.overrideWith((ref) => Stream.value(archivedClients)),
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

  testWidgets('create mode: selecting an existing client sets clientId on submit', (tester) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          activeClientsProvider.overrideWith((ref) => Stream.value([client])),
          archivedClientsProvider.overrideWith((ref) => Stream.value(const <Client>[])),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showProjectFormDialog(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Inc').last);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final projects = await db.select(db.projects).get();
    expect(projects.single.clientId, client.id);
  });

  testWidgets('create mode: creating a client inline via the picker selects it, and it stays selected', (
    tester,
  ) async {
    // activeClientsProvider is driven by a StreamController the test controls
    // directly, rather than makeApp()'s static empty-stream override or a
    // real live drift query stream. A static override can never reflect the
    // client created by the nested dialog (it would make the dropdown's
    // post-creation state unprovable), while a real drift stream races pump
    // timing (see projects_editor_test.dart's Global Constraints comment).
    // Driving the emission manually lets the test deterministically exercise
    // the exact sequence that matters: the client is created and
    // selectedClientId is updated *before* the clients list catches up --
    // which is the realistic ordering, since the query stream has to
    // re-fetch after the write completes -- and only then does the list
    // update arrive. This proves the dropdown correctly displays the
    // newly-created client once the list catches up. (In this scenario
    // selectedClientId itself changes -- null to created.id -- so on this
    // Flutter version DropdownButtonFormField's own didUpdateWidget would
    // also re-sync from initialValue on its own, independent of the
    // ValueKey((selectedClientId, clientPickerGeneration)) fix above; see
    // that key's doc comment for the cancel-flow case where only the
    // ValueKey's generation counter makes the difference. Either way, this
    // test asserts the end-user-visible outcome, not which mechanism
    // produces it.)
    final clientsController = StreamController<List<Client>>();
    addTearDown(clientsController.close);
    clientsController.add(const <Client>[]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          activeClientsProvider.overrideWith((ref) => clientsController.stream),
          archivedClientsProvider.overrideWith((ref) => Stream.value(const <Client>[])),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showProjectFormDialog(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New client…').last);
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Acme Inc');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create').last);
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.clients).get()).isNotEmpty);
    });
    await tester.pumpAndSettle();
    // The client row existing doesn't mean the nested dialog has actually
    // closed yet -- see pumpUntilDialogCount's doc comment. Wait for it to
    // close before touching the project dialog underneath it.
    await pumpUntilDialogCount(tester, 1);

    final client = (await db.select(db.clients).get()).single;

    // Only now -- after the client row exists and the nested dialog has
    // already resolved (setDialogState already ran with the stale, empty
    // clients list) -- do we let activeClientsProvider catch up. This is the
    // adversarial ordering the dropdown must handle correctly: selectedClientId
    // changes first, and the clients list arrives later.
    clientsController.add([client]);
    await tester.pumpAndSettle();

    // The dropdown must show the freshly-created client without re-opening
    // it or requiring the dialog to be reopened. (In this scenario
    // selectedClientId changes, so DropdownButtonFormField's own
    // didUpdateWidget would also re-sync from initialValue on its own here,
    // independent of the ValueKey fix in Step 3 -- the end-user-visible
    // behavior is what this test asserts, not which mechanism produces it.)
    expect(find.text('Acme Inc'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Create').first);
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });
    // The project row existing only proves the DB write landed, not that
    // SyncedWrites.createProject's trailing sync-log file write (real I/O,
    // appended after the row insert) has finished -- the submit button only
    // calls Navigator.pop() once that whole awaited chain resolves, so
    // waiting for the dialog to actually close is a real, observable signal
    // that the write (DB row *and* sync-log file) is done, rather than a
    // fixed guess at how long it might take. Needed so the write isn't still
    // in flight when tearDown() deletes syncRoot out from under it -- which
    // otherwise surfaces as a stray PathNotFoundException "after the test
    // had already completed", misattributed to whatever test happens to run
    // next. (This used to also be a workaround for a TextEditingController-
    // disposal race in this dialog's own cleanup under heavier pumping;
    // project_form_dialog.dart now disposes its controllers via
    // State.dispose() instead of showDialog's `.whenComplete()`, so that
    // race no longer applies here.)
    await pumpUntilDialogCount(tester, 0);

    final project = (await db.select(db.projects).get()).single;
    expect(project.clientId, client.id);
  });

  testWidgets(
    'create mode: cancelling "+ New client..." reverts the picker display to "No client"',
    (tester) async {
      // DropdownButtonFormField's own FormFieldState applies the sentinel
      // value to its displayed selection the moment onChanged fires --
      // before the nested client dialog even opens. If the nested dialog is
      // then cancelled, selectedClientId itself never changes, so a plain
      // rebuild alone isn't enough to resync the display (see the
      // clientPickerGeneration/ValueKey doc comment in
      // project_form_dialog.dart): the fix under test must force a fresh
      // DropdownButtonFormField State so its displayed value reverts to the
      // real, unchanged selectedClientId (null / "No client") instead of
      // staying stuck showing "+ New client...".
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Website Relaunch');
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ New client…').last);
      await tester.pumpAndSettle();

      expect(find.text('New client'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      // Nested dialog is gone; no client was created.
      expect(find.text('New client'), findsNothing);
      expect(await db.select(db.clients).get(), isEmpty);

      // The picker must revert to displaying "No client" rather than
      // remaining stuck on "+ New client...".
      expect(find.text('No client'), findsOneWidget);
      expect(find.text('+ New client…'), findsNothing);
    },
  );

  testWidgets('create mode: leaving the client picker on "No client" submits a null clientId', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Website Relaunch');

    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await tester.pump();
      await pumpUntilTrue(tester, () async => (await db.select(db.projects).get()).isNotEmpty);
    });

    final projects = await db.select(db.projects).get();
    expect(projects.single.clientId, isNull);
  });

  testWidgets('edit mode: pre-selects the project\'s existing client', (tester) async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    final project = await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#5B8DEF',
      clientId: client.id,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          activeClientsProvider.overrideWith((ref) => Stream.value([client])),
          archivedClientsProvider.overrideWith((ref) => Stream.value(const <Client>[])),
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Inc'), findsOneWidget);
  });

  testWidgets(
    'edit mode: a project whose client was archived still shows and re-saves that client',
    (tester) async {
      // Regression test for the picker silently disagreeing with the DB: the
      // project's clientId points at a client that's since been archived, so
      // it's absent from activeClientsProvider. Before the fix, the picker
      // fell back to displaying "No client" while selectedClientId still
      // held the archived id -- saving an unrelated change would silently
      // write that stale-looking-but-still-correct id back, with the UI
      // never telling the user which client (if any) was really assigned.
      final client = await db.clientsDao.createClient(name: 'Acme Inc');
      await db.clientsDao.archiveClient(client.id);
      final project = await db.projectsDao.createProject(
        name: 'Website Relaunch',
        colorHex: '#5B8DEF',
        clientId: client.id,
      );
      await tester.pumpWidget(makeApp(project: project, archivedClients: [client]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The archived client must be visibly shown -- not "No client" -- and
      // labelled distinctly so the user understands it's archived.
      expect(find.text('Acme Inc (archived)'), findsOneWidget);
      expect(find.text('No client'), findsNothing);

      // Submit without touching the picker: the project's clientId must
      // still round-trip to the archived client, proving the display and
      // the persisted value now agree.
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await tester.pump();
        await pumpUntilTrue(tester, () async {
          final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
          return row.clientId == client.id;
        });
      });

      final row = await (db.select(db.projects)..where((p) => p.id.equals(project.id))).getSingle();
      expect(row.clientId, client.id);
    },
  );
}
