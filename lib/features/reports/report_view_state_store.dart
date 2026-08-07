import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:path/path.dart' as p;

import 'report_view_state.dart';
import 'reports_providers.dart';

/// Persists the Reports screen's last-used range and filters as a plain
/// JSON file in the app-support directory. Device-local only (deliberately
/// not synced -- this is a UI viewing preference for this device, not data,
/// same reasoning as WindowBoundsStore/LocaleStore). Takes the support
/// directory as a constructor parameter so it's trivially testable against
/// a temp directory -- the real caller passes
/// `await getApplicationSupportDirectory()`.
class ReportViewStateStore {
  ReportViewStateStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _file => File(p.join(supportDirectory.path, 'report_view_state.json'));

  /// Returns the default state (this-month preset, no filters) if the file
  /// is missing, unreadable, or contains an unrecognized preset/billable
  /// value -- same fall-back-to-defaults contract as WindowBoundsStore.read().
  Future<ReportViewState> read() async {
    try {
      final content = await _file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final presetName = json['preset'] as String?;
      final preset = presetName == null ? null : ReportRangePreset.values.byName(presetName);

      final customStart = json['customRangeStart'] as String?;
      final customEnd = json['customRangeEnd'] as String?;
      final customRange = (customStart != null && customEnd != null)
          ? DateTimeRange(start: DateTime.parse(customStart), end: DateTime.parse(customEnd))
          : null;

      final billableName = json['billableFilter'] as String?;
      final billableFilter =
          billableName == null ? BillableFilter.all : BillableFilter.values.byName(billableName);

      final projectIds =
          (json['projectIds'] as List<dynamic>?)?.cast<String>().toSet() ?? const <String>{};

      return ReportViewState(
        preset: preset,
        customRange: customRange,
        projectIds: projectIds,
        billableFilter: billableFilter,
      );
    } on Object {
      // Missing file, corrupt JSON, or an unrecognized preset/billable-filter
      // name (e.g. from a newer/older app version) -- fall back to defaults
      // rather than surfacing a broken state to the Reports screen.
      return const ReportViewState();
    }
  }

  Future<void> write(ReportViewState state) async {
    await _file.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'preset': state.preset?.name,
        'customRangeStart': state.customRange?.start.toIso8601String(),
        'customRangeEnd': state.customRange?.end.toIso8601String(),
        'projectIds': state.projectIds.toList(),
        'billableFilter': state.billableFilter.name,
      }),
    );
  }
}
