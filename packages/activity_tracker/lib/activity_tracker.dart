import 'activity_tracker_platform_interface.dart';
import 'src/activity_sample.dart';

export 'src/activity_sample.dart';

/// Desktop-only (macOS/Windows) automatic activity tracking: which
/// app/window is focused, and how long the user has been idle. This
/// package's `pubspec.yaml` declares only the `macos` and `windows`
/// platform keys, so Flutter's build system excludes it entirely from
/// iOS/Android builds — no `Platform.isX` guards needed at the build level.
class ActivityTracker {
  /// Emits a sample every time the foreground app/window changes.
  Stream<ActivitySample> get activeWindowChanges =>
      ActivityTrackerPlatform.instance.activeWindowChanges;

  /// Seconds since the last user input (keyboard/mouse) anywhere on the
  /// system, not just within Hickory.
  Future<int> getIdleSeconds() => ActivityTrackerPlatform.instance.getIdleSeconds();

  /// True if window-title tracking is already permitted (always true on
  /// Windows; reflects the Accessibility permission on macOS).
  Future<bool> hasPermissions() => ActivityTrackerPlatform.instance.hasPermissions();

  /// Prompts for the permission window-title tracking needs (macOS
  /// Accessibility only). No-op returning true on Windows.
  Future<bool> requestPermissions() => ActivityTrackerPlatform.instance.requestPermissions();
}
