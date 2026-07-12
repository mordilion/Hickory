// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jira_worklogs_dao.dart';

// ignore_for_file: type=lint
mixin _$JiraWorklogsDaoMixin on DatabaseAccessor<AppDatabase> {
  $JiraWorklogsTable get jiraWorklogs => attachedDatabase.jiraWorklogs;
  JiraWorklogsDaoManager get managers => JiraWorklogsDaoManager(this);
}

class JiraWorklogsDaoManager {
  final _$JiraWorklogsDaoMixin _db;
  JiraWorklogsDaoManager(this._db);
  $$JiraWorklogsTableTableManager get jiraWorklogs =>
      $$JiraWorklogsTableTableManager(_db.attachedDatabase, _db.jiraWorklogs);
}
