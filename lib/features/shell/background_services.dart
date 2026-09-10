import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../timer/idle_tracking.dart';

/// Holds the subscriptions that must outlive any screen: the sync folder
/// watcher, Jira auto-sync, idle detection and activity sampling.
///
/// These used to live in TimerScreen.build(), which worked only because
/// NavShell's IndexedStack keeps that tab mounted forever. The timer pill
/// replaces the whole tree, so anything anchored to a screen would stop
/// exactly while a timer runs. Side effects: starts four subscriptions for
/// as long as this widget is mounted.
class BackgroundServices extends ConsumerWidget {
  const BackgroundServices({
    super.key,
    required this.child,
    required this.onIdle,
    required this.onActivity,
  });

  final Widget child;
  final void Function(int idleSeconds) onIdle;
  final void Function(ActivitySample sample) onActivity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncWatcherProvider);
    ref.watch(jiraAutoSyncProvider);

    ref.listen<AsyncValue<int>>(idleSecondsProvider, (previous, next) {
      final idleSeconds = next.value;
      if (idleSeconds != null) onIdle(idleSeconds);
    });
    ref.listen<AsyncValue<ActivitySample>>(activeWindowChangesProvider, (
      previous,
      next,
    ) {
      final sample = next.value;
      if (sample != null) onActivity(sample);
    });

    return child;
  }
}
