/// Where an in-progress update currently is, for the Settings UI to render.
///
/// Only the download knows how much work is left, so only it carries numbers.
/// The other phases are named rather than measured -- inventing weights for
/// them would produce a bar that jumps and then hangs.
sealed class UpdateProgress {
  const UpdateProgress();
}

/// Downloading the release archive.
final class UpdateDownloading extends UpdateProgress {
  const UpdateDownloading({required this.receivedBytes, this.totalBytes});

  final int receivedBytes;

  /// Null when the response carried no `Content-Length` -- GitHub's asset
  /// redirects normally do, but a chunked response is allowed to omit it.
  final int? totalBytes;

  /// Completed share of the download, or null when it can't be known, which the
  /// UI turns into an indeterminate bar.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return receivedBytes / total;
  }
}

/// Comparing the download against its published checksum.
final class UpdateVerifying extends UpdateProgress {
  const UpdateVerifying();
}

/// Unpacking the archive.
final class UpdateExtracting extends UpdateProgress {
  const UpdateExtracting();
}

/// Decides which download chunks are worth reporting to the UI.
///
/// A 23 MB download arrives in thousands of chunks; forwarding each one would
/// mean thousands of rebuilds for a bar that is at most a few hundred pixels
/// wide. Reporting on whole-percent changes keeps every visible step and drops
/// the rest.
class DownloadProgressThrottle {
  /// Byte step used when the total size is unknown and percentages are
  /// therefore meaningless.
  static const _unknownTotalStep = 256 * 1024;

  int _lastPercent = -1;

  /// Starts a full step below zero so the very first chunk reports: without a
  /// total there is no percentage to change, and the user should still see the
  /// download start immediately.
  int _lastReportedBytes = -_unknownTotalStep;

  /// True when this chunk should be forwarded. Completion always reports, so
  /// the bar reaches its end rather than stopping just short of it.
  bool shouldReport({required int receivedBytes, int? totalBytes}) {
    final total = totalBytes;
    if (total == null || total <= 0) {
      if (receivedBytes - _lastReportedBytes < _unknownTotalStep) return false;
      _lastReportedBytes = receivedBytes;
      return true;
    }
    if (receivedBytes >= total) {
      _lastPercent = 100;
      _lastReportedBytes = receivedBytes;
      return true;
    }
    final percent = (receivedBytes * 100 / total).floor();
    if (percent == _lastPercent) return false;
    _lastPercent = percent;
    _lastReportedBytes = receivedBytes;
    return true;
  }
}
