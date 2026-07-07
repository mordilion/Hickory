import 'package:drift/drift.dart';

import 'clients_table.dart';

@DataClassName('Project')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();
  TextColumn get clientId => text().nullable().references(Clients, #id)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get billable => boolean().withDefault(const Constant(true))();
  IntColumn get hourlyRateCents => integer().nullable()();
  TextColumn get currency => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
