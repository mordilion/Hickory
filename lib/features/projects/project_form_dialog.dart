import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import '../clients/client_form_dialog.dart';
import '../clients/clients_providers.dart';

const projectColorPalette = [
  '#5B8DEF',
  '#EF5B5B',
  '#5BEF8D',
  '#EFC75B',
  '#B85BEF',
  '#5BD3EF',
];

const _createNewClientSentinel = '__create_new_client__';

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

/// Formats [project]'s stored hourly rate (whole cents) as the decimal
/// string the rate `TextField` should start with. Returns an empty string
/// when there's no project or no rate set.
String _formatInitialRate(Project? project) {
  final cents = project?.hourlyRateCents;
  if (cents == null) return '';
  return (cents / 100).toStringAsFixed(2);
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
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ProjectFormDialogContent(ref: ref, project: project),
  );
}

/// Dialog body for [showProjectFormDialog]. A StatefulWidget so its
/// [TextEditingController]s are disposed via the framework's own element
/// teardown (State.dispose(), which only runs once this widget is actually
/// unmounted) rather than eagerly via `.whenComplete()` on the showDialog
/// future -- that future resolves as soon as Navigator.pop() is called,
/// which is before the dialog's exit transition finishes, so disposing the
/// controllers there raced with the still-mounted TextFields touching them
/// during the last few transition frames ("used after dispose"). Same
/// pattern as client_form_dialog.dart's _ClientFormDialogContent.
class _ProjectFormDialogContent extends StatefulWidget {
  const _ProjectFormDialogContent({required this.ref, required this.project});

  final WidgetRef ref;
  final Project? project;

  @override
  State<_ProjectFormDialogContent> createState() => _ProjectFormDialogContentState();
}

class _ProjectFormDialogContentState extends State<_ProjectFormDialogContent> {
  late final _nameController = TextEditingController(text: widget.project?.name ?? '');
  late final _rateController = TextEditingController(text: _formatInitialRate(widget.project));
  late final _currencyController = TextEditingController(text: widget.project?.currency ?? '');

  late String _selectedColor = widget.project?.colorHex ?? projectColorPalette.first;
  late String? _selectedClientId = widget.project?.clientId;
  // Bumped every time the inline "+ New client..." flow resolves (created or
  // cancelled). Combined into the client dropdown's key below to force a
  // fresh State even when _selectedClientId itself doesn't change -- see that
  // key's doc comment for why a plain rebuild isn't enough on cancel.
  var _clientPickerGeneration = 0;
  late bool _billable = widget.project?.billable ?? true;
  String? _rateError;

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final project = widget.project;
    return AlertDialog(
      title: Text(project == null ? l10n.projectsNewProjectTitle : l10n.projectsEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.projectsNameLabel),
            ),
            const SizedBox(height: 12),
            Consumer(
              builder: (context, ref, _) {
                final clients = ref.watch(activeClientsProvider).value ?? const <Client>[];
                final validIds = clients.map((c) => c.id).toSet();
                // The project's assigned client may have been archived since
                // this project was last edited (archiving is a first-class
                // action in the Clients settings editor). An archived client
                // is absent from `clients` above, so without this lookup the
                // dropdown would silently fall back to "No client" while
                // `_selectedClientId` still holds the archived id -- and an
                // unrelated save (e.g. just the color) would then overwrite
                // the DB with that still-correct id, but the UI would have
                // lied about it the whole time. Surface the archived client
                // explicitly instead so the user can see it and deliberately
                // change it.
                final archivedClients = ref.watch(archivedClientsProvider).value ?? const <Client>[];
                final currentClientId = _selectedClientId;
                Client? archivedSelected;
                if (currentClientId != null && !validIds.contains(currentClientId)) {
                  for (final client in archivedClients) {
                    if (client.id != currentClientId) continue;
                    archivedSelected = client;
                    break;
                  }
                }
                if (archivedSelected != null) validIds.add(archivedSelected.id);
                return DropdownButtonFormField<String?>(
                  // DropdownButtonFormField's internal FormFieldState only
                  // re-syncs its displayed value from initialValue in
                  // didUpdateWidget when initialValue itself changed
                  // (see _DropdownButtonFormFieldState.didUpdateWidget in
                  // the Flutter SDK) -- a rebuild with an *unchanged*
                  // initialValue is a no-op, leaving the dropdown
                  // showing whatever it locally applied on the last tap
                  // (e.g. the "+ New client..." sentinel). Keying on
                  // (_selectedClientId, _clientPickerGeneration) forces a
                  // brand-new State -- and therefore a fresh initialValue
                  // read via initState, bypassing didUpdateWidget's
                  // equality check entirely -- both when _selectedClientId
                  // changes (a client was picked/created) and when only
                  // the generation bumps (the inline create dialog was
                  // cancelled, so _selectedClientId is unchanged but the
                  // dropdown's stale sentinel selection still needs
                  // clearing).
                  key: ValueKey((_selectedClientId, _clientPickerGeneration)),
                  initialValue: validIds.contains(_selectedClientId) ? _selectedClientId : null,
                  decoration: InputDecoration(labelText: l10n.projectsClientLabel),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l10n.projectsClientNone)),
                    for (final client in clients)
                      DropdownMenuItem(value: client.id, child: Text(client.name)),
                    if (archivedSelected != null)
                      DropdownMenuItem(
                        value: archivedSelected.id,
                        child: Text(l10n.projectsClientArchivedLabel(archivedSelected.name)),
                      ),
                    DropdownMenuItem(
                      value: _createNewClientSentinel,
                      child: Text(l10n.projectsClientCreateNew),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value != _createNewClientSentinel) {
                      setState(() => _selectedClientId = value);
                      return;
                    }
                    final created = await showClientFormDialog(context, ref);
                    // Call setState unconditionally, even when cancelled
                    // (created == null): the dropdown's own FormFieldState
                    // already applied the sentinel value to its displayed
                    // selection the moment onChanged fired, before this
                    // awaited dialog opened. Bumping _clientPickerGeneration
                    // here (always, not just on success) changes the
                    // dropdown's key even when _selectedClientId itself
                    // doesn't -- required so the cancelled case also gets a
                    // fresh State; see the key's doc comment above for why a
                    // plain rebuild alone can't resync the display in that
                    // case.
                    setState(() {
                      _clientPickerGeneration++;
                      if (created != null) _selectedClientId = created.id;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in projectColorPalette)
                  GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: CircleAvatar(
                      backgroundColor: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                      radius: 14,
                      child: _selectedColor == color
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
              value: _billable,
              onChanged: (value) => setState(() => _billable = value),
            ),
            TextField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.projectsHourlyRateLabel,
                errorText: _rateError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currencyController,
              decoration: InputDecoration(labelText: l10n.projectsCurrencyLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            final rawRate = _rateController.text.trim();
            final rateCents = _parseRateCents(rawRate);
            if (rawRate.isNotEmpty && rateCents == null) {
              setState(() => _rateError = l10n.projectsInvalidRateError);
              return;
            }
            final currency = _currencyController.text.trim();
            final writes = await widget.ref.read(syncedWritesProvider.future);
            if (project == null) {
              await writes.createProject(
                name: name,
                colorHex: _selectedColor,
                clientId: _selectedClientId,
                billable: _billable,
                hourlyRateCents: rateCents,
                currency: currency.isEmpty ? null : currency,
              );
            } else {
              await writes.updateProject(
                project.id,
                name: Value(name),
                colorHex: Value(_selectedColor),
                clientId: Value(_selectedClientId),
                billable: Value(_billable),
                hourlyRateCents: Value(rateCents),
                currency: Value(currency.isEmpty ? null : currency),
              );
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(project == null ? l10n.projectsCreateButton : l10n.commonSave),
        ),
      ],
    );
  }
}
