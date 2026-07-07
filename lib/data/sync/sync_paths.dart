import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Root directory containing the `entries/<deviceId>/*.jsonl` event log.
///
/// For this milestone the root is a fixed local folder inside app support
/// storage. A later milestone swaps this for a user-picked, cloud-synced
/// folder (iCloud Drive / Google Drive / Dropbox) — the writer and
/// ingestor only ever deal with a plain [Directory], so that swap doesn't
/// require changing anything downstream.
Future<Directory> defaultSyncRoot() async {
  final supportDir = await getApplicationSupportDirectory();
  final root = Directory(p.join(supportDir.path, 'sync'));
  await root.create(recursive: true);
  return root;
}

Directory entriesDir(Directory syncRoot) => Directory(p.join(syncRoot.path, 'entries'));

Directory deviceLogDir(Directory syncRoot, String deviceId) =>
    Directory(p.join(entriesDir(syncRoot).path, deviceId));

/// The device's own current-month log file, e.g. `entries/dev_abc/2026-07.jsonl`.
File currentMonthLogFile(Directory syncRoot, String deviceId, {DateTime? now}) {
  final ts = now ?? DateTime.now().toUtc();
  final month = ts.month.toString().padLeft(2, '0');
  return File(p.join(deviceLogDir(syncRoot, deviceId).path, '${ts.year}-$month.jsonl'));
}
