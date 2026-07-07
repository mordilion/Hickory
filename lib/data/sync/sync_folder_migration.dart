import 'dart:io';

import 'package:path/path.dart' as p;

import 'sync_paths.dart';

/// If the newly-chosen [newRoot] doesn't have any event log yet but
/// [oldRoot] does, copies the old data over. Without this, switching from
/// the default local-only folder to a real synced folder for the first
/// time would silently orphan whatever was tracked before the folder was
/// configured.
Future<void> migrateLocalDataIfNeeded({
  required Directory oldRoot,
  required Directory newRoot,
}) async {
  if (p.equals(oldRoot.path, newRoot.path)) return;

  final oldEntries = entriesDir(oldRoot);
  final newEntries = entriesDir(newRoot);
  if (!await oldEntries.exists()) return;
  if (await newEntries.exists()) return; // never clobber existing data

  await _copyDirectory(oldEntries, newEntries);
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list()) {
    final newPath = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(newPath));
    } else if (entity is File) {
      await entity.copy(newPath);
    }
  }
}
