import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import 'report_view_controller.dart';
import 'report_view_state.dart';

/// Live filter panel for the Reports screen: project multi-select and a
/// billable/non-billable choice, both applied immediately through
/// [ReportViewController] as the user toggles them (no separate Apply step,
/// matching how the range presets already behave). [projects] is passed in
/// by the caller (already loaded via reportProjectsProvider) rather than
/// re-fetched here.
class ReportFilterDialog extends ConsumerWidget {
  const ReportFilterDialog({super.key, required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewState = ref.watch(reportViewControllerProvider).value;
    final controller = ref.read(reportViewControllerProvider.notifier);
    final selectedProjectIds = viewState?.projectIds ?? const <String>{};
    final billableFilter = viewState?.billableFilter ?? BillableFilter.all;

    return AlertDialog(
      title: Text(l10n.reportsFilterDialogTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.reportsFilterProjectsLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                l10n.reportsFilterProjectsHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ...projects.map(
                (project) => CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selectedProjectIds.contains(project.id),
                  title: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse(
                              project.colorHex.replaceFirst('#', '0xFF'),
                            ),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(child: Text(project.name)),
                    ],
                  ),
                  onChanged: (checked) {
                    final next = Set<String>.from(selectedProjectIds);
                    if (checked ?? false) {
                      next.add(project.id);
                    } else {
                      next.remove(project.id);
                    }
                    controller.setProjectIds(next);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.reportsFilterBillableLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.reportsFilterBillableAll),
                    selected: billableFilter == BillableFilter.all,
                    onSelected: (_) =>
                        controller.setBillableFilter(BillableFilter.all),
                  ),
                  ChoiceChip(
                    label: Text(l10n.reportsFilterBillableOnly),
                    selected: billableFilter == BillableFilter.billableOnly,
                    onSelected: (_) => controller.setBillableFilter(
                      BillableFilter.billableOnly,
                    ),
                  ),
                  ChoiceChip(
                    label: Text(l10n.reportsFilterBillableNonOnly),
                    selected: billableFilter == BillableFilter.nonBillableOnly,
                    onSelected: (_) => controller.setBillableFilter(
                      BillableFilter.nonBillableOnly,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => controller.resetFilters(),
          child: Text(l10n.reportsFilterReset),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
