import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/window_bounds_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_window_bounds_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('read returns null before any write', () async {
    final store = WindowBoundsStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });

  test('write then read round-trips the same bounds, and persists across instances', () async {
    final store = WindowBoundsStore(supportDirectory: tempDir);
    const bounds = Rect.fromLTWH(120, 80, 900, 700);

    await store.write(bounds);

    expect(await store.read(), bounds);
    // A fresh instance reading the same directory sees the same bounds --
    // proves this is real file persistence, not in-memory state.
    final freshStore = WindowBoundsStore(supportDirectory: tempDir);
    expect(await freshStore.read(), bounds);
  });

  test('read returns null for a corrupt bounds file instead of throwing', () async {
    final file = File('${tempDir.path}/window_bounds.json');
    await file.writeAsString('{not valid json');

    final store = WindowBoundsStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });

  test('read returns null for structurally-valid JSON with a non-positive size', () async {
    final file = File('${tempDir.path}/window_bounds.json');
    await file.writeAsString('{"x":0,"y":0,"width":0,"height":0}');

    final store = WindowBoundsStore(supportDirectory: tempDir);
    expect(await store.read(), isNull);
  });
}
