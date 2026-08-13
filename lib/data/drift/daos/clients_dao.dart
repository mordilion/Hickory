import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/clients_table.dart';

part 'clients_dao.g.dart';

@DriftAccessor(tables: [Clients])
class ClientsDao extends DatabaseAccessor<AppDatabase> with _$ClientsDaoMixin {
  ClientsDao(super.db);

  static const _uuid = Uuid();

  Stream<List<Client>> watchActiveClients() {
    return (select(clients)
          ..where((c) => c.archived.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Stream<List<Client>> watchArchivedClients() {
    return (select(clients)
          ..where((c) => c.archived.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<Client> createClient({required String name}) async {
    final now = DateTime.now().toUtc();
    final entry = ClientsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await into(clients).insert(entry);
    return (select(clients)..where((c) => c.id.equals(entry.id.value))).getSingle();
  }

  /// Partial update -- every parameter left as [Value.absent] keeps that
  /// column's current value, same shape as [ProjectsDao.updateProject].
  Future<void> updateClient(String id, {Value<String> name = const Value.absent()}) {
    return (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(name: name, updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> archiveClient(String id) {
    return (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> unarchiveClient(String id) {
    return (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(archived: const Value(false), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> deleteClient(String id) => (delete(clients)..where((c) => c.id.equals(id))).go();
}
