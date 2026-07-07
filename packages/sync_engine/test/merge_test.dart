import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

SyncEvent _event({
  required String id,
  String entityType = 'time_entry',
  required String entityId,
  required EventOp op,
  required DateTime ts,
  required String deviceId,
  int seq = 0,
  Map<String, dynamic>? payload,
}) {
  return SyncEvent(
    id: id,
    entityType: entityType,
    entityId: entityId,
    op: op,
    ts: ts,
    deviceId: deviceId,
    seq: seq,
    payload: op == EventOp.delete ? null : (payload ?? const {}),
  );
}

void main() {
  group('materialize', () {
    test('a lone create is the winning state', () {
      final result = materialize([
        _event(
          id: 'e1',
          entityId: 'te_1',
          op: EventOp.create,
          ts: DateTime.utc(2026, 7, 7, 10),
          deviceId: 'dev_a',
          payload: {'description': 'first'},
        ),
      ]);

      expect(result['te_1']!.isDeleted, isFalse);
      expect(result['te_1']!.payload, {'description': 'first'});
    });

    test('a later update overrides an earlier create, regardless of insertion order', () {
      final create = _event(
        id: 'e1',
        entityId: 'te_1',
        op: EventOp.create,
        ts: DateTime.utc(2026, 7, 7, 10),
        deviceId: 'dev_a',
        payload: {'description': 'first'},
      );
      final update = _event(
        id: 'e2',
        entityId: 'te_1',
        op: EventOp.update,
        ts: DateTime.utc(2026, 7, 7, 11),
        deviceId: 'dev_a',
        payload: {'description': 'edited'},
      );

      // Feed events out of chronological order to prove sorting, not
      // insertion order, decides the winner.
      final result = materialize([update, create]);

      expect(result['te_1']!.payload, {'description': 'edited'});
    });

    test('a delete tombstones the entity even if a create arrives later in the list', () {
      final delete = _event(
        id: 'e1',
        entityId: 'te_1',
        op: EventOp.delete,
        ts: DateTime.utc(2026, 7, 7, 12),
        deviceId: 'dev_a',
      );
      final earlierCreate = _event(
        id: 'e2',
        entityId: 'te_1',
        op: EventOp.create,
        ts: DateTime.utc(2026, 7, 7, 10),
        deviceId: 'dev_a',
        payload: {'description': 'first'},
      );

      final result = materialize([earlierCreate, delete]);

      expect(result['te_1']!.isDeleted, isTrue);
      expect(result['te_1']!.payload, isNull);
    });

    test('a stale update from another device does not resurrect a later delete', () {
      final deleteOnDeviceA = _event(
        id: 'e1',
        entityId: 'te_1',
        op: EventOp.delete,
        ts: DateTime.utc(2026, 7, 7, 12),
        deviceId: 'dev_a',
      );
      final staleUpdateFromDeviceB = _event(
        id: 'e2',
        entityId: 'te_1',
        op: EventOp.update,
        ts: DateTime.utc(2026, 7, 7, 11, 59),
        deviceId: 'dev_b',
        payload: {'description': 'stale edit made before the delete synced'},
      );

      final result = materialize([staleUpdateFromDeviceB, deleteOnDeviceA]);

      expect(result['te_1']!.isDeleted, isTrue);
    });

    test('ties at the same timestamp are broken by deviceId', () {
      final sameTs = DateTime.utc(2026, 7, 7, 10);
      final fromB = _event(
        id: 'e1',
        entityId: 'te_1',
        op: EventOp.update,
        ts: sameTs,
        deviceId: 'dev_b',
        payload: {'description': 'from b'},
      );
      final fromA = _event(
        id: 'e2',
        entityId: 'te_1',
        op: EventOp.update,
        ts: sameTs,
        deviceId: 'dev_a',
        payload: {'description': 'from a'},
      );

      final result = materialize([fromA, fromB]);

      // 'dev_b' > 'dev_a' lexicographically, so it wins the tie.
      expect(result['te_1']!.payload, {'description': 'from b'});
    });

    test('ties at the same timestamp and device are broken by seq', () {
      final sameTs = DateTime.utc(2026, 7, 7, 10);
      final seq1 = _event(
        id: 'e1',
        entityId: 'te_1',
        op: EventOp.update,
        ts: sameTs,
        deviceId: 'dev_a',
        seq: 1,
        payload: {'description': 'seq 1'},
      );
      final seq2 = _event(
        id: 'e2',
        entityId: 'te_1',
        op: EventOp.update,
        ts: sameTs,
        deviceId: 'dev_a',
        seq: 2,
        payload: {'description': 'seq 2'},
      );

      final result = materialize([seq2, seq1]);

      expect(result['te_1']!.payload, {'description': 'seq 2'});
    });

    test('entities are resolved independently of one another', () {
      final result = materialize([
        _event(
          id: 'e1',
          entityId: 'te_1',
          op: EventOp.create,
          ts: DateTime.utc(2026, 7, 7),
          deviceId: 'dev_a',
          payload: {'n': 1},
        ),
        _event(
          id: 'e2',
          entityId: 'te_2',
          op: EventOp.create,
          ts: DateTime.utc(2026, 7, 7),
          deviceId: 'dev_a',
          payload: {'n': 2},
        ),
        _event(
          id: 'e3',
          entityId: 'te_2',
          op: EventOp.delete,
          ts: DateTime.utc(2026, 7, 8),
          deviceId: 'dev_a',
        ),
      ]);

      expect(result['te_1']!.isDeleted, isFalse);
      expect(result['te_2']!.isDeleted, isTrue);
    });

    test('empty input materializes to an empty map', () {
      expect(materialize(const []), isEmpty);
    });
  });
}
