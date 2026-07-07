import 'package:drift/drift.dart';

@DataClassName('Client')
class Clients extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
