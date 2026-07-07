/// The kind of mutation a [SyncEvent] represents.
enum EventOp {
  create,
  update,
  delete;

  String get wireName => name;

  static EventOp fromWireName(String value) => switch (value) {
        'create' => EventOp.create,
        'update' => EventOp.update,
        'delete' => EventOp.delete,
        _ => throw FormatException('Unknown event op: $value'),
      };
}

/// A single append-only log entry. One line of JSONL on disk maps to
/// exactly one [SyncEvent].
///
/// [payload] is a full snapshot of the entity at the time of the mutation
/// (not a field-level diff) — deliberately simple last-write-wins semantics,
/// see the architecture plan for the tradeoff. It is null for [EventOp.delete]
/// (a tombstone).
class SyncEvent {
  const SyncEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.ts,
    required this.deviceId,
    required this.seq,
    required this.payload,
  }) : assert(
          op != EventOp.delete || payload == null,
          'delete events must not carry a payload',
        );

  final String id;
  final String entityType;
  final String entityId;
  final EventOp op;

  /// UTC timestamp used as the primary last-write-wins ordering key.
  final DateTime ts;
  final String deviceId;

  /// Per-device monotonic counter, used as the final tiebreaker after
  /// [ts] and [deviceId] (guards against clock resolution ties).
  final int seq;

  final Map<String, dynamic>? payload;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'op': op.wireName,
        'ts': ts.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'seq': seq,
        'payload': payload,
      };

  factory SyncEvent.fromJson(Map<String, dynamic> json) {
    return SyncEvent(
      id: json['id'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      op: EventOp.fromWireName(json['op'] as String),
      ts: DateTime.parse(json['ts'] as String).toUtc(),
      deviceId: json['deviceId'] as String,
      seq: json['seq'] as int,
      payload: (json['payload'] as Map<String, dynamic>?),
    );
  }

  @override
  String toString() => 'SyncEvent(${op.wireName} $entityType/$entityId '
      '@ $ts by $deviceId#$seq)';
}
