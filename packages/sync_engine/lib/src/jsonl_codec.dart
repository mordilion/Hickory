import 'dart:convert';

import 'event.dart';

/// Result of decoding a JSONL blob: the successfully-parsed events plus a
/// count of lines that were skipped because they were malformed (expected
/// in practice — a cloud sync client can deliver a file mid-write).
class JsonlDecodeResult {
  const JsonlDecodeResult({required this.events, required this.skippedLines});

  final List<SyncEvent> events;
  final int skippedLines;
}

/// Encodes events as newline-delimited JSON, one line per event, ready to
/// append to (or write as) a `.jsonl` sync log file.
String encodeEventsToJsonl(Iterable<SyncEvent> events) {
  return events.map((e) => jsonEncode(e.toJson())).join('\n');
}

/// Decodes a JSONL blob into events. Blank lines are skipped silently;
/// lines that fail to parse as JSON or don't match the expected shape are
/// counted in [JsonlDecodeResult.skippedLines] rather than throwing, since a
/// partially-written file (mid-sync) is an expected occurrence, not a bug.
JsonlDecodeResult decodeJsonl(String content) {
  final events = <SyncEvent>[];
  var skipped = 0;
  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      events.add(SyncEvent.fromJson(decoded));
    } on Object {
      skipped++;
    }
  }
  return JsonlDecodeResult(events: events, skippedLines: skipped);
}
