import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/absence_providers.dart';
import '../../core/di/app_settings_provider.dart';
import '../../core/di/database_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import 'settings_editor_support.dart';

/// Settings editor for the absence feature: the global switch, and the
/// user's own list of absence types.
///
/// Nothing is seeded automatically. Creating a default set at database
/// creation would have every device create its own "Vacation" row, all of
/// which would then sync into a pile of duplicates; the standard set is
/// therefore an explicit button the user presses once, on one device.
class AbsenceTypesEditor extends ConsumerStatefulWidget {
  const AbsenceTypesEditor({super.key});

  @override
  ConsumerState<AbsenceTypesEditor> createState() => _AbsenceTypesEditorState();
}

class _AbsenceTypesEditorState extends ConsumerState<AbsenceTypesEditor>
    with SettingsWriteGuard {
  @override
  String saveErrorMessage(AppLocalizations l10n) => l10n.settingsAbsencesSaveError;

  Future<void> _setEnabled(bool enabled) {
    return guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(absenceTrackingEnabled: enabled);
    });
  }

  Future<void> _addStandardTypes() {
    final l10n = AppLocalizations.of(context);
    // Named in the user's language at creation time: the name is user data
    // from here on, editable and synced like any other type they add.
    final standard = <(String, bool)>[
      (l10n.settingsAbsenceTypeDefaultVacation, true),
      (l10n.settingsAbsenceTypeDefaultSick, true),
      (l10n.settingsAbsenceTypeDefaultHoliday, true),
      (l10n.settingsAbsenceTypeDefaultUnpaid, false),
    ];
    return guardedWrite(() async {
      final deviceId = await ref.read(deviceIdProvider.future);
      final writes = await ref.read(syncedWritesProvider.future);
      for (final (index, entry) in standard.indexed) {
        await writes.createAbsenceType(
          deviceId: deviceId,
          name: entry.$1,
          paid: entry.$2,
          sortOrder: index,
        );
      }
    });
  }

  Future<void> _delete(AbsenceType type) async {
    final l10n = AppLocalizations.of(context);
    // The synced tables carry no foreign keys, so nothing below this line
    // would stop a delete from orphaning absence rows. Checked here, and
    // refused with the count rather than a bare "cannot delete".
    final inUse = await ref.read(appDatabaseProvider).absencesDao.countByType(type.id);
    if (inUse > 0) {
      if (mounted) showMessage(l10n.settingsAbsenceTypeInUse(inUse));
      return;
    }
    await guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.deleteAbsenceType(type.id);
    });
  }

  Future<void> _edit(AbsenceType? existing) async {
    final result = await showDialog<({String name, bool paid})>(
      context: context,
      builder: (_) => _AbsenceTypeDialog(existing: existing),
    );
    if (result == null) return;
    await guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      if (existing != null) {
        await writes.updateAbsenceType(existing.id, name: result.name, paid: result.paid);
        return;
      }
      final deviceId = await ref.read(deviceIdProvider.future);
      final types = ref.read(absenceTypesProvider).value ?? const <AbsenceType>[];
      // One past the highest existing order, not the list length: deleting
      // a type in the middle leaves a gap, and reusing the length would
      // then collide with a row that already has that value.
      final nextOrder = types.isEmpty
          ? 0
          : types.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
      await writes.createAbsenceType(
        deviceId: deviceId,
        name: result.name,
        paid: result.paid,
        sortOrder: nextOrder,
      );
    });
  }

  /// Moves [type] one place up or down. Spec section 2 lists reordering
  /// alongside add, rename and delete.
  Future<void> _move(AbsenceType type, int delta) {
    final types = [...?ref.read(absenceTypesProvider).value];
    final index = types.indexWhere((t) => t.id == type.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= types.length) return Future.value();
    types.insert(target, types.removeAt(index));
    // Renumbered from zero rather than swapping the two rows' values: two
    // devices that each added a type while offline can produce duplicate
    // sortOrders, and swapping two equal values would silently do nothing.
    return guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      for (final (position, moved) in types.indexed) {
        if (moved.sortOrder == position) continue;
        await writes.updateAbsenceType(moved.id, sortOrder: position);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final types = ref.watch(absenceTypesProvider).value ?? const <AbsenceType>[];
    if (settings == null) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsAbsencesEnabled),
          subtitle: Text(l10n.settingsAbsencesEnabledDescription),
          value: settings.absenceTrackingEnabled,
          onChanged: busy ? null : _setEnabled,
        ),
        const Divider(),
        const SizedBox(height: 8),
        Text(l10n.settingsAbsenceTypesTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final type in types)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(type.name),
            subtitle: Text(
              type.paid ? l10n.settingsAbsenceTypePaid : l10n.settingsAbsenceTypeUnpaid,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey('moveAbsenceTypeUp-${type.id}'),
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: l10n.settingsAbsenceTypeMoveUp,
                  onPressed:
                      busy || type == types.first ? null : () => _move(type, -1),
                ),
                IconButton(
                  key: ValueKey('moveAbsenceTypeDown-${type.id}'),
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: l10n.settingsAbsenceTypeMoveDown,
                  onPressed:
                      busy || type == types.last ? null : () => _move(type, 1),
                ),
                IconButton(
                  key: ValueKey('editAbsenceType-${type.id}'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.commonEdit,
                  onPressed: busy ? null : () => _edit(type),
                ),
                IconButton(
                  key: ValueKey('deleteAbsenceType-${type.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.commonDelete,
                  onPressed: busy ? null : () => _delete(type),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => _edit(null),
              icon: const Icon(Icons.add),
              label: Text(l10n.settingsAbsenceTypeAdd),
            ),
            if (types.isEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: busy ? null : _addStandardTypes,
                child: Text(l10n.settingsAbsenceTypeAddStandard),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Name and paid flag for a new or edited type. Returns null on cancel.
class _AbsenceTypeDialog extends StatefulWidget {
  const _AbsenceTypeDialog({required this.existing});

  final AbsenceType? existing;

  @override
  State<_AbsenceTypeDialog> createState() => _AbsenceTypeDialogState();
}

class _AbsenceTypeDialogState extends State<_AbsenceTypeDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late bool _paid = widget.existing?.paid ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l10n.settingsAbsenceTypeAdd
            : l10n.settingsAbsenceTypesTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('absenceTypeName'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.settingsAbsenceTypeName),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAbsenceTypePaid),
            value: _paid,
            onChanged: (value) => setState(() => _paid = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, paid: _paid));
          },
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
