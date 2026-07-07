import 'dart:io';

import 'package:activity_tracker/activity_tracker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/activity_tracker_provider.dart';

/// The activity_tracker plugin only ships native code for macOS/Windows
/// (its pubspec declares no ios/android platform keys); calling it on
/// other platforms would hit a MissingPluginException, so the app must
/// gate usage the same way at runtime.
bool get isDesktopTrackingSupported => Platform.isWindows || Platform.isMacOS;

/// Idle seconds, polled every 5s. Desktop only — a constant 0 elsewhere.
final idleSecondsProvider = StreamProvider<int>((ref) async* {
  if (!isDesktopTrackingSupported) {
    yield 0;
    return;
  }
  final tracker = ref.watch(activityTrackerProvider);
  while (true) {
    yield await tracker.getIdleSeconds();
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});

/// Emits whenever the foreground app/window changes. Desktop only — never
/// emits elsewhere.
final activeWindowChangesProvider = StreamProvider<ActivitySample>((ref) {
  if (!isDesktopTrackingSupported) return const Stream.empty();
  return ref.watch(activityTrackerProvider).activeWindowChanges;
});
