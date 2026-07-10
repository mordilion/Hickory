import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/features/settings/language_dropdown.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('language_dropdown_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  // Mirrors HickoryApp's locale wiring (locale follows the controller, so
  // the "switch re-renders immediately" behavior is actually under test);
  // starts at German because nothing is stored and resolveLocale of the
  // test binding's en_US would give English — so pin the platform locale.
  Widget makeApp() => ProviderScope(
        overrides: [
          localeStoreProvider.overrideWith(
            (ref) async => LocaleStore(supportDirectory: tempDir),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(localeControllerProvider).value;
            return MaterialApp(
              locale: locale ?? const Locale('de'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: LanguageDropdown()),
            );
          },
        ),
      );

  // Real dart:io futures cannot finish inside the fake-async test zone on
  // their own: their completions land on the fake microtask queue, which
  // only pump flushes. Each runAsync window lets an IO event arrive; each
  // pump flushes the queue so async chains advance one await at a time.
  Future<void> pumpRealIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }

  testWidgets('shows the system-default option with the resolved language', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.text('Sprache'), findsOneWidget);
    // Test binding's platform locale is en_US → resolved display name English.
    expect(find.textContaining('Systemstandard'), findsOneWidget);
  });

  testWidgets('selecting a language persists it via the controller', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    // Let the controller's initial build (a real file read) finish before
    // interacting — otherwise the still-pending build would complete after
    // setLocale and clobber the selection with its stale null result.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LanguageDropdown)),
      listen: false,
    );
    for (var i = 0;
        i < 50 && container.read(localeControllerProvider).isLoading;
        i++) {
      await pumpRealIo(tester);
    }

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français').last);
    await tester.pumpAndSettle();

    // Persisted: drive the controller's disk write to completion, then read
    // the stored preference back (both are real IO, hence the interleave).
    String? stored;
    for (var i = 0; i < 50 && stored != 'fr'; i++) {
      await pumpRealIo(tester);
      stored = await tester.runAsync<String?>(
        () => LocaleStore(supportDirectory: tempDir).read(),
      );
    }
    expect(stored, 'fr');
    // AND immediately re-rendered: the dropdown label is now French.
    expect(find.text('Langue'), findsOneWidget);
  });
}
