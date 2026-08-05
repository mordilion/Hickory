import 'dart:convert';

import 'package:http/http.dart' as http;

/// One asset attached to a GitHub release (e.g. a platform zip).
class GithubReleaseAsset {
  const GithubReleaseAsset({required this.name, required this.downloadUrl, required this.size});

  final String name;
  final String downloadUrl;
  final int size;
}

/// The latest published release of a repository, as returned by GitHub's
/// public Releases API.
class GithubRelease {
  const GithubRelease({required this.version, required this.notes, required this.assets});

  /// The release's tag with a leading "v" stripped (e.g. "1.2.3" for tag
  /// "v1.2.3"), matching PackageInfo.version's format.
  final String version;
  final String notes;
  final List<GithubReleaseAsset> assets;
}

/// Reads the latest release from a public GitHub repository. Unauthenticated
/// -- GitHub allows 60 requests/hour/IP for unauthenticated API calls, far
/// more than an app that checks once per startup needs.
class GithubReleaseClient {
  GithubReleaseClient({required this.owner, required this.repo, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final String owner;
  final String repo;
  final http.Client _httpClient;

  /// Returns null if the repository has no releases yet (404), or the
  /// response can't be parsed -- callers treat "can't determine the latest
  /// release" the same as "nothing to report", never an error the user
  /// didn't ask for.
  Future<GithubRelease?> fetchLatestRelease() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = decoded['tag_name'] as String;
      final rawAssets = decoded['assets'] as List<dynamic>? ?? const [];
      return GithubRelease(
        version: tagName.startsWith('v') ? tagName.substring(1) : tagName,
        notes: (decoded['body'] as String?) ?? '',
        assets: [
          for (final asset in rawAssets)
            GithubReleaseAsset(
              name: (asset as Map<String, dynamic>)['name'] as String,
              downloadUrl: asset['browser_download_url'] as String,
              size: (asset['size'] as num).toInt(),
            ),
        ],
      );
    } on Object {
      return null;
    }
  }
}
