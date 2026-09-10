import 'package:activity_tracker/activity_tracker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../shell/background_services.dart';
import 'idle_prompt_dialog.dart';
import 'timer_providers.dart';

/// Idle time is prompted about once it reaches this threshold, on desktop
/// only (see [isDesktopTrackingSupported]).
const _idleThresholdSeconds = 5 * 60;

/// Owns the idle prompt and activity sampling for the whole app.
///
/// Lives directly under MaterialApp rather than inside the timer tab: the
/// pill replaces the tab, and both concerns must keep working while it does.
/// Its context is below MaterialApp, so showIdlePromptDialog still has a
/// Navigator.
class TimerBackgroundHandlers extends ConsumerStatefulWidget {
  const TimerBackgroundHandlers({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TimerBackgroundHandlers> createState() =>
      TimerBackgroundHandlersState();
}

class TimerBackgroundHandlersState
    extends ConsumerState<TimerBackgroundHandlers> {
  bool _idlePromptShowing = false;

  Future<void> handleIdleSecondsChanged(int idleSeconds) async {
    if (idleSeconds < _idleThresholdSeconds) {
      _idlePromptShowing = false;
      return;
    }
    if (_idlePromptShowing) return;
    final running = ref.read(runningEntryProvider).value;
    if (running == null || running.pausedAt != null) return;

    _idlePromptShowing = true;
    final idleDuration = Duration(seconds: idleSeconds);
    final shouldTrim = await showIdlePromptDialog(context, idleDuration);
    if (!mounted) return;
    if (shouldTrim) {
      final writes = await ref.read(syncedWritesProvider.future);
      final idleStart = DateTime.now().subtract(idleDuration);
      await writes.updateEntry(running.id, endAt: Value(idleStart.toUtc()));
    }
    _idlePromptShowing = false;
  }

  Future<void> recordActivitySample(ActivitySample sample) async {
    final running = ref.read(runningEntryProvider).value;
    if (running == null || running.pausedAt != null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.recordActivitySample(
      deviceId: deviceId,
      appName: sample.appName,
      windowTitle: sample.windowTitle,
      observedAt: sample.observedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundServices(
      onIdle: handleIdleSecondsChanged,
      onActivity: recordActivitySample,
      child: widget.child,
    );
  }
}
