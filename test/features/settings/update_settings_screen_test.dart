import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/di/update_providers.dart';
import 'package:hickory/core/update/github_release_client.dart';
import 'package:hickory/core/update/update_checker.dart';
import 'package:hickory/core/update/update_installer.dart';
import 'package:hickory/core/update/update_progress.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/update_settings_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

class _FakeUpdateChecker extends UpdateChecker {
  _FakeUpdateChecker(this._result)
    : super(
        releaseClient: GithubReleaseClient(owner: 'test', repo: 'test'),
        platformAssetName: 'test.zip',
      );

  final UpdateInfo? _result;

  @override
  Future<UpdateInfo?> checkForUpdate() async => _result;
}

class _FakeUpdateInstaller extends UpdateInstaller {
  _FakeUpdateInstaller(
    this.extractedDir, {
    this.progressToEmit = const [],
    this.holdUntil,
  });

  final Directory extractedDir;

  /// Progress the fake reports before returning, so a test can assert what the
  /// screen renders mid-install.
  final List<UpdateProgress> progressToEmit;

  /// Blocks the fake after reporting, so the install stays in flight. Without
  /// it the whole install completes in one microtask drain and the finally
  /// block clears the progress before the test can pump a frame.
  final Future<void>? holdUntil;
  bool quitAndSwapCalled = false;

  @override
  Future<Directory> prepareUpdate(
    UpdateInfo update, {
    void Function(UpdateProgress)? onProgress,
  }) async {
    for (final progress in progressToEmit) {
      onProgress?.call(progress);
    }
    if (holdUntil != null) await holdUntil;
    return extractedDir;
  }

  @override
  Future<void> quitAndSwap(
    Directory extractedTopLevel, {
    required AppDatabase db,
    required SyncedWrites writes,
  }) async {
    quitAndSwapCalled = true;
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;
  late Directory extractedDir;
  late _FakeUpdateInstaller installer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync(
      'hickory_update_settings_test_sync_',
    );
    extractedDir = Directory.systemTemp.createTempSync(
      'hickory_update_settings_test_extracted_',
    );
    installer = _FakeUpdateInstaller(extractedDir);
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
    if (extractedDir.existsSync()) extractedDir.deleteSync(recursive: true);
  });

  Widget makeApp({UpdateInfo? checkResult}) => ProviderScope(
    overrides: [
      currentAppVersionProvider.overrideWith((ref) async => '1.1.0'),
      updateCheckerProvider.overrideWithValue(_FakeUpdateChecker(checkResult)),
      updateInstallerProvider.overrideWithValue(installer),
      appDatabaseProvider.overrideWithValue(db),
      syncedWritesProvider.overrideWith(
        (ref) async => SyncedWrites(
          db: db,
          logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: UpdateSettingsScreen()),
    ),
  );

  testWidgets('shows the current version', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('1.1.0'), findsOneWidget);
  });

  testWidgets(
    'checking for updates with none available shows the up-to-date message',
    (tester) async {
      await tester.pumpWidget(makeApp(checkResult: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text("You're on the latest version."), findsOneWidget);
    },
  );

  testWidgets(
    'checking for updates with one available shows the install button',
    (tester) async {
      const update = UpdateInfo(
        version: '1.2.0',
        notes: 'Bug fixes',
        downloadUrl: 'https://example.com/a.zip',
        checksumUrl: 'https://example.com/a.sha256',
        size: 1024,
      );
      await tester.pumpWidget(makeApp(checkResult: update));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1.2.0'), findsWidgets);
      expect(find.text('Install now'), findsOneWidget);
    },
  );

  testWidgets(
    'installing calls prepareUpdate and quitAndSwap on the installer',
    (tester) async {
      const update = UpdateInfo(
        version: '1.2.0',
        notes: '',
        downloadUrl: 'https://example.com/a.zip',
        checksumUrl: 'https://example.com/a.sha256',
        size: 1024,
      );
      await tester.pumpWidget(makeApp(checkResult: update));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install now'));
      await tester.pumpAndSettle();

      expect(installer.quitAndSwapCalled, isTrue);
    },
  );

  testWidgets(
    'shows a determinate bar with megabytes while downloading',
    (tester) async {
      // The fake reports download progress and then stops, so the screen stays
      // on the phase the assertion is about.
      final hold = Completer<void>();
      installer = _FakeUpdateInstaller(
        extractedDir,
        progressToEmit: const [
          UpdateDownloading(receivedBytes: 5 * 1024 * 1024, totalBytes: 20 * 1024 * 1024),
        ],
        holdUntil: hold.future,
      );
      const update = UpdateInfo(
        version: '1.2.0',
        notes: '',
        downloadUrl: 'https://example.com/a.zip',
        checksumUrl: 'https://example.com/a.sha256',
        size: 1024,
      );
      await tester.pumpWidget(makeApp(checkResult: update));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install now'));
      await tester.pump();

      expect(find.text('Downloading update … 5.0 of 20.0 MB'), findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        0.25,
      );

      // Let the install finish so no work is left pending at teardown.
      hold.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shows an indeterminate bar while verifying', (tester) async {
    final hold = Completer<void>();
    installer = _FakeUpdateInstaller(
      extractedDir,
      progressToEmit: const [UpdateVerifying()],
      holdUntil: hold.future,
    );
    const update = UpdateInfo(
      version: '1.2.0',
      notes: '',
      downloadUrl: 'https://example.com/a.zip',
      checksumUrl: 'https://example.com/a.sha256',
      size: 1024,
    );
    await tester.pumpWidget(makeApp(checkResult: update));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install now'));
    await tester.pump();

    expect(find.text('Verifying checksum …'), findsOneWidget);
    // No invented percentage for a phase that cannot report one.
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      isNull,
    );

    hold.complete();
    await tester.pumpAndSettle();
  });
}
