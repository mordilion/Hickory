import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/autostart_service.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/general_settings_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeAutostartService extends AutostartService {
  bool enabled = false;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

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
  late Directory localeDir;
  late _FakeAutostartService autostartService;

  setUpAll(() async {
    // GeneralSettingsScreen formats each date-format dropdown option via
    // formatDate(..., Localizations.localeOf(context).languageCode), which
    // is 'en' for this test's MaterialApp(locale: Locale('en')) -- intl
    // requires its locale data initialized before DateFormat('en', ...) works,
    // same requirement documented on formatDate itself and followed by
    // date_format_test.dart/csv_export_test.dart.
    await initializeDateFormatting('en');
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync(
      'hickory_general_settings_test_sync_',
    );
    localeDir = Directory.systemTemp.createTempSync(
      'hickory_general_settings_test_locale_',
    );
    autostartService = _FakeAutostartService();
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
    if (localeDir.existsSync()) localeDir.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
    overrides: [
      appSettingsProvider.overrideWith(
        (ref) => Stream.value(
          AppSettingsRow(
            id: 'default',
            dateFormat: 'iso',
            timeFormat: '24h',
            quickAddDurationsMinutes: '15,30,45,60',
            countPausedTimeAsBreak: false,
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
      autostartServiceProvider.overrideWithValue(autostartService),
      localeStoreProvider.overrideWith(
        (ref) async => LocaleStore(supportDirectory: localeDir),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: GeneralSettingsScreen()),
    ),
  );

  Future<String?> currentDateFormat() async {
    final row = await db.select(db.appSettings).getSingleOrNull();
    return row?.dateFormat;
  }

  testWidgets('shows the autostart switch reflecting the current state', (
    tester,
  ) async {
    autostartService.enabled = true;
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switchTile.value, isTrue);
  });

  testWidgets('toggling autostart persists via AutostartService', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(autostartService.enabled, isTrue);
    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switchTile.value, isTrue);
  });

  testWidgets('selecting a date format persists it', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    // The dropdown's option labels are formatted dates (e.g. "08/08/2026"),
    // not the enum name -- compute the exact string GeneralSettingsScreen
    // will render for DateFormatStyle.us so the tap target matches without
    // guessing at a hardcoded date. 'en' matches this test's locale, same
    // as what the widget passes via Localizations.localeOf(context).
    final usDateText = formatDate(DateTime.now(), DateFormatStyle.us, 'en');

    await tester.tap(find.byType(DropdownButtonFormField<DateFormatStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(usDateText).last);
    await tester.pumpAndSettle();

    await pumpUntilTrue(tester, () async => await currentDateFormat() == 'us');
    expect(await currentDateFormat(), 'us');
  });
}
