import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/update/update_checker.dart';
import 'package:hickory/core/update/update_installer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // path_provider talks to the platform over a MethodChannel, which has no
  // real implementation under `flutter test`. Fake it out with a temp
  // directory so prepareUpdate's getTemporaryDirectory() call resolves.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fakeTempDir;

  setUp(() {
    fakeTempDir = Directory.systemTemp.createTempSync('update_installer_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async =>
              call.method == 'getTemporaryDirectory' ? fakeTempDir.path : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (fakeTempDir.existsSync()) fakeTempDir.deleteSync(recursive: true);
  });

  /// Builds a fixture zip matching each platform's actual CI archive shape:
  /// flat on Windows (Compress-Archive globs the release folder's
  /// *contents*, no wrapping directory), wrapped in a `hickory.app` bundle
  /// on macOS (ditto --keepParent) -- so prepareUpdate's extraction/
  /// executable-lookup logic can be tested without a real release artifact.
  List<int> buildFixtureZip({bool withExecutable = true}) {
    final archive = Archive();
    if (Platform.isWindows) {
      final content =
          (withExecutable ? 'fake executable' : 'unrelated file').codeUnits;
      final name = withExecutable ? 'hickory.exe' : 'readme.txt';
      archive.addFile(ArchiveFile(name, content.length, content));
    } else {
      final content =
          (withExecutable ? 'fake executable' : 'unrelated file').codeUnits;
      final name = withExecutable
          ? 'hickory.app/Contents/MacOS/hickory'
          : 'hickory.app/readme.txt';
      archive.addFile(ArchiveFile(name, content.length, content));
    }
    return ZipEncoder().encode(archive);
  }

  const update = UpdateInfo(
    version: '9.9.9',
    notes: '',
    downloadUrl: 'https://example.com/update.zip',
    checksumUrl: 'https://example.com/update.zip.sha256',
    size: 0,
  );

  test(
    'prepareUpdate returns the extracted top-level directory on success',
    skip: Platform.isMacOS || Platform.isWindows
        ? null
        : 'prepareUpdate only supports macOS and Windows; the CI test job '
              'runs on ubuntu-latest, where it throws before reaching this '
              'behavior.',
    () async {
      final zipBytes = buildFixtureZip();
      final checksum = sha256.convert(zipBytes).toString();
      final installParent = Directory(p.join(fakeTempDir.path, 'installed'))
        ..createSync(recursive: true);
      final installer = UpdateInstaller(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('.sha256')) {
            return http.Response(checksum, 200);
          }
          return http.Response.bytes(zipBytes, 200);
        }),
        installDirOverride: Directory(p.join(installParent.path, 'Hickory.app')),
      );

      final topLevel = await installer.prepareUpdate(update);

      expect(topLevel.existsSync(), isTrue);
      if (Platform.isWindows) {
        expect(File(p.join(topLevel.path, 'hickory.exe')).existsSync(), isTrue);
      } else {
        expect(topLevel.path, endsWith('hickory.app'));
      }
      addTearDown(() {
        final workDir = Platform.isWindows
            ? topLevel.parent
            : topLevel.parent.parent;
        if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      });
    },
  );

  test('prepareUpdate throws on a checksum mismatch', () async {
    final zipBytes = buildFixtureZip();
    final installer = UpdateInstaller(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return http.Response('0' * 64, 200);
        }
        return http.Response.bytes(zipBytes, 200);
      }),
    );

    expect(
      () => installer.prepareUpdate(update),
      throwsA(isA<UpdateInstallException>()),
    );
  });

  test(
    'prepareUpdate throws when the archive has no executable at the expected path',
    () async {
      final zipBytes = buildFixtureZip(withExecutable: false);
      final checksum = sha256.convert(zipBytes).toString();
      final installer = UpdateInstaller(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('.sha256')) {
            return http.Response(checksum, 200);
          }
          return http.Response.bytes(zipBytes, 200);
        }),
      );

      expect(
        () => installer.prepareUpdate(update),
        throwsA(isA<UpdateInstallException>()),
      );
    },
  );

  test('prepareUpdate throws when the download itself fails', () async {
    final installer = UpdateInstaller(
      httpClient: MockClient((request) async => http.Response('', 500)),
    );

    expect(
      () => installer.prepareUpdate(update),
      throwsA(isA<UpdateInstallException>()),
    );
  });

  test(
    'prepareUpdate throws UpdateInstallPermissionException when the install '
    "directory's parent can't be written to",
    skip: Platform.isMacOS || Platform.isWindows
        ? null
        : 'prepareUpdate only supports macOS and Windows; the CI test job '
              'runs on ubuntu-latest, where it throws before reaching this '
              'behavior.',
    () async {
      final zipBytes = buildFixtureZip();
      final checksum = sha256.convert(zipBytes).toString();
      // A parent that doesn't exist on disk can never accept the write
      // probe -- a deterministic, cross-platform stand-in for the real
      // trigger (e.g. /Applications without admin rights), which can't be
      // simulated portably since CI often runs as root/admin and bypasses
      // permission bits entirely.
      final missingParent = Directory(
        p.join(fakeTempDir.path, 'missing_parent', 'nested'),
      );
      final installer = UpdateInstaller(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('.sha256')) {
            return http.Response(checksum, 200);
          }
          return http.Response.bytes(zipBytes, 200);
        }),
        installDirOverride: Directory(p.join(missingParent.path, 'Hickory.app')),
      );

      expect(
        () => installer.prepareUpdate(update),
        throwsA(isA<UpdateInstallPermissionException>()),
      );
    },
  );
}
