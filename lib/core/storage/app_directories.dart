import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The one directory the app keeps its state in: the database next to the
/// device id, sync configuration and window bounds.
///
/// macOS uses the support directory, Windows the documents directory. That
/// difference is deliberate rather than sloppy: the database has always lived
/// in the documents directory, and on macOS that path is about to change
/// meaning -- unsandboxed it resolves to the user's own `~/Documents`, which is
/// no place for an app database (visible in Finder, offered in every backup
/// dialog, deleted by accident). Windows keeps its existing path because
/// nothing forces it to move, and moving a working install's database earns
/// only risk. See docs/superpowers/specs/2026-08-19-macos-sandbox-removal-design.md.
Future<Directory> appDataDirectory() => Platform.isMacOS
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();

/// Where the sandboxed build's support data sits, derived from [home] and
/// [bundleId] because `path_provider` stops returning it once the sandbox is
/// gone. macOS's own layout -- the bundle id appears twice, once for the
/// container and once inside it.
Directory legacyContainerSupportDirectory(String home, String bundleId) =>
    Directory(
      p.join(
        home,
        'Library',
        'Containers',
        bundleId,
        'Data',
        'Library',
        'Application Support',
        bundleId,
      ),
    );

/// Where the sandboxed build's database sits (see
/// [legacyContainerSupportDirectory] for why this is built by hand).
Directory legacyContainerDocumentsDirectory(String home, String bundleId) =>
    Directory(
      p.join(home, 'Library', 'Containers', bundleId, 'Data', 'Documents'),
    );

/// The bundle id, read off the support directory `path_provider` resolved.
///
/// Cheaper and harder to get wrong than asking for the bundle id separately:
/// path_provider appends it to the support directory on macOS, so the last
/// segment already is it, and this stays correct if it ever changes.
String bundleIdOfSupportDirectory(String supportDirectoryPath) =>
    p.basename(supportDirectoryPath);

/// The user's home directory, derived from the resolved support directory
/// (`<home>/Library/Application Support/<bundleId>`).
///
/// Not `Platform.environment['HOME']`: macOS redirects that into the container
/// for a sandboxed app, so it names the very place the migration is trying to
/// read out of. Cost us a wrong no-op before the smoke test caught it.
String homeOfSupportDirectory(String supportDirectoryPath) =>
    p.dirname(p.dirname(p.dirname(supportDirectoryPath)));

/// True when [path] sits inside a sandbox container, i.e. this build is still
/// sandboxed and has nothing to migrate out of.
bool isSandboxContainerPath(String path) => path.contains(
  '${p.separator}Library${p.separator}Containers${p.separator}',
);
