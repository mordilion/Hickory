/// String values used in [SyncEvent.entityType]. Kept as constants so the
/// writer (emitting events) and the ingestor (dispatching on entityType)
/// can't drift apart on the literal strings.
abstract final class EntityTypes {
  static const project = 'project';
  static const timeEntry = 'time_entry';
  static const client = 'client';
  static const tag = 'tag';
  static const activitySample = 'activity_sample';
  static const appSettings = 'app_settings';
}
