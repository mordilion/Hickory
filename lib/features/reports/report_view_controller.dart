import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'report_view_state.dart';
import 'report_view_state_store.dart';
import 'reports_providers.dart';

part 'report_view_controller.g.dart';

@Riverpod(keepAlive: true)
Future<ReportViewStateStore> reportViewStateStore(Ref ref) async =>
    ReportViewStateStore(
      supportDirectory: await getApplicationSupportDirectory(),
    );

/// The Reports screen's remembered range + filters (see [ReportViewState]).
/// Loaded once from disk on first use and kept alive for the app's
/// lifetime -- same pattern as LocaleController.
@Riverpod(keepAlive: true)
class ReportViewController extends _$ReportViewController {
  @override
  Future<ReportViewState> build() async {
    final store = await ref.watch(reportViewStateStoreProvider.future);
    return store.read();
  }

  Future<void> _update(ReportViewState Function(ReportViewState) update) async {
    final next = update(state.value ?? const ReportViewState());
    // State first: the change applies to the running session even when
    // persisting fails (same precaution as LocaleController.setLocale).
    state = AsyncData(next);
    try {
      final store = await ref.read(reportViewStateStoreProvider.future);
      await store.write(next);
    } catch (error) {
      debugPrint('Failed to persist report view state: $error');
    }
  }

  Future<void> setPreset(ReportRangePreset preset) =>
      _update((s) => s.copyWith(preset: () => preset, customRange: () => null));

  Future<void> setCustomRange(DateTimeRange range) =>
      _update((s) => s.copyWith(preset: () => null, customRange: () => range));

  Future<void> setProjectIds(Set<String> ids) =>
      _update((s) => s.copyWith(projectIds: ids));

  Future<void> setBillableFilter(BillableFilter filter) =>
      _update((s) => s.copyWith(billableFilter: filter));

  Future<void> resetFilters() => _update(
    (s) => s.copyWith(projectIds: {}, billableFilter: BillableFilter.all),
  );
}
