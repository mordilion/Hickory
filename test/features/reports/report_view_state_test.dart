import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  group('ReportViewState.range', () {
    test('resolves via rangeForPreset when preset is set', () {
      const state = ReportViewState(preset: ReportRangePreset.all);
      expect(state.range, rangeForPreset(ReportRangePreset.all));
    });

    test('resolves customRange when preset is null', () {
      final customRange = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 2, 1));
      final state = ReportViewState(preset: null, customRange: customRange);
      expect(state.range, customRange);
    });
  });

  group('ReportViewState.copyWith', () {
    test('setting a custom range together with a null preset nulls out the preset', () {
      const state = ReportViewState(preset: ReportRangePreset.thisWeek);
      final customRange = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 8));

      final next = state.copyWith(preset: () => null, customRange: () => customRange);

      expect(next.preset, isNull);
      expect(next.customRange, customRange);
    });

    test('switching back to a preset together with a null custom range clears it', () {
      final customRange = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 8));
      final state = ReportViewState(preset: null, customRange: customRange);

      final next = state.copyWith(preset: () => ReportRangePreset.thisMonth, customRange: () => null);

      expect(next.preset, ReportRangePreset.thisMonth);
      expect(next.customRange, isNull);
    });

    test('updating projectIds/billableFilter leaves the range untouched', () {
      const state = ReportViewState(preset: ReportRangePreset.thisMonth);

      final next = state.copyWith(projectIds: {'p1'}, billableFilter: BillableFilter.billableOnly);

      expect(next.preset, ReportRangePreset.thisMonth);
      expect(next.projectIds, {'p1'});
      expect(next.billableFilter, BillableFilter.billableOnly);
    });
  });

  group('ReportViewState.activeFilterCount', () {
    test('is 0 with no filters', () {
      expect(const ReportViewState().activeFilterCount, 0);
    });

    test('counts project selection and billable filter independently', () {
      expect(const ReportViewState(projectIds: {'p1'}).activeFilterCount, 1);
      expect(
        const ReportViewState(billableFilter: BillableFilter.nonBillableOnly).activeFilterCount,
        1,
      );
      expect(
        const ReportViewState(
          projectIds: {'p1'},
          billableFilter: BillableFilter.billableOnly,
        ).activeFilterCount,
        2,
      );
    });
  });
}
