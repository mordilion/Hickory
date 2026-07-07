import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'device_id_provider.g.dart';

/// Generated once per install and persisted to a plain file (not synced) so
/// it survives app restarts; identifies which device wrote which sync
/// event-log entries down the line.
@Riverpod(keepAlive: true)
Future<String> deviceId(Ref ref) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'device_id'));
  if (await file.exists()) {
    final existing = (await file.readAsString()).trim();
    if (existing.isNotEmpty) return existing;
  }
  final id = const Uuid().v4();
  await file.create(recursive: true);
  await file.writeAsString(id);
  return id;
}
