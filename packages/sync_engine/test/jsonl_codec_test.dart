import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('encodeEventsToJsonl / decodeJsonl', () {
    test('round-trips a create event', () {
      final event = SyncEvent(
        id: 'evt_1',
        entityType: 'project',
        entityId: 'proj_1',
        op: EventOp.create,
        ts: DateTime.utc(2026, 7, 7, 12, 0, 0),
        deviceId: 'dev_a',
        seq: 1,
        payload: {'name': 'Hickory'},
      );

      final jsonl = encodeEventsToJsonl([event]);
      final result = decodeJsonl(jsonl);

      expect(result.skippedLines, 0);
      expect(result.events, hasLength(1));
      expect(result.events.single.id, 'evt_1');
      expect(result.events.single.payload, {'name': 'Hickory'});
    });

    test('round-trips a delete (tombstone) event with a null payload', () {
      final event = SyncEvent(
        id: 'evt_2',
        entityType: 'project',
        entityId: 'proj_1',
        op: EventOp.delete,
        ts: DateTime.utc(2026, 7, 7, 12, 5, 0),
        deviceId: 'dev_a',
        seq: 2,
        payload: null,
      );

      final result = decodeJsonl(encodeEventsToJsonl([event]));

      expect(result.events.single.op, EventOp.delete);
      expect(result.events.single.payload, isNull);
    });

    test('encodes one event per line', () {
      final events = List.generate(
        3,
        (i) => SyncEvent(
          id: 'evt_$i',
          entityType: 'tag',
          entityId: 'tag_$i',
          op: EventOp.create,
          ts: DateTime.utc(2026, 7, 7),
          deviceId: 'dev_a',
          seq: i,
          payload: const {},
        ),
      );

      final jsonl = encodeEventsToJsonl(events);

      expect(jsonl.split('\n'), hasLength(3));
    });

    test('skips malformed lines instead of throwing', () {
      const content = '{"not": "an event"}\n'
          'not even json\n'
          '\n'
          '   \n';

      final result = decodeJsonl(content);

      expect(result.events, isEmpty);
      // "not even json" and the bad-shape line are skipped; blank/whitespace
      // lines are simply ignored and not counted as skipped.
      expect(result.skippedLines, 2);
    });

    test('skips only the malformed lines among otherwise-valid ones', () {
      final good = SyncEvent(
        id: 'evt_good',
        entityType: 'project',
        entityId: 'proj_1',
        op: EventOp.create,
        ts: DateTime.utc(2026, 7, 7),
        deviceId: 'dev_a',
        seq: 0,
        payload: const {'name': 'X'},
      );
      final content = '${encodeEventsToJsonl([good])}\n{corrupted';

      final result = decodeJsonl(content);

      expect(result.events, hasLength(1));
      expect(result.events.single.id, 'evt_good');
      expect(result.skippedLines, 1);
    });
  });
}
