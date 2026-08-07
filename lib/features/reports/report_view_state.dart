import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show DateTimeRange;

import 'reports_providers.dart';

enum BillableFilter { all, billableOnly, nonBillableOnly }

/// Immutable snapshot of everything the Reports screen remembers across
/// restarts: the selected range (as a preset, or explicit custom bounds when
/// [preset] is null) plus the active filters. Empty [projectIds] means "all
/// projects" (not "no projects").
@immutable
class ReportViewState {
  const ReportViewState({
    this.preset = ReportRangePreset.thisMonth,
    this.customRange,
    this.projectIds = const {},
    this.billableFilter = BillableFilter.all,
  }) : assert(
        preset != null || customRange != null,
        'ReportViewState requires either a preset or a customRange',
      );

  final ReportRangePreset? preset;
  final DateTimeRange? customRange;
  final Set<String> projectIds;
  final BillableFilter billableFilter;

  // customRange is always set together with a null preset (see
  // ReportViewController.setPreset/setCustomRange in report_view_controller.dart),
  // so the ! here reflects that invariant rather than an unchecked assumption.
  DateTimeRange get range => preset == null ? customRange! : rangeForPreset(preset!);

  int get activeFilterCount =>
      (projectIds.isNotEmpty ? 1 : 0) + (billableFilter != BillableFilter.all ? 1 : 0);

  ReportViewState copyWith({
    ReportRangePreset? Function()? preset,
    DateTimeRange? Function()? customRange,
    Set<String>? projectIds,
    BillableFilter? billableFilter,
  }) {
    return ReportViewState(
      preset: preset == null ? this.preset : preset(),
      customRange: customRange == null ? this.customRange : customRange(),
      projectIds: projectIds ?? this.projectIds,
      billableFilter: billableFilter ?? this.billableFilter,
    );
  }
}
