import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'activity_tracker_method_channel.dart';
import 'src/activity_sample.dart';

abstract class ActivityTrackerPlatform extends PlatformInterface {
  ActivityTrackerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ActivityTrackerPlatform _instance = MethodChannelActivityTracker();

  /// Defaults to [MethodChannelActivityTracker].
  static ActivityTrackerPlatform get instance => _instance;

  static set instance(ActivityTrackerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Emits a sample every time the foreground app/window changes.
  Stream<ActivitySample> get activeWindowChanges {
    throw UnimplementedError('activeWindowChanges has not been implemented.');
  }

  /// Seconds since the last user input (keyboard/mouse) anywhere on the
  /// system, not just within Hickory.
  Future<int> getIdleSeconds() {
    throw UnimplementedError('getIdleSeconds() has not been implemented.');
  }

  /// True if the permissions needed for full tracking (window titles, not
  /// just app names) are already granted. Always true on Windows, since it
  /// needs no special permission for this.
  Future<bool> hasPermissions() {
    throw UnimplementedError('hasPermissions() has not been implemented.');
  }

  /// Prompts the user to grant the permission needed for window-title
  /// tracking (macOS Accessibility). Returns the resulting [hasPermissions]
  /// state. No-op returning true on Windows.
  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }
}
