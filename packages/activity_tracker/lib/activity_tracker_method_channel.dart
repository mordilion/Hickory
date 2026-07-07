import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'activity_tracker_platform_interface.dart';
import 'src/activity_sample.dart';

/// An implementation of [ActivityTrackerPlatform] that uses method/event
/// channels — the only implementation, on both supported platforms
/// (macOS/Windows each provide the native side of the same channels).
class MethodChannelActivityTracker extends ActivityTrackerPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('hickory/activity_tracker');

  @visibleForTesting
  final eventChannel = const EventChannel('hickory/activity_tracker/events');

  Stream<ActivitySample>? _activeWindowChanges;

  @override
  Stream<ActivitySample> get activeWindowChanges {
    return _activeWindowChanges ??= eventChannel.receiveBroadcastStream().map(
          (event) => ActivitySample.fromMap(event as Map<Object?, Object?>),
        );
  }

  @override
  Future<int> getIdleSeconds() async {
    final seconds = await methodChannel.invokeMethod<int>('getIdleSeconds');
    return seconds ?? 0;
  }

  @override
  Future<bool> hasPermissions() async {
    final result = await methodChannel.invokeMethod<bool>('hasPermissions');
    return result ?? false;
  }

  @override
  Future<bool> requestPermissions() async {
    final result = await methodChannel.invokeMethod<bool>('requestPermissions');
    return result ?? false;
  }
}
