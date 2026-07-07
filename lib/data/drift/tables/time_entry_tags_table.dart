import 'package:drift/drift.dart';

import 'tags_table.dart';
import 'time_entries_table.dart';

@DataClassName('TimeEntryTag')
class TimeEntryTags extends Table {
  TextColumn get timeEntryId => text().references(TimeEntries, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {timeEntryId, tagId};
}
