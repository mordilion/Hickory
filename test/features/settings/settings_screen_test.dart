import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/update_providers.dart';
import 'package:hickory/features/settings/settings_navigation.dart';
import 'package:hickory/features/settings/settings_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

/// An explicit container (rather than a plain ProviderScope) so a test can
/// flip [openUpdatePageRequestedProvider] after the screen is mounted --
/// which is what AppShell does in the real app, and the only way the
/// screen's listener fires at all.
ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      // The update page watches this during build; the real provider reads
      // PackageInfo.fromPlatform() over a platform channel.
      currentAppVersionProvider.overrideWith((ref) async => '1.1.0'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const SettingsScreen(),
  ),
);

void main() {
  testWidgets('shows the category list as its initial route', (tester) async {
    await tester.pumpWidget(_app(_container()));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
  });

  testWidgets('pushes the update page when asked to, and clears the request', (
    tester,
  ) async {
    final container = _container();
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(openUpdatePageRequestedProvider.notifier).state = true;
    await tester.pumpAndSettle();

    // The pushed route is opaque, so the category list underneath it is
    // offstage and skipped by the default finder.
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('General'), findsNothing);
    // Cleared, or returning to this tab later would push the page again.
    expect(container.read(openUpdatePageRequestedProvider), isFalse);
  });
}
