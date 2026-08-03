import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/format/quick_add_durations.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/quick_add_durations_editor.dart';
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

// A plain one-shot select, never db.appSettingsDao.watchSettings() (a live
// drift .watch() stream): even called just for a single value via .first,
// a watched stream still registers with drift's StreamQueryStore, and
// repeatedly subscribing/cancelling one inside a testWidgets polling loop
// hit a 10-minute hang in this codebase's flutter_test/drift combination --
// the same family of issue as the real-Riverpod-StreamProvider bug fixed in
// Task 4 (flutter/flutter#144472), but here triggered by direct DAO watch
// calls rather than a mounted widget.
Future<String?> _currentQuickAddDurationsMinutes(AppDatabase db) async {
  final row = await db.select(db.appSettings).getSingleOrNull();
  return row?.quickAddDurationsMinutes;
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_quick_add_settings_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp({List<int> durations = const [15, 30, 45, 60]}) => ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: formatQuickAddDurations(durations),
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
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
          home: const Scaffold(body: QuickAddDurationsEditor()),
        ),
      );

  testWidgets('shows the default duration chips', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
  });

  testWidgets(
    'removing a chip persists the updated list and re-renders without it',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.widgetWithText(Chip, '30 min'),
        matching: find.byIcon(Icons.cancel),
      ));

      await pumpUntilTrue(
        tester,
        () async => await _currentQuickAddDurationsMinutes(db) == '15,45,60',
      );

      final quickAddDurationsMinutes = await _currentQuickAddDurationsMinutes(db);
      expect(quickAddDurationsMinutes, '15,45,60');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        makeApp(durations: parseQuickAddDurations(quickAddDurationsMinutes)),
      );
      await tester.pumpAndSettle();

      expect(find.text('30 min'), findsNothing);
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
    },
  );

  testWidgets(
    'adding a duration persists the updated list and re-renders with it',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '90');
      await tester.tap(find.text('Save'));
      await tester.pump();

      await pumpUntilTrue(
        tester,
        () async => await _currentQuickAddDurationsMinutes(db) == '15,30,45,60,90',
      );

      final quickAddDurationsMinutes = await _currentQuickAddDurationsMinutes(db);
      expect(quickAddDurationsMinutes, '15,30,45,60,90');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        makeApp(durations: parseQuickAddDurations(quickAddDurationsMinutes)),
      );
      await tester.pumpAndSettle();

      expect(find.text('90 min'), findsOneWidget);
    },
  );
}
