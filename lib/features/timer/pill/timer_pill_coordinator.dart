import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/window/window_mode.dart';
import '../../../core/window/window_mode_provider.dart';
import '../../../data/drift/database.dart';
import '../timer_providers.dart';

/// Collapses the window to the pill when a timer starts, and expands it again
/// when that entry stops. Deliberately reacts only to the presence of a
/// running entry: pausing keeps the pill, and expanding by hand (the pill's
/// expand button) is not undone by this widget.
///
/// Mounted above the mode switch so it survives the tree swap it causes.
class TimerPillCoordinator extends ConsumerStatefulWidget {
  const TimerPillCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TimerPillCoordinator> createState() => _TimerPillCoordinatorState();
}

class _TimerPillCoordinatorState extends ConsumerState<TimerPillCoordinator> {
  // Null until the first emission arrives; that first value is app-launch
  // state (possibly a forgotten-running entry, spec 4.3), not a transition,
  // so it must never trigger a collapse. See _onRunningChanged.
  bool? _wasRunning;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TimeEntry?>>(runningEntryProvider, (previous, next) {
      next.whenData(_onRunningChanged);
    });
    return widget.child;
  }

  void _onRunningChanged(TimeEntry? running) {
    final isRunning = running != null;
    if (_wasRunning == isRunning) return;
    final hadPreviousValue = _wasRunning != null;
    _wasRunning = isRunning;
    // The very first emission is the current state, not a transition -- a
    // start that already happened before this widget mounted (an app launch
    // with an entry still running) must not collapse the window, see spec 4.3.
    if (!hadPreviousValue) return;

    final notifier = ref.read(windowModeProvider.notifier);
    if (isRunning) {
      notifier.collapse();
      return;
    }
    if (ref.read(windowModeProvider) == WindowMode.pill) notifier.expand();
  }
}
