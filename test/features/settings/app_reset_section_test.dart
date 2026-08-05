import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/reset_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/reset/app_reset_service.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/features/settings/app_reset_section.dart';
import 'package:hickory/l10n/app_localizations.dart';

class _NoopJiraCredentialsStore implements JiraCredentialsStore {
  @override
  Future<JiraCredentials?> read() async => null;
  @override
  Future<void> write(JiraCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

class _NoopPersonioCredentialsStore implements PersonioCredentialsStore {
  @override
  Future<PersonioCredentials?> read() async => null;
  @override
  Future<void> write(PersonioCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

Future<void> pumpUntilTrue(
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) return;
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late bool resetCalled;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('hickory_app_reset_section_test_');
    resetCalled = false;
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appResetServiceProvider.overrideWith(
            (ref) async => AppResetService(
              db: db,
              deviceId: 'device-1',
              effectiveSyncRoot: Directory('${tempDir.path}/effective')..createSync(),
              defaultSyncRoot: Directory('${tempDir.path}/default')..createSync(),
              clearSyncFolder: () async => resetCalled = true,
              jiraCredentialsStore: _NoopJiraCredentialsStore(),
              personioCredentialsStore: _NoopPersonioCredentialsStore(),
              localeStore: LocaleStore(supportDirectory: Directory('${tempDir.path}/locale')..createSync()),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AppResetSection()),
        ),
      );

  testWidgets('shows the reset button', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Reset everything'), findsOneWidget);
  });

  testWidgets('tapping the button opens a confirmation dialog explaining the consequences', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();

    expect(find.text('Really reset everything?'), findsOneWidget);
    expect(resetCalled, isFalse);
  });

  testWidgets('cancelling the confirmation performs no reset', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(resetCalled, isFalse);
  });

  testWidgets('confirming runs the reset and shows a success message', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Yes, reset everything'));
      await pumpUntilTrue(() async {
        await tester.pump();
        return resetCalled;
      });
      await pumpUntilTrue(() async {
        await tester.pump();
        return find.text('The app has been reset.').evaluate().isNotEmpty;
      });
    });
  });
}
