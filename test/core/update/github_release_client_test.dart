import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/update/github_release_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchLatestRelease parses tag, notes, and assets', () async {
    final client = GithubReleaseClient(
      owner: 'mordilion',
      repo: 'Hickory',
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/mordilion/Hickory/releases/latest',
        );
        // GitHub rejects requests with no User-Agent header (403) --
        // regression check for that requirement.
        expect(request.headers['User-Agent'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.2.3',
            'body': 'Release notes here',
            'assets': [
              {
                'name': 'hickory-windows.zip',
                'browser_download_url': 'https://example.com/hickory-windows.zip',
                'size': 12345,
              },
            ],
          }),
          200,
        );
      }),
    );

    final release = await client.fetchLatestRelease();

    expect(release, isNotNull);
    expect(release!.version, '1.2.3');
    expect(release.notes, 'Release notes here');
    expect(release.assets, hasLength(1));
    expect(release.assets.single.name, 'hickory-windows.zip');
    expect(release.assets.single.downloadUrl, 'https://example.com/hickory-windows.zip');
    expect(release.assets.single.size, 12345);
  });

  test('fetchLatestRelease returns null on a 404 (no releases yet)', () async {
    final client = GithubReleaseClient(
      owner: 'mordilion',
      repo: 'Hickory',
      httpClient: MockClient((request) async => http.Response('Not Found', 404)),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('fetchLatestRelease returns null instead of throwing on malformed JSON', () async {
    final client = GithubReleaseClient(
      owner: 'mordilion',
      repo: 'Hickory',
      httpClient: MockClient((request) async => http.Response('not json', 200)),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a tag without a leading v is used as-is', () async {
    final client = GithubReleaseClient(
      owner: 'mordilion',
      repo: 'Hickory',
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'tag_name': '1.2.3', 'body': '', 'assets': []}), 200);
      }),
    );

    final release = await client.fetchLatestRelease();
    expect(release!.version, '1.2.3');
  });
}
