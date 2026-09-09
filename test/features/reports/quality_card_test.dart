import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/features/reports/quality_calculations.dart';
import 'package:hickory/features/reports/quality_card.dart';
import 'package:hickory/features/reports/reports_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, QualityFigures figures) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qualityFiguresProvider.overrideWithValue(AsyncValue.data(figures)),
          // The dates are rendered in the configured format; left live
          // this watches a real drift stream from inside a widget.
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(appSettingsFixture(dateFormat: 'de')),
          ),
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

  group('the days behind a count', () {
    testWidgets('names them when the line is tapped', (tester) async {
      await pumpCard(
        tester,
        figures(unbooked: [DateTime(2026, 9, 7), DateTime(2026, 9, 9)]),
      );

      // A count alone tells the user something is wrong but not where to
      // look, and the days are already in hand.
      expect(find.text('07.09.2026'), findsNothing);

      await tester.tap(find.text('2 Arbeitstage ohne Buchung'));
      await tester.pumpAndSettle();

      expect(find.text('07.09.2026'), findsOneWidget);
      expect(find.text('09.09.2026'), findsOneWidget);
    });

    testWidgets('folds them away again on a second tap', (tester) async {
      await pumpCard(tester, figures(unbooked: [DateTime(2026, 9, 7)]));

      await tester.tap(find.text('1 Arbeitstag ohne Buchung'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Arbeitstag ohne Buchung'));
      await tester.pumpAndSettle();

      expect(find.text('07.09.2026'), findsNothing);
    });

    testWidgets('opens the days with too short a break as well', (tester) async {
      await pumpCard(tester, figures(shortBreaks: [DateTime(2026, 9, 8)]));

      await tester.tap(find.text('1 Tag mit zu kurzer Pause'));
      await tester.pumpAndSettle();

      expect(find.text('08.09.2026'), findsOneWidget);
    });

    testWidgets('opens each list on its own', (tester) async {
      await pumpCard(
        tester,
        figures(unbooked: [DateTime(2026, 9, 7)], shortBreaks: [DateTime(2026, 9, 8)]),
      );

      await tester.tap(find.text('1 Arbeitstag ohne Buchung'));
      await tester.pumpAndSettle();

      expect(find.text('07.09.2026'), findsOneWidget);
      expect(find.text('08.09.2026'), findsNothing);
    });

    testWidgets('leaves a line with no days behind it inert', (tester) async {
      await pumpCard(tester, figures(failedPushCount: 2));

      // The failed pushes are listed per entry on the Sync tab, so this
      // line has no days of its own to reveal and must not look as if it
      // did.
      final line = find.ancestor(
        of: find.text('2 Einträge konnten nicht übertragen werden'),
        matching: find.byType(InkWell),
      );
      expect(line, findsNothing);
    });
  });
}
