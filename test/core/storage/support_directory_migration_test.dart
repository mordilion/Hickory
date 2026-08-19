import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/storage/support_directory_migration.dart';

void main() {
  late Directory root;
  late Directory legacySupport;
  late Directory legacyDocuments;
  late Directory target;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hickory_migration_test_');
    legacySupport = Directory(
      '${root.path}/container/Library/Application Support',
    )..createSync(recursive: true);
    legacyDocuments = Directory('${root.path}/container/Documents')
      ..createSync(recursive: true);
    target = Directory('${root.path}/unsandboxed')..createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<SupportMigrationOutcome> migrate() => migrateOutOfSandboxContainer(
    legacySupport: legacySupport,
    legacyDocuments: legacyDocuments,
    target: target,
    databaseFileName: 'hickory.sqlite',
  );

  test(
    'copies the database and the support files into one directory',
    () async {
      File('${legacyDocuments.path}/hickory.sqlite').writeAsStringSync('db');
      File('${legacySupport.path}/device_id').writeAsStringSync('device-1');
      Directory('${legacySupport.path}/sync').createSync();
      File('${legacySupport.path}/sync/state.json').writeAsStringSync('{}');

      expect(await migrate(), SupportMigrationOutcome.copied);
      expect(File('${target.path}/hickory.sqlite').readAsStringSync(), 'db');
      expect(File('${target.path}/device_id').readAsStringSync(), 'device-1');
      expect(File('${target.path}/sync/state.json').existsSync(), isTrue);
    },
  );

  test('leaves the legacy data in place', () async {
    File('${legacyDocuments.path}/hickory.sqlite').writeAsStringSync('db');

    await migrate();

    expect(File('${legacyDocuments.path}/hickory.sqlite').existsSync(), isTrue);
  });

  test('does nothing when the target already has a database', () async {
    File('${legacyDocuments.path}/hickory.sqlite').writeAsStringSync('old');
    File('${target.path}/hickory.sqlite').writeAsStringSync('current');

    expect(await migrate(), SupportMigrationOutcome.skippedAlreadyMigrated);
    // The second run must never overwrite live data with the stale container copy.
    expect(File('${target.path}/hickory.sqlite').readAsStringSync(), 'current');
  });

  test('does nothing for a fresh install with no container', () async {
    legacySupport.deleteSync();
    legacyDocuments.deleteSync();

    expect(await migrate(), SupportMigrationOutcome.skippedNoLegacyData);
    expect(target.listSync(), isEmpty);
  });

  test('reports copied when only the support directory exists', () async {
    legacyDocuments.deleteSync();
    File('${legacySupport.path}/device_id').writeAsStringSync('device-1');

    expect(await migrate(), SupportMigrationOutcome.copied);
    expect(File('${target.path}/device_id').existsSync(), isTrue);
  });
}
