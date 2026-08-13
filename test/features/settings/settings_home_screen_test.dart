import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/autostart_service.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/di/update_providers.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/clients/clients_providers.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/settings/clients_settings_screen.dart';
import 'package:hickory/features/settings/general_settings_screen.dart';
import 'package:hickory/features/settings/projects_settings_screen.dart';
import 'package:hickory/features/settings/reset_settings_screen.dart';
import 'package:hickory/features/settings/settings_screen.dart';
import 'package:hickory/features/settings/time_tracking_settings_screen.dart';
import 'package:hickory/features/settings/update_settings_screen.dart';
import 'package:hickory/features/shell/nav_shell.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeAutostartService extends AutostartService {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool value) async {}
}

void main() {
  late Directory localeDir;

  setUpAll(() async {
    // Navigating into General renders GeneralSettingsScreen's date-format
    // dropdown, which calls formatDate(..., 'en') while building its
    // (unopened) options list -- same intl initialization requirement as
    // general_settings_screen_test.dart.
    await initializeDateFormatting('en');
  });

  setUp(
    () => localeDir = Directory.systemTemp.createTempSync(
      'settings_home_screen_test_',
    ),
  );
  tearDown(() => localeDir.deleteSync(recursive: true));

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
      breakRuleTiersProvider.overrideWith((ref) => Stream.value(const [])),
      activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
      archivedProjectsProvider.overrideWith((ref) => Stream.value(const [])),
      activeClientsProvider.overrideWith((ref) => Stream.value(const [])),
      archivedClientsProvider.overrideWith((ref) => Stream.value(const [])),
      autostartServiceProvider.overrideWithValue(_FakeAutostartService()),
      localeStoreProvider.overrideWith(
        (ref) async => LocaleStore(supportDirectory: localeDir),
      ),
      currentAppVersionProvider.overrideWith((ref) async => '1.1.0'),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: NavShell(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          NavigationDestination(icon: Icon(Icons.circle), label: 'Other'),
        ],
        children: const [
          SettingsScreen(),
          Center(child: Text('Other tab')),
        ],
      ),
    ),
  );

  testWidgets('shows all category rows', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Time tracking'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    if (Platform.isMacOS || Platform.isWindows) {
      expect(find.text('Updates'), findsOneWidget);
    }
  });

  testWidgets(
    'tapping each category row navigates to that category\'s screen, back returns to the list',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      Future<void> tapAndVerify(String rowText, Type screenType) async {
        await tester.tap(find.text(rowText));
        await tester.pumpAndSettle();
        expect(find.byType(screenType), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }

      await tapAndVerify('General', GeneralSettingsScreen);
      await tapAndVerify('Time tracking', TimeTrackingSettingsScreen);
      await tapAndVerify('Projects', ProjectsSettingsScreen);
      await tapAndVerify('Clients', ClientsSettingsScreen);
      if (Platform.isMacOS || Platform.isWindows) {
        await tapAndVerify('Updates', UpdateSettingsScreen);
      }
      await tapAndVerify('Reset', ResetSettingsScreen);
    },
  );

  testWidgets('the bottom nav bar stays visible while browsing a sub-page', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(GeneralSettingsScreen), findsOneWidget);
  });

  testWidgets('switching tabs and back preserves the open sub-page', (
    tester,
  ) async {
    // IndexedStack keeps every tab's widget tree mounted (via Visibility,
    // not Offstage), so a bare find.byType would pass even without ever
    // switching tabs -- assert on NavigationBar.selectedIndex too, so a
    // regression that stops preserving state is actually caught.
    NavigationBar navBar() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.byType(GeneralSettingsScreen), findsOneWidget);

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(navBar().selectedIndex, 1);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(navBar().selectedIndex, 0);
    expect(find.byType(GeneralSettingsScreen), findsOneWidget);
  });
}
