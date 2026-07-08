import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/window/background_notice_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_notice_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('has not been shown before markShown is called', () async {
    final store = BackgroundNoticeStore(supportDirectory: tempDir);
    expect(await store.hasBeenShown(), isFalse);
  });

  test('reports shown after markShown, and persists across instances', () async {
    final store = BackgroundNoticeStore(supportDirectory: tempDir);
    await store.markShown();

    expect(await store.hasBeenShown(), isTrue);
    // A fresh instance reading the same directory sees the same flag —
    // proves this is real file persistence, not in-memory state.
    final freshStore = BackgroundNoticeStore(supportDirectory: tempDir);
    expect(await freshStore.hasBeenShown(), isTrue);
  });
}
