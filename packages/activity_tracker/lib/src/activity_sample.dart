/// A single observation of which application/window was focused at a point
/// in time. Emitted by [ActivityTracker.activeWindowChanges] on desktop
/// (macOS/Windows) whenever the foreground app changes.
class ActivitySample {
  const ActivitySample({
    required this.appName,
    this.windowTitle,
    required this.observedAt,
  });

  /// The foreground process's display/executable name.
  final String appName;

  /// The foreground window's title, if available. Null on macOS when the
  /// user has not granted the Accessibility permission (app-name-only
  /// degradation — see [ActivityTracker.hasPermissions]).
  final String? windowTitle;

  /// UTC timestamp of the observation.
  final DateTime observedAt;

  factory ActivitySample.fromMap(Map<Object?, Object?> map) {
    return ActivitySample(
      appName: map['appName'] as String,
      windowTitle: map['windowTitle'] as String?,
      observedAt: DateTime.fromMillisecondsSinceEpoch(
        map['observedAtMillis'] as int,
        isUtc: true,
      ),
    );
  }

  @override
  String toString() => 'ActivitySample($appName${windowTitle != null ? ' — $windowTitle' : ''} '
      '@ $observedAt)';
}
