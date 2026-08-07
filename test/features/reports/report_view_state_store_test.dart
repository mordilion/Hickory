import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'hickory_report_view_state_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('read returns the default state before any write', () async {
    final store = ReportViewStateStore(supportDirectory: tempDir);
    final state = await store.read();
    expect(state.preset, ReportRangePreset.thisMonth);
    expect(state.customRange, isNull);
    expect(state.projectIds, isEmpty);
    expect(state.billableFilter, BillableFilter.all);
  });

  test(
    'write then read round-trips a preset-based state, and persists across instances',
    () async {
      final store = ReportViewStateStore(supportDirectory: tempDir);
      const state = ReportViewState(
        preset: ReportRangePreset.today,
        projectIds: {'p1', 'p2'},
        billableFilter: BillableFilter.billableOnly,
      );

      await store.write(state);

      final read = await store.read();
      expect(read.preset, ReportRangePreset.today);
      expect(read.customRange, isNull);
      expect(read.projectIds, {'p1', 'p2'});
      expect(read.billableFilter, BillableFilter.billableOnly);
      final fresh = await ReportViewStateStore(
        supportDirectory: tempDir,
      ).read();
      expect(fresh.preset, ReportRangePreset.today);
    },
  );

  test('write then read round-trips a custom-range state', () async {
    final store = ReportViewStateStore(supportDirectory: tempDir);
    final range = DateTimeRange(
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 2, 1),
    );
    final state = ReportViewState(preset: null, customRange: range);

    await store.write(state);

    final read = await store.read();
    expect(read.preset, isNull);
    expect(read.customRange, range);
  });

  test(
    'read returns the default state for a corrupt file instead of throwing',
    () async {
      final file = File('${tempDir.path}/report_view_state.json');
      await file.writeAsString('{not valid json');

      final store = ReportViewStateStore(supportDirectory: tempDir);
      final state = await store.read();
      expect(state.preset, ReportRangePreset.thisMonth);
    },
  );

  test(
    'read returns the default state for an unrecognized preset name',
    () async {
      final file = File('${tempDir.path}/report_view_state.json');
      await file.writeAsString('{"preset": "someFuturePreset"}');

      final store = ReportViewStateStore(supportDirectory: tempDir);
      final state = await store.read();
      expect(state.preset, ReportRangePreset.thisMonth);
    },
  );
}
