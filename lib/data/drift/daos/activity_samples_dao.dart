import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/activity_samples_table.dart';

part 'activity_samples_dao.g.dart';

@DriftAccessor(tables: [ActivitySamples])
class ActivitySamplesDao extends DatabaseAccessor<AppDatabase> with _$ActivitySamplesDaoMixin {
  ActivitySamplesDao(super.db);

  Future<void> insertSample(Insertable<ActivitySampleRow> sample) {
    return into(activitySamples).insertOnConflictUpdate(sample);
  }

  Stream<ActivitySampleRow?> watchLatestSample() {
    return (select(activitySamples)
          ..orderBy([(a) => OrderingTerm.desc(a.observedAt)])
          ..limit(1))
        .watchSingleOrNull();
  }
}
