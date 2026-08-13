import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('createClient inserts a row with archived defaulting to false', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');

    expect(client.name, 'Acme Inc');
    expect(client.archived, isFalse);
  });

  test('updateClient updates only the fields passed', () async {
    final client = await db.clientsDao.createClient(name: 'Old Name');

    await db.clientsDao.updateClient(client.id, name: const Value('New Name'));

    final updated = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(updated.name, 'New Name');
  });

  test('archiveClient sets archived to true', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');

    await db.clientsDao.archiveClient(client.id);

    final updated = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(updated.archived, isTrue);
  });

  test('unarchiveClient sets archived back to false', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');
    await db.clientsDao.archiveClient(client.id);

    await db.clientsDao.unarchiveClient(client.id);

    final updated = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).getSingle();
    expect(updated.archived, isFalse);
  });

  test('watchActiveClients only returns non-archived clients, ordered by name', () async {
    final active = await db.clientsDao.createClient(name: 'Active Client');
    final archivedB = await db.clientsDao.createClient(name: 'Zeta');
    final archivedA = await db.clientsDao.createClient(name: 'Alpha');
    await db.clientsDao.archiveClient(archivedB.id);
    await db.clientsDao.archiveClient(archivedA.id);

    final result = await db.clientsDao.watchActiveClients().first;

    expect(result.map((c) => c.name), ['Active Client']);
    expect(result.any((c) => c.id == active.id), isTrue);
  });

  test('watchArchivedClients only returns archived clients, ordered by name', () async {
    final archivedB = await db.clientsDao.createClient(name: 'Zeta');
    final archivedA = await db.clientsDao.createClient(name: 'Alpha');
    await db.clientsDao.archiveClient(archivedB.id);
    await db.clientsDao.archiveClient(archivedA.id);

    final result = await db.clientsDao.watchArchivedClients().first;

    expect(result.map((c) => c.name), ['Alpha', 'Zeta']);
  });

  test('deleteClient removes the row', () async {
    final client = await db.clientsDao.createClient(name: 'Acme Inc');

    await db.clientsDao.deleteClient(client.id);

    final remaining = await (db.select(db.clients)..where((c) => c.id.equals(client.id))).get();
    expect(remaining, isEmpty);
  });
}
