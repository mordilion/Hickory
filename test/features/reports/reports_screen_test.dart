import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/report_view_controller.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';
import 'package:hickory/features/reports/reports_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

Project _project({
  required String id,
  required String name,
  bool billable = true,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Project(
    id: id,
    name: name,
    colorHex: '#5B8DEF',
    archived: false,
    billable: billable,
    hourlyRateCents: null,
    currency: null,
    createdAt: now,
    updatedAt: now,
  );
}

TimeEntry _entry({required String id, String? projectId}) {
  final now = DateTime.utc(2026, 8, 7, 9);
  return TimeEntry(
    id: id,
    projectId: projectId,
    description: null,
    startAt: now,
    endAt: now.add(const Duration(hours: 1)),
    pausedAt: null,
    totalPausedSeconds: 0,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tempDir;

  setUp(
    () => tempDir = Directory.systemTemp.createTempSync('reports_screen_test_'),
  );
  tearDown(() => tempDir.deleteSync(recursive: true));

  final projectA = _project(id: 'p1', name: 'Project A');
  final projectB = _project(id: 'p2', name: 'Project B', billable: false);
  final entries = [
    _entry(id: 'e1', projectId: 'p1'),
    _entry(id: 'e2', projectId: 'p2'),
  ];

  // Same static-override pattern used throughout this codebase's other
  // widget tests (see timer_screen_test.dart) to avoid subscribing to a
  // live drift-backed StreamProvider, which hits a known flutter_test false
  // positive at teardown (flutter/flutter#144472).
  // reportViewStateStoreProvider is left live (real file IO against tempDir,
  // not drift) so the test exercises real ReportViewController wiring, same
  // as language_dropdown_test.dart.
  Widget makeApp() => ProviderScope(
    overrides: [
      reportEntriesProvider.overrideWith((ref, range) => Stream.value(entries)),
      reportProjectsProvider.overrideWith(
        (ref) => Stream.value([projectA, projectB]),
      ),
      reportViewStateStoreProvider.overrideWith(
        (ref) async => ReportViewStateStore(supportDirectory: tempDir),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: ReportsScreen()),
    ),
  );

  // AppTheme.light pulls in buildAppTextTheme, which calls
  // GoogleFonts.unbounded()/manrope() for every text role. Each of those
  // kicks off an internal, fire-and-forget font-load Future (see
  // google_fonts' own `pendingFontFutures` set in google_fonts_base.dart).
  // That code tracks completion with a bare
  // `.then((_) => pendingFontFutures.remove(loadingFuture))` and no
  // `onError`, so when a load fails -- as it always does here, since
  // flutter_test blocks the real network fetch google_fonts falls back to
  // -- the error propagates into a *new*, untracked Future that nothing
  // (not even the package's own drain API) ever attaches a listener to. It
  // can only be caught by owning the zone the code ran in via `onError`
  // (mirrors the identical problem/wrapper in app_theme_test.dart). Scoped
  // tightly around just the widget construction (where AppTheme.light gets
  // evaluated) rather than the whole test body, since it doesn't need to
  // wrap tester.runAsync()/pumpAndSettle() at all.
  Widget buildAppIsolatingFontErrors() {
    late Widget app;
    runZonedGuarded(() => app = makeApp(), (error, stack) {
      if (!error.toString().contains('Failed to load font with url')) {
        Error.throwWithStackTrace(error, stack);
      }
    });
    return app;
  }

  // ReportViewController.build() does a real dart:io file read, which can't
  // complete inside testWidgets' fake-async zone on its own -- same issue
  // and same fix as language_dropdown_test.dart's pumpRealIo.
  Future<void> pumpRealIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }

  // Waits for the ReportViewController's real disk read AND the entries/
  // projects StreamProviders to finish resolving -- the filter icon renders
  // on the very first frame regardless of those streams' state, so a plain
  // wait for the icon alone can race ahead of the project/entry data still
  // being AsyncLoading (which, for the filter button, is a silent no-op).
  Future<void> pumpUntilReady(WidgetTester tester) async {
    for (
      var i = 0;
      i < 50 && find.byIcon(Icons.filter_list).evaluate().isEmpty;
      i++
    ) {
      await pumpRealIo(tester);
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows Today/Yesterday presets and both projects with no filter active',
    (tester) async {
      await tester.pumpWidget(buildAppIsolatingFontErrors());
      await pumpUntilReady(tester);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Project A'), findsOneWidget);
      expect(find.text('Project B'), findsOneWidget);
    },
  );

  testWidgets('tapping Today selects it and deselects This month', (
    tester,
  ) async {
    await tester.pumpWidget(buildAppIsolatingFontErrors());
    await pumpUntilReady(tester);

    final thisMonthBefore = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('This month'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(thisMonthBefore.selected, isTrue);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    final todayAfter = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Today'), matching: find.byType(ChoiceChip)),
    );
    final thisMonthAfter = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('This month'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(todayAfter.selected, isTrue);
    expect(thisMonthAfter.selected, isFalse);
  });

  testWidgets(
    'filtering to one project narrows the list, and a further billable filter reaches '
    'the filtered empty state',
    (tester) async {
      await tester.pumpWidget(buildAppIsolatingFontErrors());
      await pumpUntilReady(tester);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Project A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Project A'), findsOneWidget);
      expect(find.text('Project B'), findsNothing);

      // Project A is billable, so filtering to non-billable-only on top of
      // the project filter leaves no matching entries.
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non-billable only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        find.text('No entries for this period and these filters.'),
        findsOneWidget,
      );

      // The export button is disabled for an empty list -- this only holds
      // if it was built from the filtered entries, not the raw unfiltered
      // range query (which still has 2 entries at this point).
      final exportButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.byIcon(Icons.download),
          matching: find.byType(FilledButton),
        ),
      );
      expect(exportButton.onPressed, isNull);
    },
  );

  testWidgets('Reset filters clears the project and billable selection', (
    tester,
  ) async {
    await tester.pumpWidget(buildAppIsolatingFontErrors());
    await pumpUntilReady(tester);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Project A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Project A'), findsOneWidget);
    expect(find.text('Project B'), findsOneWidget);
  });
}
