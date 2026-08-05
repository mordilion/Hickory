import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to this entry point in Riverpod 3.x; still the right
// tool for a single piece of simple, directly-settable UI state like the
// currently known available update.
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../update/github_release_client.dart';
import '../update/update_checker.dart';
import '../update/update_installer.dart';

const _githubOwner = 'mordilion';
const _githubRepo = 'Hickory';

final githubReleaseClientProvider = Provider<GithubReleaseClient>(
  (ref) => GithubReleaseClient(owner: _githubOwner, repo: _githubRepo),
);

/// The release asset name this platform's build publishes -- see
/// release.yml. Only meaningful on macOS/Windows; the update UI isn't shown
/// on other platforms.
String _platformAssetName() => Platform.isWindows ? 'hickory-windows.zip' : 'hickory-macos.zip';

final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(
    releaseClient: ref.watch(githubReleaseClientProvider),
    platformAssetName: _platformAssetName(),
  ),
);

final updateInstallerProvider = Provider<UpdateInstaller>((ref) => UpdateInstaller());

/// The current app version, for display in Settings.
final currentAppVersionProvider = FutureProvider<String>((ref) async {
  return (await PackageInfo.fromPlatform()).version;
});

/// The update found by either the silent startup check or the manual
/// "Check for updates" button -- null means none is currently known. Plain
/// mutable state (not code-generated) so it can be set imperatively from
/// both call sites via `.notifier.state = ...`.
final availableUpdateProvider = StateProvider<UpdateInfo?>((ref) => null);
