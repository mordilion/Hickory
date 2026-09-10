import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/absence_providers.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/personio_providers.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/shell/app_shell.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

/// Records every mode transition instead of touching a real
/// [WindowModeController] -- same fake used by
/// test/features/timer/pill/timer_pill_coordinator_test.dart, which
/// documents why this is simpler than overriding
/// windowModeControllerProvider directly.
class _FakeWindowModeNotifier extends WindowModeNotifier {
  final calls = <String>[];

  @override
  WindowMode build() => WindowMode.full;

  @override
  Future<void> collapse() async {
    calls.add('collapse');
    state = WindowMode.pill;
  }

  @override
  Future<void> expand() async {
    calls.add('expand');
    state = WindowMode.full;
  }
}

/// SyncScreen reads its configured credentials on init without a try/catch
/// (see sync_screen.dart's _loadJiraCredentials); a real
/// SecureJiraCredentialsStore would hit a platform channel no widget test
/// provides, turning that unguarded read into an unhandled exception. This
/// (and _NoopPersonioCredentialsStore below) is the same fake
/// app_reset_section_test.dart already uses for the same reason.
class _NoopJiraCredentialsStore implements JiraCredentialsStore {
  @override
  Future<JiraCredentials?> read() async => null;
  @override
  Future<void> write(JiraCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

class _NoopPersonioCredentialsStore implements PersonioCredentialsStore {
  @override
  Future<PersonioCredentials?> read() async => null;
  @override
  Future<void> write(PersonioCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

TimeEntry _runningEntry() {
  final now = DateTime.utc(2026, 9, 10, 8);
  return TimeEntry(
    id: 'running-1',
    deviceId: 'device-1',
    startAt: now,
    endAt: null,
    pausedAt: null,
    totalPausedSeconds: 0,
    source: 'manual',
    projectId: null,
    description: null,
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('AppShell', () {
    // NavShell's IndexedStack keeps all four tabs mounted at once (not just
    // the selected one), so every provider any tab touches during build has
    // to resolve safely even while a different tab is showing -- this
    // covers Timer, Reports, Sync and Settings simultaneously rather than
    // just the Timer tab the FAB's own condition depends on.
    late Directory syncRoot;

    setUp(() {
      syncRoot = Directory.systemTemp.createTempSync('hickory_app_shell_test_');
    });

    tearDown(() {
      if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
    });

    // AppTheme.light is required (not a plain MaterialApp theme) because
    // TimerScreen's running/start cards call HickoryColors.of(context),
    // which throws off a theme with no HickoryColors extension registered.
    // Building it triggers GoogleFonts' fire-and-forget font-load Future,
    // which always fails under flutter_test (no network) and otherwise
    // escapes as an unhandled Zone error -- same wrapper, same reason, as
    // reports_screen_test.dart's buildAppIsolatingFontErrors.
    Widget buildAppIsolatingFontErrors({
      required TimeEntry? running,
      required WindowModeNotifier notifier,
    }) {
      late Widget app;
      runZonedGuarded(
        () => app = ProviderScope(
          overrides: [
            windowModeProvider.overrideWith(() => notifier),
            runningEntryProvider.overrideWith((ref) => Stream.value(running)),
            // Every stream below is watched during build by whichever tab
            // uses it, regardless of which tab is selected (see the
            // IndexedStack note above) -- overridden as fixed values, not
            // left on the real (unopened, in this test) database, for the
            // same "no live drift stream in a widget test" reason
            // timer_screen_test.dart and reports_screen_test.dart give.
            allEntriesProvider.overrideWith((ref) => Stream.value(const [])),
            activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
            jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
            personioAttendancesByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
            breakRuleTiersProvider.overrideWith((ref) => Stream.value(const [])),
            absencesProvider.overrideWith((ref) => Stream.value(const [])),
            absenceTypesProvider.overrideWith((ref) => Stream.value(const [])),
            appSettingsProvider.overrideWith((ref) => Stream.value(appSettingsFixture())),
            // SyncScreen reads these three via unguarded `.future` calls in
            // initState (see sync_screen.dart) -- real defaults would hit a
            // secure-storage/database platform channel and surface as an
            // unhandled exception rather than a handled AsyncValue.error.
            jiraCredentialsStoreProvider.overrideWithValue(_NoopJiraCredentialsStore()),
            personioCredentialsStoreProvider.overrideWithValue(_NoopPersonioCredentialsStore()),
            personioLatestSyncedAtProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const AppShell(),
          ),
        ),
        (error, stack) {
          if (!error.toString().contains('Failed to load font with url')) {
            Error.throwWithStackTrace(error, stack);
          }
        },
      );
      return app;
    }

    testWidgets('no collapse button while nothing is running', (tester) async {
      await tester.pumpWidget(
        buildAppIsolatingFontErrors(running: null, notifier: _FakeWindowModeNotifier()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close_fullscreen), findsNothing);
    });

    testWidgets('collapses on tap and stays available after switching to another tab', (
      tester,
    ) async {
      final notifier = _FakeWindowModeNotifier();
      await tester.pumpWidget(
        buildAppIsolatingFontErrors(running: _runningEntry(), notifier: notifier),
      );
      // Not pumpAndSettle(): the Reports tab's filter spinner
      // (reportViewControllerProvider never resolves here -- see the
      // override list above) and Sync's folder-load indicator are
      // indeterminate progress animations that never stop, which would make
      // pumpAndSettle() time out regardless of the FAB's own state.
      //
      // Not a single fixed-duration pump() either, even though its Duration
      // covers far more than Scaffold's own FAB entrance animation
      // (kFloatingActionButtonSegue, 200ms): runningEntryProvider resolves
      // one microtask after pumpWidget(), so the FAB's ScaleTransition
      // starts its AnimationController.forward() *during* the build of
      // whichever single frame that pump() call ends up producing. That
      // controller's elapsed time is measured from its own start timestamp,
      // which is that same frame's timestamp -- so the transform this one
      // frame paints with is still the animation's t=0 value (scale 0, an
      // unhittable point) no matter how long a Duration the pump was given.
      // It only advances on a *later* frame's tick callback. A loop of
      // short pumps forces those later frames to actually happen, letting
      // the entrance animation reach its settled, hit-testable scale.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

      // A real tap, dispatched through hit-testing and the gesture arena --
      // not a direct onPressed() call -- now that the loop above gives the
      // entrance transition's transform time to settle. This is the
      // meaningful difference for Finding 1's regression: an onPressed()
      // call would still succeed even if something else visually and
      // functionally covered the FAB, since it never asks the render tree
      // what is actually hit-testable at that point on screen.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(notifier.calls, ['collapse']);

      // The client-phone-call scenario the button exists for: it has to
      // survive a tab switch away from Timer, not just render there.
      await tester.tap(find.text('Reports'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);
    });
  });
}
