import 'dart:async';

import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/auto_sync_trigger.dart';
import 'package:hickory/features/timer/idle_tracking.dart';
import 'package:hickory/features/timer/timer_background_handlers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

/// Starts in pill mode and records every collapse/expand call, so the tests
/// below can assert the handler expanded before showing its dialog.
class _PillModeNotifier extends WindowModeNotifier {
  final calls = <String>[];

  @override
  WindowMode build() => WindowMode.pill;

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

/// Starts already in full mode. A separate class rather than driving
/// [_PillModeNotifier.expand] directly: calling a Notifier's state setter
/// before anything has read the provider can hit it uninitialized.
class _FullModeNotifier extends WindowModeNotifier {
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

TimeEntry _running() => TimeEntry(
  id: 'e1',
  deviceId: 'd1',
  startAt: DateTime.utc(2026, 9, 10, 8),
  endAt: null,
  pausedAt: null,
  totalPausedSeconds: 0,
  source: 'manual',
  projectId: null,
  description: null,
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 8),
);

/// Builds the widget tree under test. [child] is a [Consumer] that watches
/// [runningEntryProvider] so the stream has actually emitted -- and the
/// value is cached in the provider -- before a test invokes the handler;
/// otherwise `ref.read(runningEntryProvider).value` inside the handler would
/// see null and return early, failing every test for the wrong reason.
Widget _harness({
  required WindowModeNotifier Function() notifier,
  required GlobalKey<TimerBackgroundHandlersState> key,
}) {
  return ProviderScope(
    overrides: [
      windowModeProvider.overrideWith(notifier),
      runningEntryProvider.overrideWith((ref) => Stream.value(_running())),
      idleSecondsProvider.overrideWith((ref) => const Stream<int>.empty()),
      activeWindowChangesProvider
          .overrideWith((ref) => const Stream<ActivitySample>.empty()),
      // BackgroundServices (rendered by TimerBackgroundHandlers) also watches
      // these; jiraAutoSyncProvider reads settings, subscribes to
      // allEntriesProvider and schedules a 3s Timer, so leaving it
      // un-overridden reaches the real database and leaves a pending timer.
      syncWatcherProvider.overrideWith((ref) async {}),
      jiraAutoSyncProvider.overrideWithValue(AutoSyncTrigger(() async {})),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TimerBackgroundHandlers(
        key: key,
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(runningEntryProvider);
            return const SizedBox();
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('expands the window before showing the idle prompt', (
    tester,
  ) async {
    final notifier = _PillModeNotifier();
    final key = GlobalKey<TimerBackgroundHandlersState>();

    await tester.pumpWidget(_harness(notifier: () => notifier, key: key));
    await tester.pumpAndSettle();

    unawaited(key.currentState!.handleIdleSecondsChanged(600));
    await tester.pumpAndSettle();

    expect(notifier.calls, contains('expand'));
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('does not expand when already in full mode', (tester) async {
    final notifier = _FullModeNotifier();
    final key = GlobalKey<TimerBackgroundHandlersState>();

    await tester.pumpWidget(_harness(notifier: () => notifier, key: key));
    await tester.pumpAndSettle();

    unawaited(key.currentState!.handleIdleSecondsChanged(600));
    await tester.pumpAndSettle();

    expect(notifier.calls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('below the threshold nothing happens at all', (tester) async {
    final notifier = _PillModeNotifier();
    final key = GlobalKey<TimerBackgroundHandlersState>();

    await tester.pumpWidget(_harness(notifier: () => notifier, key: key));
    await tester.pumpAndSettle();

    await key.currentState!.handleIdleSecondsChanged(10);
    await tester.pumpAndSettle();

    expect(notifier.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
