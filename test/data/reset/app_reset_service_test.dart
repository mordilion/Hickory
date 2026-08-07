import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/reset/app_reset_service.dart';
import 'package:hickory/data/sync/sync_paths.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';

class _FakeJiraCredentialsStore implements JiraCredentialsStore {
  bool cleared = false;

  @override
  Future<JiraCredentials?> read() async => null;

  @override
  Future<void> write(JiraCredentials credentials) async {}

  @override
  Future<void> clear() async => cleared = true;
}

class _FakePersonioCredentialsStore implements PersonioCredentialsStore {
  bool cleared = false;

  @override
  Future<PersonioCredentials?> read() async => null;

  @override
  Future<void> write(PersonioCredentials credentials) async {}

  @override
  Future<void> clear() async => cleared = true;
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late Directory effectiveRoot;
  late Directory defaultRoot;
  late Directory localeDir;
  late Directory reportViewStateDir;
  late _FakeJiraCredentialsStore jiraStore;
  late _FakePersonioCredentialsStore personioStore;
  late LocaleStore localeStore;
  late ReportViewStateStore reportViewStateStore;
  late bool syncFolderCleared;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync(
      'hickory_app_reset_service_test_',
    );
    effectiveRoot = Directory('${tempDir.path}/configured_folder')
      ..createSync();
    defaultRoot = Directory('${tempDir.path}/default_root')..createSync();
    localeDir = Directory('${tempDir.path}/locale')..createSync();
    reportViewStateDir = Directory('${tempDir.path}/report_view_state')
      ..createSync();
    jiraStore = _FakeJiraCredentialsStore();
    personioStore = _FakePersonioCredentialsStore();
    localeStore = LocaleStore(supportDirectory: localeDir);
    reportViewStateStore = ReportViewStateStore(
      supportDirectory: reportViewStateDir,
    );
    syncFolderCleared = false;

    // This device's own log file under the configured folder, and its own
    // log file under the always-present default root -- both must be
    // deleted so the device can't re-ingest its own history on next sync.
    await deviceLogDir(effectiveRoot, 'this-device').create(recursive: true);
    await File(
      '${deviceLogDir(effectiveRoot, 'this-device').path}/2026-08.jsonl',
    ).writeAsString('{}\n');
    await deviceLogDir(defaultRoot, 'this-device').create(recursive: true);
    await File(
      '${deviceLogDir(defaultRoot, 'this-device').path}/2026-08.jsonl',
    ).writeAsString('{}\n');

    // Another device's log file under the configured (shared) folder --
    // must survive untouched: a device-local reset must never delete
    // another device's contribution to a shared sync folder.
    await deviceLogDir(effectiveRoot, 'other-device').create(recursive: true);
    await File(
      '${deviceLogDir(effectiveRoot, 'other-device').path}/2026-08.jsonl',
    ).writeAsString('{}\n');

    await localeStore.write('de');
    await reportViewStateStore.write(
      const ReportViewState(
        preset: ReportRangePreset.today,
        projectIds: {'p1'},
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AppResetService makeService() => AppResetService(
    db: db,
    deviceId: 'this-device',
    effectiveSyncRoot: effectiveRoot,
    defaultSyncRoot: defaultRoot,
    clearSyncFolder: () async => syncFolderCleared = true,
    jiraCredentialsStore: jiraStore,
    personioCredentialsStore: personioStore,
    localeStore: localeStore,
    reportViewStateStore: reportViewStateStore,
  );

  test('resetEverything clears every drift table', () async {
    await db.projectsDao.createProject(
      name: 'Website Relaunch',
      colorHex: '#5B8DEF',
    );
    await db.timeEntriesDao.startEntry(deviceId: 'this-device');
    await db.appSettingsDao.updateSettings(dateFormat: 'us');
    await db.breakRuleTiersDao.createTier(
      deviceId: 'this-device',
      afterMinutes: 360,
      requiredBreakMinutes: 30,
    );

    await makeService().resetEverything();

    for (final table in db.allTables) {
      final rows = await db
          .customSelect('SELECT * FROM ${table.actualTableName}')
          .get();
      expect(
        rows,
        isEmpty,
        reason: 'expected ${table.actualTableName} to be empty after reset',
      );
    }
  });

  test(
    'resetEverything deletes this device\'s own log directory from both roots',
    () async {
      await makeService().resetEverything();

      expect(
        await deviceLogDir(effectiveRoot, 'this-device').exists(),
        isFalse,
      );
      expect(await deviceLogDir(defaultRoot, 'this-device').exists(), isFalse);
    },
  );

  test(
    'resetEverything never touches another device\'s log directory',
    () async {
      await makeService().resetEverything();

      expect(
        await deviceLogDir(effectiveRoot, 'other-device').exists(),
        isTrue,
      );
    },
  );

  test(
    'resetEverything clears the sync folder pointer, credentials, locale, and report filters',
    () async {
      await makeService().resetEverything();

      expect(syncFolderCleared, isTrue);
      expect(jiraStore.cleared, isTrue);
      expect(personioStore.cleared, isTrue);
      expect(await localeStore.read(), isNull);
      final reportViewState = await reportViewStateStore.read();
      expect(reportViewState.preset, ReportRangePreset.thisMonth);
      expect(reportViewState.projectIds, isEmpty);
    },
  );
}
