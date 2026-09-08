import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/features/reports/reports_providers.dart';
import 'package:hickory/features/reports/trend_calculations.dart';
import 'package:hickory/features/reports/trend_chart.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';
import 'package:hickory/core/di/app_settings_provider.dart';

void main() {
  final monday = DateTime(2026, 9, 7);

  Future<void> pumpChart(WidgetTester tester, List<TrendBar> bars) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendBarsProvider.overrideWithValue(AsyncValue.data(bars)),
          appSettingsProvider.overrideWith((ref) => Stream.value(appSettingsFixture())),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox(height: 300, child: TrendChart())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('gives every bar an accessible label with its figures', (tester) async {
    await pumpChart(tester, [
      (start: monday, worked: const Duration(hours: 9), target: const Duration(hours: 8)),
      (
        start: monday.add(const Duration(days: 1)),
        worked: const Duration(hours: 7),
        target: const Duration(hours: 8),
      ),
    ]);

    // The painter itself is unreadable from a test, and a hover tooltip has
    // no keyboard equivalent -- the per-bar semantics are both the
    // accessible path and the only thing a test can assert on.
    expect(find.bySemanticsLabel(RegExp(r'09:00 von 08:00')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'07:00 von 08:00')), findsOneWidget);
  });

  testWidgets('says the range is empty rather than drawing an empty box', (tester) async {
    await pumpChart(tester, const []);

    expect(find.text('Nichts erfasst im Zeitraum.'), findsOneWidget);
    // byType(CustomPaint) would also match the ones Flutter's own widgets
    // paint with, so the chart's own box is what is asserted on.
    expect(find.byKey(const ValueKey('trendBars')), findsNothing);
  });

  testWidgets('draws the bars it was given', (tester) async {
    await pumpChart(tester, [
      (start: monday, worked: const Duration(hours: 8), target: const Duration(hours: 8)),
    ]);

    expect(find.byKey(const ValueKey('trendBars')), findsOneWidget);
  });
}
