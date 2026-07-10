import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/locale/locale_store.dart';

void main() {
  late Directory tempDir;
  late LocaleStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('locale_store_test');
    store = LocaleStore(supportDirectory: tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('read returns null when no file exists', () async {
    expect(await store.read(), isNull);
  });

  test('write/read round-trip', () async {
    await store.write('fr');
    expect(await store.read(), 'fr');
  });

  test('clear removes the preference', () async {
    await store.write('it');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('clear on a missing file is a no-op', () async {
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('unsupported code in the file yields null (e.g. after downgrade)', () async {
    File('${tempDir.path}/locale').writeAsStringSync('ja');
    expect(await store.read(), isNull);
  });

  test('corrupt content yields null', () async {
    File('${tempDir.path}/locale').writeAsStringSync('\x00\x01garbage');
    expect(await store.read(), isNull);
  });
}
