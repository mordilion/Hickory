import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/features/reports/quality_calculations.dart';
import 'package:hickory/features/reports/quality_card.dart';
import 'package:hickory/features/reports/reports_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, QualityFigures figures) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qualityFiguresProvider.overrideWithValue(AsyncValue.data(figures)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: QualityCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  QualityFigures figures({
    List<DateTime> unbooked = const [],
    List<DateTime> shortBreaks = const [],
    int failedPushCount = 0,
    Map<String, int> absences = const {},
  }) => QualityFigures(
        unbookedWorkDays: unbooked,
        shortBreakDays: shortBreaks,
        failedPushCount: failedPushCount,
        absenceDaysByTypeName: absences,
      );

  testWidgets('names each kind of gap with its count', (tester) async {
    await pumpCard(
      tester,
      figures(
        unbooked: [DateTime(2026, 9, 7)],
        shortBreaks: [DateTime(2026, 9, 8), DateTime(2026, 9, 9)],
        failedPushCount: 1,
      ),
    );

    expect(find.text('1 Arbeitstag ohne Buchung'), findsOneWidget);
    expect(find.text('2 Tage mit zu kurzer Pause'), findsOneWidget);
    expect(find.text('1 Eintrag konnte nicht übertragen werden'), findsOneWidget);
  });

  testWidgets('lists absence days per type', (tester) async {
    await pumpCard(tester, figures(absences: {'Urlaub': 3, 'Krank': 1}));

    expect(find.text('Abwesenheitstage'), findsOneWidget);
    expect(find.textContaining('Urlaub'), findsOneWidget);
    expect(find.textContaining('Krank'), findsOneWidget);
  });

  testWidgets('says everything is in order rather than showing three zeroes', (tester) async {
    await pumpCard(tester, figures());

    expect(find.text('Nichts zu beanstanden.'), findsOneWidget);
    expect(find.textContaining('ohne Buchung'), findsNothing);
  });
}
