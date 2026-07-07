// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_samples_dao.dart';

// ignore_for_file: type=lint
mixin _$ActivitySamplesDaoMixin on DatabaseAccessor<AppDatabase> {
  $ActivitySamplesTable get activitySamples => attachedDatabase.activitySamples;
  ActivitySamplesDaoManager get managers => ActivitySamplesDaoManager(this);
}

class ActivitySamplesDaoManager {
  final _$ActivitySamplesDaoMixin _db;
  ActivitySamplesDaoManager(this._db);
  $$ActivitySamplesTableTableManager get activitySamples =>
      $$ActivitySamplesTableTableManager(
        _db.attachedDatabase,
        _db.activitySamples,
      );
}
