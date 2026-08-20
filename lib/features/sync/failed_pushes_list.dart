import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import 'failed_pushes.dart';

/// The entries whose last push failed, each with its date and the reason the
/// sync service stored, and each tappable to open the entry — the Sync tab's
/// counts say that something failed but not what or where (see
/// docs/superpowers/specs/2026-08-19-sync-error-visibility-design.md §5).
///
/// Presentational only: [onTapEntry] carries the Riverpod-dependent behavior,
/// so this stays a plain [StatelessWidget] usable for both services. Renders
/// nothing when [failed] is empty — a "nothing failed" message would be noise
/// in a tab the user opens to do something else.
class FailedPushesList extends StatelessWidget {
  const FailedPushesList({
    super.key,
    required this.failed,
    required this.fallbackError,
    required this.dateStyle,
    required this.localeName,
    required this.onTapEntry,
  });

  final List<FailedPush> failed;

  /// Shown for a row whose message was never stored.
  final String fallbackError;
  final DateFormatStyle dateStyle;
  final String localeName;
  final void Function(TimeEntry entry) onTapEntry;

  @override
  Widget build(BuildContext context) {
    if (failed.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(l10n.syncFailedEntriesTitle, style: theme.textTheme.titleSmall),
        for (final push in failed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              push.entry.description?.isNotEmpty == true
                  ? push.entry.description!
                  : l10n.entriesNoDescription,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(push.entry.startAt, dateStyle, localeName)),
                // Kept on its own line rather than appended to the date: the
                // stored message is a sentence of its own and can be long.
                Text(
                  push.error ?? fallbackError,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            onTap: () => onTapEntry(push.entry),
          ),
      ],
    );
  }
}
