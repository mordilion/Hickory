import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/update/github_release_client.dart';
import 'package:hickory/core/update/update_checker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockGithubReleaseClient extends Mock implements GithubReleaseClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Hickory',
      packageName: 'com.hickory.hickory',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('returns update info when the release is newer and has a matching asset', () async {
    final client = MockGithubReleaseClient();
    when(() => client.fetchLatestRelease()).thenAnswer(
      (_) async => const GithubRelease(
        version: '1.1.0',
        notes: 'Notes',
        assets: [
          GithubReleaseAsset(
            name: 'hickory-windows.zip',
            downloadUrl: 'https://example.com/a.zip',
            size: 100,
          ),
          GithubReleaseAsset(
            name: 'hickory-windows.zip.sha256',
            downloadUrl: 'https://example.com/a.sha256',
            size: 64,
          ),
        ],
      ),
    );
    final checker = UpdateChecker(releaseClient: client, platformAssetName: 'hickory-windows.zip');

    final result = await checker.checkForUpdate();

    expect(result, isNotNull);
    expect(result!.version, '1.1.0');
    expect(result.downloadUrl, 'https://example.com/a.zip');
    expect(result.checksumUrl, 'https://example.com/a.sha256');
  });

  test('returns null when the release is not newer than the current version', () async {
    final client = MockGithubReleaseClient();
    when(() => client.fetchLatestRelease()).thenAnswer(
      (_) async => const GithubRelease(
        version: '1.0.0',
        notes: '',
        assets: [GithubReleaseAsset(name: 'hickory-windows.zip', downloadUrl: '', size: 0)],
      ),
    );
    final checker = UpdateChecker(releaseClient: client, platformAssetName: 'hickory-windows.zip');

    expect(await checker.checkForUpdate(), isNull);
  });

  test('returns null when the release has no asset for this platform', () async {
    final client = MockGithubReleaseClient();
    when(() => client.fetchLatestRelease()).thenAnswer(
      (_) async => const GithubRelease(
        version: '1.1.0',
        notes: '',
        assets: [GithubReleaseAsset(name: 'hickory-macos.zip', downloadUrl: '', size: 0)],
      ),
    );
    final checker = UpdateChecker(releaseClient: client, platformAssetName: 'hickory-windows.zip');

    expect(await checker.checkForUpdate(), isNull);
  });

  test('returns null when the matching asset has no checksum sidecar', () async {
    final client = MockGithubReleaseClient();
    when(() => client.fetchLatestRelease()).thenAnswer(
      (_) async => const GithubRelease(
        version: '1.1.0',
        notes: '',
        assets: [GithubReleaseAsset(name: 'hickory-windows.zip', downloadUrl: '', size: 0)],
      ),
    );
    final checker = UpdateChecker(releaseClient: client, platformAssetName: 'hickory-windows.zip');

    expect(await checker.checkForUpdate(), isNull);
  });

  test('returns null when fetchLatestRelease itself returns null', () async {
    final client = MockGithubReleaseClient();
    when(() => client.fetchLatestRelease()).thenAnswer((_) async => null);
    final checker = UpdateChecker(releaseClient: client, platformAssetName: 'hickory-windows.zip');

    expect(await checker.checkForUpdate(), isNull);
  });

  test('a higher patch, minor, or major version is each detected as newer', () async {
    final client = MockGithubReleaseClient();
    final checker = UpdateChecker(releaseClient: client, platformAssetName: 'hickory-windows.zip');

    for (final newerVersion in ['1.0.1', '1.1.0', '2.0.0']) {
      when(() => client.fetchLatestRelease()).thenAnswer(
        (_) async => GithubRelease(
          version: newerVersion,
          notes: '',
          assets: const [
            GithubReleaseAsset(name: 'hickory-windows.zip', downloadUrl: 'x', size: 0),
            GithubReleaseAsset(name: 'hickory-windows.zip.sha256', downloadUrl: 'y', size: 0),
          ],
        ),
      );
      final result = await checker.checkForUpdate();
      expect(result, isNotNull, reason: '$newerVersion should be detected as newer than 1.0.0');
    }
  });
}
