import 'package:drift/drift.dart';

@DataClassName('Tag')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();

  @override
  Set<Column> get primaryKey => {id};
}
