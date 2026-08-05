# GitHub Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish real GitHub Releases from version tags, and let Hickory check for
a newer release, then download/verify/install/relaunch itself on macOS/Windows.

**Architecture:** A new `release.yml` CI workflow (tag push → build → publish with
checksums). In-app: a small hand-rolled `GithubReleaseClient` (GitHub's public
Releases API, unauthenticated) → `UpdateChecker` (version compare + platform-asset
match) → `UpdateInstaller`, split into a fully testable, non-destructive
`prepareUpdate` (download, checksum-verify, extract) and an untestable
`quitAndSwap` (writes a detached relaunch script, quits through the app's existing
quit path, and only the script — after this process has fully exited — replaces
the install directory via a rename-swap).

**Tech Stack:** Flutter, `http` (existing), `archive` + `crypto` (new), GitHub
Actions, `package_info_plus` (existing).

**Full design:** `docs/superpowers/specs/2026-08-05-github-auto-update-design.md`

## Global Constraints

- English only in code, comments, commit messages, and workflow YAML.
- The updater (check + install) only activates on macOS/Windows
  (`Platform.isMacOS || Platform.isWindows`) — iOS/Android are untouched by this
  plan entirely, and `release.yml` only builds/publishes macOS/Windows, per the
  approved design's explicit scope decision.
- **No third-party updater package** (`auto_updater` etc.) — a small hand-rolled
  client against GitHub's public Releases API, matching this codebase's existing
  pattern of purpose-built HTTP clients (`HttpJiraClient`, `HttpPersonioClient`).
- **Deviation from the approved design, flagged here rather than silently made:**
  the design's Section 5 describes an app-shell-level banner in addition to the
  Settings card. Implementing that would require either exposing `NavShell`'s
  internal tab index externally (it's deliberately decoupled — see its own doc
  comment) or duplicating the install-trigger/progress logic in a second widget.
  This plan drops the separate banner: `availableUpdateProvider` is still set by
  both the silent startup check and the manual button, so an update found at
  startup is visible the next time the user opens Settings — just not as an
  interrupt on whatever screen they're currently on. If this trade-off isn't
  acceptable, say so before Task 5 and the plan can be revised.
- New dependencies: run `flutter pub add archive crypto` (Task 4) rather than
  hand-writing version numbers into `pubspec.yaml` — let the tool resolve current
  compatible versions, per this project's "don't introduce fixed versions by hand"
  convention.
- `archive` package API: this plan calls `extractFileToDisk(inputPath,
  outputPath)` from `package:archive/archive_io.dart` — `[inferred from the
  package's documented usage, not re-verified against the exact version `flutter
  pub add` resolves]`. If the resolved version's signature differs, Task 4's
  Step 3 is the only place that needs adjusting; everything around it (the
  checksum verification, the executable sanity-check, the tests) is unaffected by
  the exact extraction call shape.
- GitHub Actions in `release.yml` must be **pinned by commit SHA with a version
  comment**, matching every existing action reference in `build.yml` — Task 3
  names two actions (`actions/download-artifact`, `softprops/action-gh-release`)
  whose exact current SHA this plan does not fabricate; resolve the real SHA for
  each action's current stable release tag before finalizing the workflow file
  (e.g. via the GitHub UI's "Use latest version" suggestion on the actions
  marketplace page, or `gh api repos/<owner>/<repo>/git/refs/tags/<tag>`).
- The quit step reuses `stopPausedEntryOnQuit` (from `lib/core/window/quit_behavior.dart`)
  and `windowManager.destroy()` **directly** — not through `WindowTrayController`,
  which isn't wired into Riverpod anywhere. A running (non-paused) time entry is
  already designed to survive an app restart unmodified (see
  `quit_behavior.dart`'s own doc comment); the update-triggered restart behaves
  exactly like any other quit-and-relaunch.
- `UpdateInstaller.quitAndSwap` and the relaunch scripts it writes are **not**
  unit-testable (everything they do only happens after this process has fully
  exited) — Task 4's test file only covers `prepareUpdate`. The implementation
  plan calls out real-machine manual verification as a required step, the same
  way the `resizable-window` plan flagged `WindowTrayController`'s real-window
  behavior as manual-only.
- Cutting an actual release (bumping `pubspec.yaml`'s version, moving
  `CHANGELOG.md`'s `[Unreleased]` section, tagging, pushing the tag) is a manual
  checklist this plan does not automate.

---

### Task 1: `GithubReleaseClient`

**Files:**
- Create: `lib/core/update/github_release_client.dart`
- Test: `test/core/update/github_release_client_test.dart`

**Interfaces:**
- Produces: `GithubReleaseAsset({required name, required downloadUrl, required
  size})`. `GithubRelease({required version, required notes, required assets})` —
  `version` has any leading `v` already stripped. `GithubReleaseClient({required
  owner, required repo, http.Client? httpClient})` with `Future<GithubRelease?>
  fetchLatestRelease()` — null on a 404 or any parse failure, never throws.

- [ ] **Step 1: Write the failing test**

Create `test/core/update/github_release_client_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/update/github_release_client_test.dart`
Expected: FAIL — `package:hickory/core/update/github_release_client.dart` doesn't exist.

- [ ] **Step 3: Implement `GithubReleaseClient`**

Create `lib/core/update/github_release_client.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/update/github_release_client_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/github_release_client.dart test/core/update/github_release_client_test.dart
git commit -m "feat(update): add GithubReleaseClient for the public Releases API"
```

---

### Task 2: `UpdateChecker`

**Files:**
- Create: `lib/core/update/update_checker.dart`
- Test: `test/core/update/update_checker_test.dart`

**Interfaces:**
- Consumes: `GithubReleaseClient.fetchLatestRelease()`, `GithubRelease`,
  `GithubReleaseAsset` (Task 1, exact shapes above).
- Produces: `UpdateInfo({required version, required notes, required downloadUrl,
  required checksumUrl, required size})`. `UpdateChecker({required
  GithubReleaseClient releaseClient, required String platformAssetName})` with
  `Future<UpdateInfo?> checkForUpdate()` — null when there's no newer release, no
  matching platform asset, no checksum sidecar asset, or the release fetch itself
  failed.

- [ ] **Step 1: Write the failing test**

Create `test/core/update/update_checker_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/update/update_checker_test.dart`
Expected: FAIL — `UpdateChecker` doesn't exist.

- [ ] **Step 3: Implement `UpdateChecker`**

Create `lib/core/update/update_checker.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/update/update_checker_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/update_checker.dart test/core/update/update_checker_test.dart
git commit -m "feat(update): add UpdateChecker version/asset matching"
```

---

### Task 3: Release CI workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Produces: on pushing a `v*` tag, a GitHub Release named after the tag, with
  `hickory-macos.zip`, `hickory-macos.zip.sha256`, `hickory-windows.zip`,
  `hickory-windows.zip.sha256` attached — the exact 4 filenames Task 2's
  `UpdateChecker` (via `platformAssetName`/`$platformAssetName.sha256`) expects.

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/release.yml`. **Before committing**, resolve the actual
current commit SHA for `actions/download-artifact`'s latest stable tag and for
`softprops/action-gh-release`'s latest stable tag (see this plan's Global
Constraints for how) and substitute them for the `<RESOLVE-SHA>` placeholders
below — do not leave them unresolved or guess a SHA:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  verify-version:
    name: Verify pubspec version matches tag
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - name: Compare pubspec.yaml version to the pushed tag
        run: |
          TAG_VERSION="${GITHUB_REF_NAME#v}"
          PUBSPEC_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d'+' -f1)
          if [ "$TAG_VERSION" != "$PUBSPEC_VERSION" ]; then
            echo "Tag $GITHUB_REF_NAME (version $TAG_VERSION) does not match pubspec.yaml version $PUBSPEC_VERSION"
            exit 1
          fi

  build-macos:
    name: Build macOS
    needs: verify-version
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - uses: subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2.23.0
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter build macos --release
      - name: Package hickory.app
        working-directory: build/macos/Build/Products/Release
        run: ditto -c -k --sequesterRsrc --keepParent hickory.app hickory-macos.zip
      - name: Compute checksum
        working-directory: build/macos/Build/Products/Release
        run: shasum -a 256 hickory-macos.zip | cut -d' ' -f1 > hickory-macos.zip.sha256
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: hickory-macos-release
          path: |
            build/macos/Build/Products/Release/hickory-macos.zip
            build/macos/Build/Products/Release/hickory-macos.zip.sha256
          if-no-files-found: error

  build-windows:
    name: Build Windows
    needs: verify-version
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - uses: subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2.23.0
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter build windows --release
      - name: Package hickory.exe
        run: Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath build/windows/x64/runner/Release/hickory-windows.zip
      - name: Compute checksum
        run: (Get-FileHash -Algorithm SHA256 build/windows/x64/runner/Release/hickory-windows.zip).Hash.ToLower() | Set-Content -NoNewline build/windows/x64/runner/Release/hickory-windows.zip.sha256
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: hickory-windows-release
          path: |
            build/windows/x64/runner/Release/hickory-windows.zip
            build/windows/x64/runner/Release/hickory-windows.zip.sha256
          if-no-files-found: error

  publish:
    name: Publish GitHub Release
    needs: [build-macos, build-windows]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - uses: actions/download-artifact@<RESOLVE-SHA> # pin to the current stable tag
        with:
          name: hickory-macos-release
          path: release-assets
      - uses: actions/download-artifact@<RESOLVE-SHA> # pin to the current stable tag
        with:
          name: hickory-windows-release
          path: release-assets
      - name: Extract release notes from CHANGELOG.md
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          awk -v ver="$VERSION" '
            BEGIN { found=0 }
            /^## \[/ {
              if (found) exit
              if ($0 ~ "\\[" ver "\\]") { found=1; next }
            }
            found { print }
          ' CHANGELOG.md > release_notes.md
      - uses: softprops/action-gh-release@<RESOLVE-SHA> # pin to the current stable tag
        with:
          name: ${{ github.ref_name }}
          body_path: release_notes.md
          files: release-assets/*
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
(or any available YAML linter) to catch structural errors before pushing — this
workflow can't be exercised by `flutter test`, so this is the only automatable
check available before a real tag push.
Expected: no error.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow that publishes tagged builds to GitHub Releases"
```

- [ ] **Step 4: Manual verification (not automatable — note for the user)**

This workflow only runs on a real tag push and cannot be exercised by CI-on-PR or
`flutter test`. Before relying on it: bump `pubspec.yaml`'s version, move
`CHANGELOG.md`'s `[Unreleased]` section under the matching version heading, commit,
tag (`git tag vX.Y.Z`), push the tag, and confirm in the Actions tab that all four
jobs succeed and the resulting GitHub Release has exactly the 4 expected files
attached with non-empty checksums.

---

### Task 4: `UpdateInstaller`

**Files:**
- Create: `lib/core/update/update_installer.dart`
- Test: `test/core/update/update_installer_test.dart`

**Interfaces:**
- Consumes: `UpdateInfo` (Task 2), `stopPausedEntryOnQuit(AppDatabase, SyncedWrites)`
  (existing, `lib/core/window/quit_behavior.dart`), `windowManager.destroy()`
  (existing, `package:window_manager/window_manager.dart`).
- Produces: `UpdateInstallException(String message)`. `UpdateInstaller({http.Client?
  httpClient})` with `Future<Directory> prepareUpdate(UpdateInfo update)` (throws
  `UpdateInstallException` on failure; fully non-destructive, unit-tested) and
  `Future<void> quitAndSwap(Directory extractedTopLevel, {required AppDatabase db,
  required SyncedWrites writes})` (not unit-tested — see Global Constraints).

- [ ] **Step 1: Add the new dependencies**

Run: `flutter pub add archive crypto`
Expected: `pubspec.yaml`'s `dependencies:` section gains `archive: ^<resolved>`
and `crypto: ^<resolved>` lines (exact versions chosen by the tool, not hand-typed).

- [ ] **Step 2: Write the failing test**

Create `test/core/update/update_installer_test.dart`:

```dart
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/update/update_checker.dart';
import 'package:hickory/core/update/update_installer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// Builds a zip containing a single top-level "Hickory" directory with a
  /// fake executable at the platform-appropriate relative path -- the same
  /// shape ditto/Compress-Archive produce in CI, so prepareUpdate's
  /// extraction/executable-lookup logic can be tested without a real
  /// release artifact.
  List<int> buildFixtureZip({bool withExecutable = true}) {
    final relativePath = Platform.isWindows ? 'hickory.exe' : 'Contents/MacOS/hickory';
    final archive = Archive();
    if (withExecutable) {
      final content = 'fake executable'.codeUnits;
      archive.addFile(ArchiveFile('Hickory/$relativePath', content.length, content));
    } else {
      final content = 'unrelated file'.codeUnits;
      archive.addFile(ArchiveFile('Hickory/readme.txt', content.length, content));
    }
    return ZipEncoder().encode(archive)!;
  }

  const update = UpdateInfo(
    version: '9.9.9',
    notes: '',
    downloadUrl: 'https://example.com/update.zip',
    checksumUrl: 'https://example.com/update.zip.sha256',
    size: 0,
  );

  test('prepareUpdate returns the extracted top-level directory on success', () async {
    final zipBytes = buildFixtureZip();
    final checksum = sha256.convert(zipBytes).toString();
    final installer = UpdateInstaller(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) return http.Response(checksum, 200);
        return http.Response.bytes(zipBytes, 200);
      }),
    );

    final topLevel = await installer.prepareUpdate(update);

    expect(topLevel.existsSync(), isTrue);
    expect(topLevel.path, endsWith('Hickory'));
    addTearDown(() {
      final workDir = topLevel.parent.parent;
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    });
  });

  test('prepareUpdate throws on a checksum mismatch', () async {
    final zipBytes = buildFixtureZip();
    final installer = UpdateInstaller(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) return http.Response('0' * 64, 200);
        return http.Response.bytes(zipBytes, 200);
      }),
    );

    expect(() => installer.prepareUpdate(update), throwsA(isA<UpdateInstallException>()));
  });

  test('prepareUpdate throws when the archive has no executable at the expected path', () async {
    final zipBytes = buildFixtureZip(withExecutable: false);
    final checksum = sha256.convert(zipBytes).toString();
    final installer = UpdateInstaller(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) return http.Response(checksum, 200);
        return http.Response.bytes(zipBytes, 200);
      }),
    );

    expect(() => installer.prepareUpdate(update), throwsA(isA<UpdateInstallException>()));
  });

  test('prepareUpdate throws when the download itself fails', () async {
    final installer = UpdateInstaller(
      httpClient: MockClient((request) async => http.Response('', 500)),
    );

    expect(() => installer.prepareUpdate(update), throwsA(isA<UpdateInstallException>()));
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/update/update_installer_test.dart`
Expected: FAIL — `UpdateInstaller` doesn't exist.

- [ ] **Step 4: Implement `UpdateInstaller`**

Create `lib/core/update/update_installer.dart`. Verify `extractFileToDisk`'s exact
signature against the version `flutter pub add archive` resolved (see Global
Constraints) before treating this file as final:

```dart
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart';
import '../window/quit_behavior.dart';
import 'update_checker.dart';

/// Raised for any failure in [UpdateInstaller.prepareUpdate] -- carries a
/// caller-safe message suitable for the Settings UI.
class UpdateInstallException implements Exception {
  UpdateInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads, verifies, extracts, and installs an [UpdateInfo] on macOS/
/// Windows, then relaunches. See
/// docs/superpowers/specs/2026-08-05-github-auto-update-design.md section 4
/// for why the work is split this way: [prepareUpdate] is entirely
/// non-destructive and can fail safely with the app still running; only
/// [quitAndSwap]'s detached script touches the real install, and only after
/// this process has fully exited.
class UpdateInstaller {
  UpdateInstaller({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Downloads, verifies, and extracts [update], returning the archive's
  /// single top-level directory (the install root on Windows, the .app
  /// bundle on macOS).
  Future<Directory> prepareUpdate(UpdateInfo update) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      throw UpdateInstallException('Automatic updates are only supported on macOS and Windows.');
    }

    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(
      p.join(tempDir.path, 'hickory_update_${DateTime.now().millisecondsSinceEpoch}'),
    );
    await workDir.create(recursive: true);

    final zipFile = File(p.join(workDir.path, 'update.zip'));
    await _downloadToFile(update.downloadUrl, zipFile);

    final expectedChecksum = (await _downloadString(update.checksumUrl)).trim().toLowerCase();
    final actualChecksum = sha256.convert(await zipFile.readAsBytes()).toString();
    if (actualChecksum != expectedChecksum) {
      throw UpdateInstallException('Downloaded update failed checksum verification.');
    }

    final extractedDir = Directory(p.join(workDir.path, 'extracted'));
    await extractedDir.create(recursive: true);
    extractFileToDisk(zipFile.path, extractedDir.path);

    final topLevel = _firstSubdirectory(extractedDir);
    if (topLevel == null) {
      throw UpdateInstallException('Downloaded update archive has an unexpected layout.');
    }
    final executable = _executableInside(topLevel);
    if (!await executable.exists()) {
      throw UpdateInstallException('Downloaded update is missing its executable.');
    }
    return topLevel;
  }

  /// Writes and launches the detached relaunch script, then quits through
  /// the same path the tray menu's "Beenden" already uses (see
  /// quit_behavior.dart) so a paused entry is finalized exactly like any
  /// other quit. NOT unit-testable -- everything past this point only
  /// happens after this process has fully exited; see this feature's
  /// implementation plan for the required manual verification.
  Future<void> quitAndSwap(
    Directory extractedTopLevel, {
    required AppDatabase db,
    required SyncedWrites writes,
  }) async {
    final installDir = _currentInstallDir();
    final scriptPath = await _writeRelaunchScript(
      installDir: installDir,
      extractedTopLevel: extractedTopLevel,
      currentPid: pid,
    );
    await _launchDetached(scriptPath);

    await stopPausedEntryOnQuit(db, writes);
    await windowManager.destroy();
  }

  Future<void> _downloadToFile(String url, File file) async {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw UpdateInstallException('Failed to download update (HTTP ${response.statusCode}).');
    }
    await file.writeAsBytes(response.bodyBytes);
  }

  Future<String> _downloadString(String url) async {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw UpdateInstallException(
        'Failed to download update checksum (HTTP ${response.statusCode}).',
      );
    }
    return response.body;
  }

  /// The zip's single top-level directory -- matches exactly what
  /// ditto/Compress-Archive produced in CI. Returns null if the archive
  /// doesn't have that shape.
  Directory? _firstSubdirectory(Directory parent) {
    for (final entity in parent.listSync()) {
      if (entity is Directory) return entity;
    }
    return null;
  }

  /// The directory containing the running app's files -- on Windows, the
  /// folder holding hickory.exe and its data/ folder (exactly what
  /// build.yml/release.yml zip up); on macOS, the .app bundle root, three
  /// path segments above Contents/MacOS/<executable> -- a stable,
  /// well-known bundle-layout convention.
  Directory _currentInstallDir() {
    final executable = File(Platform.resolvedExecutable);
    return Platform.isWindows ? executable.parent : executable.parent.parent.parent;
  }

  File _executableInside(Directory topLevel) {
    return Platform.isWindows
        ? File(p.join(topLevel.path, 'hickory.exe'))
        : File(p.join(topLevel.path, 'Contents', 'MacOS', 'hickory'));
  }

  Future<String> _writeRelaunchScript({
    required Directory installDir,
    required Directory extractedTopLevel,
    required int currentPid,
  }) async {
    final tempDir = await getTemporaryDirectory();

    if (Platform.isWindows) {
      final scriptFile = File(p.join(tempDir.path, 'hickory_update.ps1'));
      final exePath = p.join(installDir.path, 'hickory.exe');
      await scriptFile.writeAsString('''
Wait-Process -Id $currentPid -Timeout 30 -ErrorAction SilentlyContinue
\$backup = "${installDir.path}_old"
if (Test-Path \$backup) { Remove-Item \$backup -Recurse -Force }
Rename-Item -Path "${installDir.path}" -NewName (Split-Path \$backup -Leaf)
Move-Item -Path "${extractedTopLevel.path}" -Destination "${installDir.path}"
Remove-Item \$backup -Recurse -Force
Start-Process -FilePath "$exePath"
Remove-Item -Path \$MyInvocation.MyCommand.Path -Force
''');
      return scriptFile.path;
    }

    final scriptFile = File(p.join(tempDir.path, 'hickory_update.sh'));
    await scriptFile.writeAsString('''
#!/bin/sh
while kill -0 $currentPid 2>/dev/null; do sleep 0.5; done
BACKUP="${installDir.path}_old"
rm -rf "\$BACKUP"
mv "${installDir.path}" "\$BACKUP"
mv "${extractedTopLevel.path}" "${installDir.path}"
rm -rf "\$BACKUP"
open "${installDir.path}"
rm -- "\$0"
''');
    await Process.run('chmod', ['+x', scriptFile.path]);
    return scriptFile.path;
  }

  Future<void> _launchDetached(String scriptPath) {
    if (Platform.isWindows) {
      return Process.start(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-File', scriptPath],
        mode: ProcessStartMode.detached,
      );
    }
    return Process.start('/bin/sh', [scriptPath], mode: ProcessStartMode.detached);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/update/update_installer_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/update/update_installer.dart test/core/update/update_installer_test.dart
git commit -m "feat(update): add UpdateInstaller download/verify/extract/swap"
```

---

### Task 5: Providers, Settings UI, and startup check

**Files:**
- Create: `lib/core/di/update_providers.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/main.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`,
  `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`

**Interfaces:**
- Consumes: `GithubReleaseClient` (Task 1), `UpdateChecker`/`UpdateInfo` (Task 2),
  `UpdateInstaller` (Task 4).
- Produces: `githubReleaseClientProvider`, `updateCheckerProvider`,
  `updateInstallerProvider`, `currentAppVersionProvider` (`FutureProvider<String>`),
  `availableUpdateProvider` (`StateProvider<UpdateInfo?>`) — no other file depends
  on these (final task). No new test file: this task is pure UI/wiring, matching
  this codebase's existing precedent of not widget-testing Settings/Sync screen
  sections (see the Personio design's identical reasoning) — verify via `flutter
  analyze` + the full `flutter test` suite.

- [ ] **Step 1: Add the new ARB keys to all 6 locale files**

Edit `lib/l10n/app_de.arb`. Find:

```json
  "settingsTimeFormat": "Zeitformat",
  "syncTitle": "Sync-Einstellungen",
```

Replace it with:

```json
  "settingsTimeFormat": "Zeitformat",
  "settingsUpdateTitle": "Updates",
  "settingsUpdateCurrentVersion": "Aktuelle Version: {version}",
  "settingsUpdateCheckButton": "Nach Updates suchen",
  "settingsUpdateChecking": "Suche nach Updates...",
  "settingsUpdateUpToDate": "Du hast die neueste Version.",
  "settingsUpdateCheckError": "Update-Prüfung fehlgeschlagen. Bitte versuche es später erneut.",
  "settingsUpdateAvailable": "Version {version} ist verfügbar.",
  "settingsUpdateInstallButton": "Jetzt installieren",
  "settingsUpdateInstalling": "Update wird installiert...",
  "settingsUpdateInstallError": "Installation fehlgeschlagen. Bitte versuche es erneut oder lade die neue Version manuell von GitHub herunter.",
  "syncTitle": "Sync-Einstellungen",
```

Edit `lib/l10n/app_en.arb`. Find:

```json
  "settingsTimeFormat": "Time format",
  "syncTitle": "Sync settings",
```

Replace it with:

```json
  "settingsTimeFormat": "Time format",
  "settingsUpdateTitle": "Updates",
  "settingsUpdateCurrentVersion": "Current version: {version}",
  "settingsUpdateCheckButton": "Check for updates",
  "settingsUpdateChecking": "Checking for updates...",
  "settingsUpdateUpToDate": "You're on the latest version.",
  "settingsUpdateCheckError": "Update check failed. Please try again later.",
  "settingsUpdateAvailable": "Version {version} is available.",
  "settingsUpdateInstallButton": "Install now",
  "settingsUpdateInstalling": "Installing update...",
  "settingsUpdateInstallError": "Installation failed. Please try again or download the new version manually from GitHub.",
  "syncTitle": "Sync settings",
```

Edit `lib/l10n/app_es.arb`. Find:

```json
  "settingsTimeFormat": "Formato de hora",
  "syncTitle": "Ajustes de sincronización",
```

Replace it with:

```json
  "settingsTimeFormat": "Formato de hora",
  "settingsUpdateTitle": "Actualizaciones",
  "settingsUpdateCurrentVersion": "Versión actual: {version}",
  "settingsUpdateCheckButton": "Buscar actualizaciones",
  "settingsUpdateChecking": "Buscando actualizaciones...",
  "settingsUpdateUpToDate": "Tienes la última versión.",
  "settingsUpdateCheckError": "La comprobación de actualizaciones falló. Inténtalo de nuevo más tarde.",
  "settingsUpdateAvailable": "La versión {version} está disponible.",
  "settingsUpdateInstallButton": "Instalar ahora",
  "settingsUpdateInstalling": "Instalando actualización...",
  "settingsUpdateInstallError": "La instalación falló. Inténtalo de nuevo o descarga la nueva versión manualmente desde GitHub.",
  "syncTitle": "Ajustes de sincronización",
```

Edit `lib/l10n/app_fr.arb`. Find:

```json
  "settingsTimeFormat": "Format d'heure",
  "syncTitle": "Paramètres de synchronisation",
```

Replace it with:

```json
  "settingsTimeFormat": "Format d'heure",
  "settingsUpdateTitle": "Mises à jour",
  "settingsUpdateCurrentVersion": "Version actuelle : {version}",
  "settingsUpdateCheckButton": "Rechercher des mises à jour",
  "settingsUpdateChecking": "Recherche de mises à jour...",
  "settingsUpdateUpToDate": "Vous avez la dernière version.",
  "settingsUpdateCheckError": "La vérification des mises à jour a échoué. Veuillez réessayer plus tard.",
  "settingsUpdateAvailable": "La version {version} est disponible.",
  "settingsUpdateInstallButton": "Installer maintenant",
  "settingsUpdateInstalling": "Installation de la mise à jour...",
  "settingsUpdateInstallError": "L'installation a échoué. Veuillez réessayer ou télécharger la nouvelle version manuellement depuis GitHub.",
  "syncTitle": "Paramètres de synchronisation",
```

Edit `lib/l10n/app_it.arb`. Find:

```json
  "settingsTimeFormat": "Formato ora",
  "syncTitle": "Impostazioni di sincronizzazione",
```

Replace it with:

```json
  "settingsTimeFormat": "Formato ora",
  "settingsUpdateTitle": "Aggiornamenti",
  "settingsUpdateCurrentVersion": "Versione attuale: {version}",
  "settingsUpdateCheckButton": "Cerca aggiornamenti",
  "settingsUpdateChecking": "Ricerca aggiornamenti...",
  "settingsUpdateUpToDate": "Hai l'ultima versione.",
  "settingsUpdateCheckError": "Controllo aggiornamenti non riuscito. Riprova più tardi.",
  "settingsUpdateAvailable": "La versione {version} è disponibile.",
  "settingsUpdateInstallButton": "Installa ora",
  "settingsUpdateInstalling": "Installazione aggiornamento...",
  "settingsUpdateInstallError": "Installazione non riuscita. Riprova o scarica la nuova versione manualmente da GitHub.",
  "syncTitle": "Impostazioni di sincronizzazione",
```

Edit `lib/l10n/app_nl.arb`. Find:

```json
  "settingsTimeFormat": "Tijdnotatie",
  "syncTitle": "Synchronisatie-instellingen",
```

Replace it with:

```json
  "settingsTimeFormat": "Tijdnotatie",
  "settingsUpdateTitle": "Updates",
  "settingsUpdateCurrentVersion": "Huidige versie: {version}",
  "settingsUpdateCheckButton": "Naar updates zoeken",
  "settingsUpdateChecking": "Zoeken naar updates...",
  "settingsUpdateUpToDate": "Je hebt de nieuwste versie.",
  "settingsUpdateCheckError": "Update-controle mislukt. Probeer het later opnieuw.",
  "settingsUpdateAvailable": "Versie {version} is beschikbaar.",
  "settingsUpdateInstallButton": "Nu installeren",
  "settingsUpdateInstalling": "Update wordt geïnstalleerd...",
  "settingsUpdateInstallError": "Installatie mislukt. Probeer het opnieuw of download de nieuwe versie handmatig van GitHub.",
  "syncTitle": "Synchronisatie-instellingen",
```

- [ ] **Step 2: Verify key parity and regenerate localizations**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

Run: `flutter gen-l10n`
Expected: completes with no errors; the 10 new getters appear in
`lib/l10n/app_localizations*.dart`.

- [ ] **Step 3: Create the providers**

Create `lib/core/di/update_providers.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
```

- [ ] **Step 4: Wire the silent startup check**

Edit `lib/main.dart`. Find:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/di/database_provider.dart';
import 'core/di/locale_provider.dart';
import 'core/di/sync_providers.dart';
import 'core/locale/locale_resolution.dart';
import 'core/theme/app_text_theme.dart';
import 'core/window/quit_behavior.dart';
import 'core/window/window_tray_controller.dart';
import 'l10n/app_localizations.dart';
```

Replace it with:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/autostart_service.dart';
import 'core/di/database_provider.dart';
import 'core/di/locale_provider.dart';
import 'core/di/sync_providers.dart';
import 'core/di/update_providers.dart';
import 'core/locale/locale_resolution.dart';
import 'core/theme/app_text_theme.dart';
import 'core/window/quit_behavior.dart';
import 'core/window/window_tray_controller.dart';
import 'l10n/app_localizations.dart';
```

Find:

```dart
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );
}
```

Replace it with:

```dart
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HickoryApp(scaffoldMessengerKey: windowTrayController.scaffoldMessengerKey),
    ),
  );

  // Silent by design: only ever sets availableUpdateProvider when a real
  // update is found (Settings surfaces it) -- never shown as an error or
  // any other visible feedback if the check itself fails.
  if (Platform.isMacOS || Platform.isWindows) {
    unawaited(
      container.read(updateCheckerProvider).checkForUpdate().then((update) {
        if (update != null) {
          container.read(availableUpdateProvider.notifier).state = update;
        }
      }),
    );
  }
}
```

- [ ] **Step 5: Add the Settings "Updates" card**

Edit `lib/features/settings/settings_screen.dart`. Find:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_editor.dart';
import 'break_rule_tiers_editor.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _autostartEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAutostartState();
  }
```

Replace it with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/database_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/update/update_checker.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_editor.dart';
import 'break_rule_tiers_editor.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _autostartEnabled = false;
  bool _updateBusy = false;
  String? _updateStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadAutostartState();
  }
```

Find:

```dart
  Future<void> _setTimeFormat(TimeFormatStyle style) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(timeFormat: style.wireName);
  }

  @override
  Widget build(BuildContext context) {
```

Replace it with:

```dart
  Future<void> _setTimeFormat(TimeFormatStyle style) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(timeFormat: style.wireName);
  }

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _updateBusy = true;
      _updateStatusMessage = l10n.settingsUpdateChecking;
    });
    try {
      final checker = ref.read(updateCheckerProvider);
      final update = await checker.checkForUpdate();
      ref.read(availableUpdateProvider.notifier).state = update;
      if (!mounted) return;
      setState(() => _updateStatusMessage = update == null ? l10n.settingsUpdateUpToDate : null);
    } catch (_) {
      if (mounted) setState(() => _updateStatusMessage = l10n.settingsUpdateCheckError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Future<void> _installUpdate(UpdateInfo update) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _updateBusy = true;
      _updateStatusMessage = l10n.settingsUpdateInstalling;
    });
    try {
      final installer = ref.read(updateInstallerProvider);
      final extracted = await installer.prepareUpdate(update);
      final db = ref.read(appDatabaseProvider);
      final writes = await ref.read(syncedWritesProvider.future);
      await installer.quitAndSwap(extracted, db: db, writes: writes);
    } catch (_) {
      if (mounted) setState(() => _updateStatusMessage = l10n.settingsUpdateInstallError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
```

Find:

```dart
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: ProjectsEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

Replace it with:

```dart
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: ProjectsEditor(),
            ),
          ),
          if (Platform.isMacOS || Platform.isWindows) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settingsUpdateTitle, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    currentVersionAsync.when(
                      data: (version) => Text(
                        l10n.settingsUpdateCurrentVersion(version),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                    if (_updateStatusMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_updateStatusMessage!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 16),
                    if (availableUpdate != null) ...[
                      Text(l10n.settingsUpdateAvailable(availableUpdate.version)),
                      if (availableUpdate.notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(availableUpdate.notes, style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _updateBusy ? null : () => _installUpdate(availableUpdate),
                        child: Text(l10n.settingsUpdateInstallButton),
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: _updateBusy ? null : _checkForUpdates,
                        child: Text(l10n.settingsUpdateCheckButton),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

Find (the `build` method's opening, to add the two new `ref.watch` calls):

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final now = DateTime.now();
```

Replace it with:

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final now = DateTime.now();
    final currentVersionAsync = ref.watch(currentAppVersionProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);
```

- [ ] **Step 6: Verify**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: PASS (all tests — this task adds no new test file, but the full suite
must still show no regressions).

- [ ] **Step 7: Commit**

```bash
git add lib/core/di/update_providers.dart lib/main.dart lib/features/settings/settings_screen.dart lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_es.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_it.dart lib/l10n/app_localizations_nl.dart
git commit -m "feat(update): add update providers, Settings UI, and startup check"
```

- [ ] **Step 8: Manual verification (not automatable — note for the user)**

`UpdateInstaller.quitAndSwap` and its relaunch scripts can only be verified on a
real machine, against a real published release (Task 3's manual step). Before
relying on this feature: publish two tagged releases (an older "current" build the
user has installed, and a newer one), run the older build, use Settings → "Check
for updates" → "Install now", and confirm: the app quits, the install directory
is fully replaced with the new version's files, the new version launches
automatically, and — separately — that a *running* (not paused) timer entry is
still shown as running after the relaunch, matching `quit_behavior.dart`'s
documented guarantee.
