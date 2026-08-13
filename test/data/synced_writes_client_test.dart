import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/entity_types.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/sync_paths.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_synced_writes_client_test_');
    writes = SyncedWrites(db: db, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'));
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  SyncEvent lastLoggedEvent(String entityId) {
    final file = currentMonthLogFile(syncRoot, 'dev_a');
    final result = decodeJsonl(file.readAsStringSync());
    return result.events.lastWhere((e) => e.entityId == entityId);
  }

  test('createClient persists the row, returns it, and logs a create event', () async {
    final client = await writes.createClient(name: 'Acme Inc');

    expect(client.name, 'Acme Inc');
    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.name, 'Acme Inc');

    final event = lastLoggedEvent(client.id);
    expect(event.entityType, EntityTypes.client);
    expect(event.op, EventOp.create);
    expect(event.payload?['name'], 'Acme Inc');
  });

  test('updateClient persists the given fields, returns the updated row, and logs the event', () async {
    final client = await writes.createClient(name: 'Old Name');

    final updated = await writes.updateClient(client.id, name: const Value('New Name'));

    expect(updated.name, 'New Name');
    final event = lastLoggedEvent(client.id);
    expect(event.op, EventOp.update);
    expect(event.payload?['name'], 'New Name');
  });

  test('archiveClient marks the client archived and logs the event', () async {
    final client = await writes.createClient(name: 'Acme Inc');

    await writes.archiveClient(client.id);

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isTrue);
    final event = lastLoggedEvent(client.id);
    expect(event.op, EventOp.update);
    expect(event.payload?['archived'], isTrue);
  });

  test('unarchiveClient clears the archived flag and logs the event', () async {
    final client = await writes.createClient(name: 'Acme Inc');
    await writes.archiveClient(client.id);

    await writes.unarchiveClient(client.id);

    final row = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(row.archived, isFalse);
  });

  test('deleteClient removes the client and logs a delete event when it has no projects', () async {
    final client = await writes.createClient(name: 'Acme Inc');

    await writes.deleteClient(client.id);

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, isEmpty);
    final event = lastLoggedEvent(client.id);
    expect(event.entityType, EntityTypes.client);
    expect(event.op, EventOp.delete);
    expect(event.payload, isNull);
  });

  test('deleteClient throws and leaves the client untouched when a project references it', () async {
    final client = await writes.createClient(name: 'Acme Inc');
    await writes.createProject(name: 'Website Relaunch', colorHex: '#5B8DEF', clientId: client.id);

    await expectLater(writes.deleteClient(client.id), throwsA(isA<ClientHasProjectsException>()));

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, hasLength(1));
  });
}
