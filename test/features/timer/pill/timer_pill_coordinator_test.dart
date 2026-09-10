import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/timer/pill/timer_pill_coordinator.dart';
import 'package:hickory/features/timer/timer_providers.dart';

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

TimeEntry _entry() => TimeEntry(
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

void main() {
  testWidgets('collapses when an entry starts running', (tester) async {
    final notifier = _FakeWindowModeNotifier();
    final running = StreamController<TimeEntry?>();
    addTearDown(running.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => running.stream),
        ],
        child: const MaterialApp(
          home: TimerPillCoordinator(child: Text('shell')),
        ),
      ),
    );

    running.add(null);
    await tester.pump();
    expect(notifier.calls, isEmpty);

    running.add(_entry());
    await tester.pump();
    expect(notifier.calls, ['collapse']);
  });

  testWidgets(
    'does not collapse when an entry is already running on the first emission',
    (tester) async {
      final notifier = _FakeWindowModeNotifier();
      final running = StreamController<TimeEntry?>();
      addTearDown(running.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            windowModeProvider.overrideWith(() => notifier),
            runningEntryProvider.overrideWith((ref) => running.stream),
          ],
          child: const MaterialApp(
            home: TimerPillCoordinator(child: Text('shell')),
          ),
        ),
      );

      // Models app start with yesterday's timer still running (spec 4.3):
      // the very first value this coordinator ever sees already being a
      // running entry must not be treated as a start transition, or the
      // user would lose the full window they need to fix it.
      running.add(_entry());
      await tester.pump();

      expect(notifier.calls, isEmpty);
    },
  );

  testWidgets('expands when the running entry stops', (tester) async {
    final notifier = _FakeWindowModeNotifier();
    final running = StreamController<TimeEntry?>();
    addTearDown(running.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => running.stream),
        ],
        child: const MaterialApp(
          home: TimerPillCoordinator(child: Text('shell')),
        ),
      ),
    );

    // Seed the "nothing running yet" baseline first, exactly as the
    // "collapses" test above does: without it, the entry below would be
    // this coordinator's first-ever observation and, per the first-emission
    // rule, would not count as a transition -- see the test above.
    running.add(null);
    await tester.pump();
    running.add(_entry());
    await tester.pump();
    running.add(null);
    await tester.pump();

    expect(notifier.calls, ['collapse', 'expand']);
  });

  testWidgets('pausing does not change the mode', (tester) async {
    final notifier = _FakeWindowModeNotifier();
    final running = StreamController<TimeEntry?>();
    addTearDown(running.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowModeProvider.overrideWith(() => notifier),
          runningEntryProvider.overrideWith((ref) => running.stream),
        ],
        child: const MaterialApp(
          home: TimerPillCoordinator(child: Text('shell')),
        ),
      ),
    );

    // Same baseline seed as above, for the same reason.
    running.add(null);
    await tester.pump();
    running.add(_entry());
    await tester.pump();
    running.add(_entry().copyWith(pausedAt: Value(DateTime.utc(2026, 9, 10, 9))));
    await tester.pump();

    expect(notifier.calls, ['collapse']);
  });
}
