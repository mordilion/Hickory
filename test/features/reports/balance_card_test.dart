import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/balance_card.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

// BalanceCard is pure presentation over appSettingsProvider and
// allEntriesProvider, so both are overridden with frozen fixture streams
// here rather than routed through a real appDatabaseProvider: a widget that
// ref.watch()es a genuine drift stream gets torn down by flutter_test's
// automatic end-of-test widget reset before drift's own debounced
// stream-close timer fires, which deadlocks tearDown's `db.close()` waiting
// on that timer (see balance_rule_editor_test.dart for the same trap with
// SyncedWrites' file I/O).
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    AppSettingsRow? settings,
    List<TimeEntry> entries = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(settings ?? appSettingsFixture()),
          ),
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        ],
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BalanceCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('formatSignedDuration always carries an explicit sign', () {
    expect(formatSignedDuration(const Duration(minutes: 90)), '+1:30');
    expect(formatSignedDuration(const Duration(minutes: -90)), '-1:30');
    expect(formatSignedDuration(Duration.zero), '+0:00');
  });

  testWidgets('without any target it points at the settings instead of a number', (tester) async {
    await pumpCard(tester);
    expect(find.text('Noch keine Soll-Arbeitszeit hinterlegt.'), findsOneWidget);
  });

  testWidgets('with a target it shows the overall balance', (tester) async {
    await pumpCard(tester, settings: appSettingsFixture(targetMinutesMonday: 480));
    expect(find.text('Saldo gesamt'), findsOneWidget);
    expect(find.text('+0:00'), findsOneWidget);
  });
}
