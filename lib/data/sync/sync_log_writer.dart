import 'dart:io';

import 'package:sync_engine/sync_engine.dart';

import 'sync_paths.dart';

/// Appends events to the current device's own current-month log file only —
/// never to another device's file. That per-device split is what makes
/// concurrent writes from multiple devices safe without a shared lock: each
/// device's file has exactly one writer.
class SyncLogWriter {
  SyncLogWriter({required this.syncRoot, required this.deviceId});

  final Directory syncRoot;
  final String deviceId;

  int _seq = 0;

  Future<void> appendEvent({
    required String entityType,
    required String entityId,
    required EventOp op,
    required Map<String, dynamic>? payload,
  }) async {
    final now = DateTime.now().toUtc();
    final event = SyncEvent(
      id: '${deviceId}_${now.microsecondsSinceEpoch}_$_seq',
      entityType: entityType,
      entityId: entityId,
      op: op,
      ts: now,
      deviceId: deviceId,
      seq: _seq++,
      payload: op == EventOp.delete ? null : payload,
    );

    final file = currentMonthLogFile(syncRoot, deviceId, now: now);
    await file.parent.create(recursive: true);
    await file.writeAsString('${encodeEventsToJsonl([event])}\n', mode: FileMode.append);
  }
}
