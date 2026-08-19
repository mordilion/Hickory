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

/// Raised when the install directory's parent can't be written to.
///
/// Up to 1.3.0 this was the *normal* macOS outcome, because the App Sandbox
/// denied `/Applications` however the bundle was owned. 1.3.1 dropped the
/// sandbox (docs/superpowers/specs/2026-08-19-macos-sandbox-removal-design.md),
/// so this is an edge case again: it now means what it says — the account
/// running the app cannot write there, typically because the bundle belongs to
/// a different user.
///
/// Distinct from [UpdateInstallException] so the Settings UI can name the
/// offending directory and a remedy instead of the generic install-failed
/// message.
class UpdateInstallPermissionException extends UpdateInstallException {
  UpdateInstallPermissionException(super.message, {required this.installParentPath});

  /// The directory that could not be written to, so the UI can name it.
  final String installParentPath;
}

/// Downloads, verifies, extracts, and installs an [UpdateInfo] on macOS/
/// Windows, then relaunches. See
/// docs/superpowers/specs/2026-08-05-github-auto-update-design.md section 4
/// for why the work is split this way: [prepareUpdate] is entirely
/// non-destructive and can fail safely with the app still running; only
/// [quitAndSwap]'s detached script touches the real install, and only after
/// this process has fully exited.
class UpdateInstaller {
  // installDirOverride must stay a public parameter name, so it can't use
  // `this._installDirOverride` -- the field is private and tests (a
  // different library) need to pass it by name.
  UpdateInstaller({http.Client? httpClient, Directory? installDirOverride})
    : _httpClient = httpClient ?? http.Client(),
      // ignore: prefer_initializing_formals
      _installDirOverride = installDirOverride;

  final http.Client _httpClient;

  /// Set by tests so [_currentInstallDir] doesn't resolve to the real
  /// [Platform.resolvedExecutable] (the test runner's own binary, whose
  /// parent directories are unrelated to any real install and shouldn't be
  /// probed for writability).
  final Directory? _installDirOverride;

  /// Downloads, verifies, and extracts [update], returning the archive's
  /// single top-level directory (the install root on Windows, the .app
  /// bundle on macOS).
  Future<Directory> prepareUpdate(UpdateInfo update) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      throw UpdateInstallException(
        'Automatic updates are only supported on macOS and Windows.',
      );
    }

    // Fail fast, before downloading anything or quitting the app: the
    // swap in quitAndSwap() runs from a detached script after this process
    // has already exited, with no way to report a failure back to the UI,
    // so a permission problem must be caught here while it's still
    // recoverable.
    _ensureInstallDirWritable(_currentInstallDir());

    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(
      p.join(
        tempDir.path,
        'hickory_update_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await workDir.create(recursive: true);

    final zipFile = File(p.join(workDir.path, 'update.zip'));
    await _downloadToFile(update.downloadUrl, zipFile);

    final expectedChecksum = (await _downloadString(
      update.checksumUrl,
    )).trim().toLowerCase();
    final actualChecksum = sha256
        .convert(await zipFile.readAsBytes())
        .toString();
    if (actualChecksum != expectedChecksum) {
      throw UpdateInstallException(
        'Downloaded update failed checksum verification.',
      );
    }

    final extractedDir = Directory(p.join(workDir.path, 'extracted'));
    await extractedDir.create(recursive: true);
    await extractFileToDisk(zipFile.path, extractedDir.path);

    final topLevel = _installRootInside(extractedDir);
    if (topLevel == null) {
      throw UpdateInstallException(
        'Downloaded update archive has an unexpected layout.',
      );
    }
    final executable = _executableInside(topLevel);
    if (!await executable.exists()) {
      throw UpdateInstallException(
        'Downloaded update is missing its executable.',
      );
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
      throw UpdateInstallException(
        'Failed to download update (HTTP ${response.statusCode}).',
      );
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

  /// The install root inside the extracted archive. Windows zips are flat
  /// (Compress-Archive globs the release folder's *contents*, so the
  /// extraction root itself is the install root); macOS zips wrap the .app
  /// bundle in a single top-level directory (ditto --keepParent), so it must
  /// be located by name rather than by listing order -- ditto
  /// --sequesterRsrc can also emit a sibling __MACOSX/ directory that must
  /// not be mistaken for the bundle. Returns null if the archive doesn't
  /// have the expected shape.
  Directory? _installRootInside(Directory extractedDir) {
    if (Platform.isWindows) return extractedDir;
    for (final entity in extractedDir.listSync()) {
      if (entity is Directory && p.basename(entity.path).endsWith('.app')) {
        return entity;
      }
    }
    return null;
  }

  /// The directory containing the running app's files -- on Windows, the
  /// folder holding hickory.exe and its data/ folder (exactly what
  /// build.yml/release.yml zip up); on macOS, the .app bundle root, three
  /// path segments above `Contents/MacOS/<executable>` -- a stable,
  /// well-known bundle-layout convention.
  Directory _currentInstallDir() {
    final override = _installDirOverride;
    if (override != null) return override;
    final executable = File(Platform.resolvedExecutable);
    return Platform.isWindows
        ? executable.parent
        : executable.parent.parent.parent;
  }

  /// Probes whether [installDir]'s parent can be written to by creating and
  /// immediately removing a throwaway directory entry there -- exactly the
  /// operation quitAndSwap's relaunch script needs (renaming installDir out
  /// of the way, then moving the new bundle in). Throws
  /// [UpdateInstallPermissionException] if it can't.
  void _ensureInstallDirWritable(Directory installDir) {
    final probe = Directory(
      p.join(installDir.parent.path, '.hickory_update_write_test_$pid'),
    );
    try {
      probe.createSync();
      probe.deleteSync();
    } catch (_) {
      throw UpdateInstallPermissionException(
        "Hickory can't write to its installation folder "
        '(${installDir.parent.path}).',
        installParentPath: installDir.parent.path,
      );
    }
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
Wait-Process -Id $currentPid -ErrorAction SilentlyContinue
\$backup = "${installDir.path}_old"
if (Test-Path \$backup) { Remove-Item \$backup -Recurse -Force }
try {
    Rename-Item -Path "${installDir.path}" -NewName (Split-Path \$backup -Leaf) -ErrorAction Stop
    Move-Item -Path "${extractedTopLevel.path}" -Destination "${installDir.path}" -ErrorAction Stop
    Remove-Item \$backup -Recurse -Force
} catch {
    if (-not (Test-Path "${installDir.path}") -and (Test-Path \$backup)) {
        Rename-Item -Path \$backup -NewName (Split-Path "${installDir.path}" -Leaf)
    }
}
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
if mv "${installDir.path}" "\$BACKUP" && mv "${extractedTopLevel.path}" "${installDir.path}"; then
  rm -rf "\$BACKUP"
else
  if [ ! -e "${installDir.path}" ] && [ -e "\$BACKUP" ]; then
    mv "\$BACKUP" "${installDir.path}"
  fi
fi
open "${installDir.path}"
rm -- "\$0"
''');
    await Process.run('chmod', ['+x', scriptFile.path]);
    return scriptFile.path;
  }

  Future<void> _launchDetached(String scriptPath) {
    if (Platform.isWindows) {
      return Process.start('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
      ], mode: ProcessStartMode.detached);
    }
    return Process.start('/bin/sh', [
      scriptPath,
    ], mode: ProcessStartMode.detached);
  }
}
