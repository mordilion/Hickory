import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/jira_worklogs_table.dart';

part 'jira_worklogs_dao.g.dart';

@DriftAccessor(tables: [JiraWorklogs])
class JiraWorklogsDao extends DatabaseAccessor<AppDatabase> with _$JiraWorklogsDaoMixin {
  JiraWorklogsDao(super.db);

  Stream<List<JiraWorklogRow>> watchAll() => select(jiraWorklogs).watch();

  Future<List<JiraWorklogRow>> getAll() => select(jiraWorklogs).get();

  Future<JiraWorklogRow?> getForEntry(String timeEntryId) {
    return (select(jiraWorklogs)..where((w) => w.id.equals(timeEntryId))).getSingleOrNull();
  }

  Future<void> upsert(Insertable<JiraWorklogRow> row) {
    return into(jiraWorklogs).insertOnConflictUpdate(row);
  }

  Future<void> deleteForEntry(String timeEntryId) {
    return (delete(jiraWorklogs)..where((w) => w.id.equals(timeEntryId))).go();
  }
}
