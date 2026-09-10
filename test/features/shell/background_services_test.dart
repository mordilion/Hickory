import 'dart:async';

import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/sync/auto_sync_trigger.dart';
import 'package:hickory/features/shell/background_services.dart';
import 'package:hickory/features/timer/idle_tracking.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          idleSecondsProvider.overrideWith((ref) => const Stream<int>.empty()),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
          syncWatcherProvider.overrideWith((ref) async {}),
          jiraAutoSyncProvider.overrideWithValue(AutoSyncTrigger(() async {})),
        ],
        child: MaterialApp(
          home: BackgroundServices(
            onIdle: (_) {},
            onActivity: (_) {},
            child: const Text('child'),
          ),
        ),
      ),
    );

    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('forwards idle seconds to the callback', (tester) async {
    final seen = <int>[];
    final idle = StreamController<int>();
    addTearDown(idle.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          idleSecondsProvider.overrideWith((ref) => idle.stream),
          activeWindowChangesProvider
              .overrideWith((ref) => const Stream<ActivitySample>.empty()),
          syncWatcherProvider.overrideWith((ref) async {}),
          jiraAutoSyncProvider.overrideWithValue(AutoSyncTrigger(() async {})),
        ],
        child: MaterialApp(
          home: BackgroundServices(
            onIdle: seen.add,
            onActivity: (_) {},
            child: const SizedBox(),
          ),
        ),
      ),
    );

    idle.add(400);
    await tester.pump();

    expect(seen, [400]);
  });

  testWidgets('keeps forwarding after the child is replaced', (tester) async {
    // The whole point of this widget: the pill swaps the child, and the
    // subscriptions must survive that swap.
    final seen = <int>[];
    final idle = StreamController<int>();
    addTearDown(idle.close);

    Widget build(Widget child) => ProviderScope(
      overrides: [
        idleSecondsProvider.overrideWith((ref) => idle.stream),
        activeWindowChangesProvider
            .overrideWith((ref) => const Stream<ActivitySample>.empty()),
        syncWatcherProvider.overrideWith((ref) async {}),
        jiraAutoSyncProvider.overrideWithValue(AutoSyncTrigger(() async {})),
      ],
      child: MaterialApp(
        home: BackgroundServices(
          onIdle: seen.add,
          onActivity: (_) {},
          child: child,
        ),
      ),
    );

    await tester.pumpWidget(build(const Text('full')));
    await tester.pumpWidget(build(const Text('pill')));

    idle.add(500);
    await tester.pump();

    expect(find.text('pill'), findsOneWidget);
    expect(seen, [500]);
  });
}
