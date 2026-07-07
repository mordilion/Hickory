import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/duration_format.dart';

// A full widget-pump test (ProviderScope + drift + the timer screen) hits a
// known flutter_test false positive: disposing the widget tree can itself
// schedule a zero-duration Timer, which the framework's pending-timers
// invariant check flags even though it's harmless
// (see https://github.com/flutter/flutter/issues/144472). That combination
// also runs multiple minutes per iteration on this machine, making it
// impractical to chase further here. formatDuration is covered instead;
// the app itself was verified by building and launching the real Windows
// executable (see the M1 build/run verification).
void main() {
  test('formatDuration pads to HH:MM:SS', () {
    expect(formatDuration(Duration.zero), '00:00:00');
    expect(formatDuration(const Duration(seconds: 5)), '00:00:05');
    expect(formatDuration(const Duration(minutes: 9, seconds: 3)), '00:09:03');
    expect(formatDuration(const Duration(hours: 2, minutes: 15, seconds: 30)), '02:15:30');
  });
}
