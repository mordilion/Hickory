import 'event.dart';

/// The current, materialized state of one entity after merging every event
/// that ever touched it.
class MaterializedEntity {
  const MaterializedEntity({
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.winningEvent,
  });

  final String entityType;
  final String entityId;

  /// Null means the entity is deleted (the winning event was a tombstone).
  final Map<String, dynamic>? payload;

  final SyncEvent winningEvent;

  bool get isDeleted => payload == null;
}

/// Orders events for last-write-wins resolution: primarily by timestamp,
/// then by device id (lexicographic, arbitrary but deterministic), then by
/// the device's own monotonic sequence counter as a final tiebreaker.
///
/// This relies on device wall clocks being roughly correct; see the
/// architecture plan for the accepted tradeoff vs. a Hybrid Logical Clock.
int compareEventsForMerge(SyncEvent a, SyncEvent b) {
  final tsCompare = a.ts.compareTo(b.ts);
  if (tsCompare != 0) return tsCompare;
  final deviceCompare = a.deviceId.compareTo(b.deviceId);
  if (deviceCompare != 0) return deviceCompare;
  return a.seq.compareTo(b.seq);
}

/// Merges every event for every entity into one current-state view: groups
/// by [SyncEvent.entityId], and for each group the event that sorts last
/// under [compareEventsForMerge] wins. A winning delete event tombstones
/// the entity (absent from the result's non-deleted view via [isDeleted]).
///
/// Pure and deterministic — safe to call repeatedly on the same input, and
/// safe to call on the full event history every time (a "rebuild") since it
/// never depends on prior state.
Map<String, MaterializedEntity> materialize(Iterable<SyncEvent> events) {
  final byEntity = <String, List<SyncEvent>>{};
  for (final event in events) {
    byEntity.putIfAbsent(event.entityId, () => []).add(event);
  }

  final result = <String, MaterializedEntity>{};
  for (final MapEntry(key: entityId, value: entityEvents) in byEntity.entries) {
    final sorted = [...entityEvents]..sort(compareEventsForMerge);
    final winner = sorted.last;
    result[entityId] = MaterializedEntity(
      entityType: winner.entityType,
      entityId: entityId,
      payload: winner.op == EventOp.delete ? null : winner.payload,
      winningEvent: winner,
    );
  }
  return result;
}
