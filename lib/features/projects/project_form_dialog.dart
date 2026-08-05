import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';

const projectColorPalette = [
  '#5B8DEF',
  '#EF5B5B',
  '#5BEF8D',
  '#EFC75B',
  '#B85BEF',
  '#5BD3EF',
];

/// Parses a user-entered hourly-rate string ("95", "95.50", "95,50") into
/// whole cents. Returns null both for an empty string (no rate set) and for
/// unparseable input -- the submit handler tells the two apart via the raw
/// text itself before deciding whether to show an error.
int? _parseRateCents(String raw) {
  if (raw.isEmpty) return null;
  final value = double.tryParse(raw.replaceAll(',', '.'));
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

/// Shows the create/edit dialog for a project. Pass [project] to edit an
/// existing one (fields pre-filled, submit calls SyncedWrites.updateProject
/// with only this form's fields); omit it to create a new one (submit calls
/// SyncedWrites.createProject) -- matches the previous standalone "new
/// project" dialog's create behavior exactly. See
/// docs/superpowers/specs/2026-08-04-project-editing-design.md.
Future<void> showProjectFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Project? project,
}) {
  final nameController = TextEditingController(text: project?.name ?? '');
  final initialRateCents = project?.hourlyRateCents;
  final rateController = TextEditingController(
    text: initialRateCents == null ? '' : (initialRateCents / 100).toStringAsFixed(2),
  );
  final currencyController = TextEditingController(text: project?.currency ?? '');
  // Declared here (not inside `builder:`) so a route rebuild -- e.g. the
  // app's locale changing while this dialog is open -- can't silently
  // reset the user's in-progress color/billable choice back to the
  // project's original values. See break_rule_tiers_editor.dart's `_add`
  // for the same precaution.
  var selectedColor = project?.colorHex ?? projectColorPalette.first;
  var billable = project?.billable ?? true;
  String? rateError;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(project == null ? l10n.projectsNewProjectTitle : l10n.projectsEditTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(labelText: l10n.projectsNameLabel),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in projectColorPalette)
                        GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = color),
                          child: CircleAvatar(
                            backgroundColor: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                            radius: 14,
                            child: selectedColor == color
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.projectsBillableLabel),
                    value: billable,
                    onChanged: (value) => setDialogState(() => billable = value),
                  ),
                  TextField(
                    controller: rateController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.projectsHourlyRateLabel,
                      errorText: rateError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: currencyController,
                    decoration: InputDecoration(labelText: l10n.projectsCurrencyLabel),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final rawRate = rateController.text.trim();
                  final rateCents = _parseRateCents(rawRate);
                  if (rawRate.isNotEmpty && rateCents == null) {
                    setDialogState(() => rateError = l10n.projectsInvalidRateError);
                    return;
                  }
                  final currency = currencyController.text.trim();
                  final writes = await ref.read(syncedWritesProvider.future);
                  if (project == null) {
                    await writes.createProject(
                      name: name,
                      colorHex: selectedColor,
                      billable: billable,
                      hourlyRateCents: rateCents,
                      currency: currency.isEmpty ? null : currency,
                    );
                  } else {
                    await writes.updateProject(
                      project.id,
                      name: Value(name),
                      colorHex: Value(selectedColor),
                      billable: Value(billable),
                      hourlyRateCents: Value(rateCents),
                      currency: Value(currency.isEmpty ? null : currency),
                    );
                  }
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: Text(project == null ? l10n.projectsCreateButton : l10n.commonSave),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    nameController.dispose();
    rateController.dispose();
    currencyController.dispose();
  });
}
