import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/report_view_controller.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('report_view_controller_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          reportViewStateStoreProvider.overrideWith(
            (ref) async => ReportViewStateStore(supportDirectory: tempDir),
          ),
        ],
      );

  test('starts at the default state when nothing is stored', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final state = await container.read(reportViewControllerProvider.future);
    expect(state.preset, ReportRangePreset.thisMonth);
    expect(state.projectIds, isEmpty);
  });

  test('setPreset updates state and persists across containers', () async {
    final first = makeContainer();
    await first.read(reportViewControllerProvider.future);
    await first.read(reportViewControllerProvider.notifier).setPreset(ReportRangePreset.today);
    expect(first.read(reportViewControllerProvider).value?.preset, ReportRangePreset.today);
    first.dispose();

    final second = makeContainer();
    addTearDown(second.dispose);
    final state = await second.read(reportViewControllerProvider.future);
    expect(state.preset, ReportRangePreset.today);
  });

  test('setCustomRange clears the preset and persists', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(reportViewControllerProvider.future);
    final range = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 8));

    await container.read(reportViewControllerProvider.notifier).setCustomRange(range);

    final state = container.read(reportViewControllerProvider).value!;
    expect(state.preset, isNull);
    expect(state.customRange, range);
  });

  test('setProjectIds and setBillableFilter update independently of range', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(reportViewControllerProvider.future);
    final controller = container.read(reportViewControllerProvider.notifier);

    await controller.setProjectIds({'p1'});
    await controller.setBillableFilter(BillableFilter.nonBillableOnly);

    final state = container.read(reportViewControllerProvider).value!;
    expect(state.preset, ReportRangePreset.thisMonth);
    expect(state.projectIds, {'p1'});
    expect(state.billableFilter, BillableFilter.nonBillableOnly);
  });

  test('resetFilters clears filters but keeps the current range', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(reportViewControllerProvider.future);
    final controller = container.read(reportViewControllerProvider.notifier);
    await controller.setPreset(ReportRangePreset.today);
    await controller.setProjectIds({'p1'});
    await controller.setBillableFilter(BillableFilter.billableOnly);

    await controller.resetFilters();

    final state = container.read(reportViewControllerProvider).value!;
    expect(state.preset, ReportRangePreset.today);
    expect(state.projectIds, isEmpty);
    expect(state.billableFilter, BillableFilter.all);
  });
}
