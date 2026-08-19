import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/update/update_progress.dart';

void main() {
  group('UpdateDownloading.fraction', () {
    test('is the ratio of received to total', () {
      expect(
        const UpdateDownloading(receivedBytes: 25, totalBytes: 100).fraction,
        0.25,
      );
    });

    test('is null without a total, so the bar can go indeterminate', () {
      expect(const UpdateDownloading(receivedBytes: 25).fraction, isNull);
    });

    test('is null for a zero total rather than dividing by it', () {
      expect(
        const UpdateDownloading(receivedBytes: 0, totalBytes: 0).fraction,
        isNull,
      );
    });
  });

  group('DownloadProgressThrottle', () {
    test('reports the first chunk, then only whole-percent changes', () {
      final throttle = DownloadProgressThrottle();

      expect(throttle.shouldReport(receivedBytes: 1, totalBytes: 100), isTrue);
      // Still 1%: a repaint here would buy nothing.
      expect(throttle.shouldReport(receivedBytes: 1, totalBytes: 100), isFalse);
      expect(throttle.shouldReport(receivedBytes: 2, totalBytes: 100), isTrue);
      expect(throttle.shouldReport(receivedBytes: 50, totalBytes: 100), isTrue);
      expect(
        throttle.shouldReport(receivedBytes: 50, totalBytes: 100),
        isFalse,
      );
    });

    test('always reports completion', () {
      final throttle = DownloadProgressThrottle();
      throttle.shouldReport(receivedBytes: 100, totalBytes: 100);

      // Same percentage as the previous call, but the last chunk must land so
      // the bar reaches its end instead of stopping at 99%.
      expect(
        throttle.shouldReport(receivedBytes: 100, totalBytes: 100),
        isTrue,
      );
    });

    test('falls back to fixed byte steps without a total', () {
      final throttle = DownloadProgressThrottle();

      expect(throttle.shouldReport(receivedBytes: 1000), isTrue);
      expect(throttle.shouldReport(receivedBytes: 2000), isFalse);
      expect(throttle.shouldReport(receivedBytes: 1000 + 262144), isTrue);
    });

    test('treats a zero total like an unknown one', () {
      final throttle = DownloadProgressThrottle();

      expect(throttle.shouldReport(receivedBytes: 10, totalBytes: 0), isTrue);
      expect(throttle.shouldReport(receivedBytes: 20, totalBytes: 0), isFalse);
    });
  });
}
