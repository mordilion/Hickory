import 'package:package_info_plus/package_info_plus.dart';

import 'github_release_client.dart';

/// A newer release the app can update to, with the download/checksum URLs
/// already resolved for the current platform.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    required this.checksumUrl,
    required this.size,
  });

  final String version;
  final String notes;
  final String downloadUrl;
  final String checksumUrl;
  final int size;
}

/// Compares the latest GitHub release against the running app version and
/// picks the release asset matching the current platform.
class UpdateChecker {
  UpdateChecker({required this.releaseClient, required this.platformAssetName});

  final GithubReleaseClient releaseClient;

  /// The exact asset filename this platform's build publishes (e.g.
  /// "hickory-windows.zip") -- passed in rather than detected internally so
  /// this class stays platform-agnostic and trivially testable.
  final String platformAssetName;

  /// Returns null when there's no newer release, the release has no asset
  /// (or no checksum sidecar) for this platform, or the release couldn't be
  /// fetched at all -- every one of those is "nothing to report" from the
  /// caller's point of view.
  Future<UpdateInfo?> checkForUpdate() async {
    final release = await releaseClient.fetchLatestRelease();
    if (release == null) return null;

    final currentVersion = (await PackageInfo.fromPlatform()).version;
    if (!_isNewer(release.version, currentVersion)) return null;

    final asset = _findAsset(release.assets, platformAssetName);
    if (asset == null) return null;
    final checksumAsset = _findAsset(release.assets, '$platformAssetName.sha256');
    if (checksumAsset == null) return null;

    return UpdateInfo(
      version: release.version,
      notes: release.notes,
      downloadUrl: asset.downloadUrl,
      checksumUrl: checksumAsset.downloadUrl,
      size: asset.size,
    );
  }

  GithubReleaseAsset? _findAsset(List<GithubReleaseAsset> assets, String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  /// Whole-number major.minor.patch comparison -- this project doesn't use
  /// pre-release/build-metadata suffixes, so a plain numeric compare is
  /// enough (no need for a full semver parser).
  bool _isNewer(String candidate, String current) {
    final a = _parts(candidate);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  List<int> _parts(String version) {
    final segments = version.split('.');
    return List.generate(3, (i) => i < segments.length ? int.tryParse(segments[i]) ?? 0 : 0);
  }
}
