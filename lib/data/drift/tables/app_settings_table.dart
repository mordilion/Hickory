import 'package:drift/drift.dart';

/// A singleton settings row — always exactly one record, keyed by the
/// fixed id [appSettingsRowId] rather than a generated UUID, since there is
/// exactly one current value per synced identity. Deliberately holds more
/// than just date/time format so a future setting (e.g. the planned i18n
/// language preference) can be added as a new column without introducing a
/// second synced singleton entity type.
const appSettingsRowId = 'default';

@DataClassName('AppSettingsRow')
class AppSettings extends Table {
  TextColumn get id => text()();
  TextColumn get dateFormat => text().withDefault(const Constant('iso'))();
  TextColumn get timeFormat => text().withDefault(const Constant('24h'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
