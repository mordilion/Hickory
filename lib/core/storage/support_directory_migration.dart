import 'dart:io';

import 'package:path/path.dart' as p;

/// What [migrateOutOfSandboxContainer] did, so the caller can log it.
enum SupportMigrationOutcome {
  /// The target already held a database: migration ran on an earlier start, or
  /// this install never was sandboxed.
  skippedAlreadyMigrated,

  /// Neither legacy directory exists — a fresh install.
  skippedNoLegacyData,

  /// Legacy data was copied into the target.
  copied,
}

/// Copies data left behind in the macOS sandbox container into [target], the
/// directory the unsandboxed build actually reads.
///
/// Dropping `com.apple.security.app-sandbox` moves both of the app's storage
/// locations. `getApplicationSupportDirectory()` stops resolving into the
/// container, and `getApplicationDocumentsDirectory()` — where the database has
/// always lived — starts resolving to the user's own `~/Documents`, which is no
/// place for an app database. So both legacy directories collapse into one
/// [target]: [legacyDocuments]'s [databaseFileName] plus everything under
/// [legacySupport]. Without this, the first unsandboxed start looks to the user
/// exactly like data loss.
///
/// Copies rather than moves, and never deletes: a failed or interrupted run has
/// to leave the sandboxed build fully working, since the container may hold the
/// only copy of someone's tracked time. Removing the container is a later
/// release's job, once this has proven itself.
///
/// The presence of `target/databaseFileName` is the "already migrated" marker,
/// so there is no separate state to keep in sync — and no way for a second run
/// to overwrite live data with the stale container copy.
///
/// Throws whatever [File.copy] or [Directory.create] throws. The caller must
/// surface that: starting with half the data copied, silently, is worse than
/// refusing to start.
Future<SupportMigrationOutcome> migrateOutOfSandboxContainer({
  required Directory legacySupport,
  required Directory legacyDocuments,
  required Directory target,
  required String databaseFileName,
}) async {
  if (await File(p.join(target.path, databaseFileName)).exists()) {
    return SupportMigrationOutcome.skippedAlreadyMigrated;
  }
  final hasSupport = await legacySupport.exists();
  final hasDocuments = await legacyDocuments.exists();
  if (!hasSupport && !hasDocuments) {
    return SupportMigrationOutcome.skippedNoLegacyData;
  }

  await target.create(recursive: true);

  if (hasDocuments) {
    final legacyDatabase = File(p.join(legacyDocuments.path, databaseFileName));
    if (await legacyDatabase.exists()) {
      await legacyDatabase.copy(p.join(target.path, databaseFileName));
    }
  }
  if (hasSupport) {
    await _copyInto(legacySupport, target);
  }
  return SupportMigrationOutcome.copied;
}

/// Recursively copies [source]'s contents into [target].
///
/// Skips links rather than following them: nothing the app writes is a link, so
/// one appearing here is not ours to reproduce.
Future<void> _copyInto(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final destination = p.join(target.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(destination);
      continue;
    }
    if (entity is Directory) {
      await _copyInto(entity, Directory(destination));
    }
  }
}
