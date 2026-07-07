import 'package:activity_tracker/activity_tracker.dart';
import 'package:activity_tracker/activity_tracker_method_channel.dart';
import 'package:activity_tracker/activity_tracker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockActivityTrackerPlatform
    with MockPlatformInterfaceMixin
    implements ActivityTrackerPlatform {
  @override
  Stream<ActivitySample> get activeWindowChanges => Stream.value(
        ActivitySample(
          appName: 'Fake App',
          windowTitle: 'Fake Window',
          observedAt: DateTime.utc(2026, 7, 7),
        ),
      );

  @override
  Future<int> getIdleSeconds() => Future.value(42);

  @override
  Future<bool> hasPermissions() => Future.value(true);

  @override
  Future<bool> requestPermissions() => Future.value(true);
}

void main() {
  final ActivityTrackerPlatform initialPlatform = ActivityTrackerPlatform.instance;

  test('$MethodChannelActivityTracker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelActivityTracker>());
  });

  test('ActivityTracker delegates to the platform instance', () async {
    final activityTracker = ActivityTracker();
    ActivityTrackerPlatform.instance = MockActivityTrackerPlatform();

    expect(await activityTracker.getIdleSeconds(), 42);
    expect(await activityTracker.hasPermissions(), isTrue);
    expect(await activityTracker.requestPermissions(), isTrue);
    expect(await activityTracker.activeWindowChanges.first, isA<ActivitySample>());
  });
}
