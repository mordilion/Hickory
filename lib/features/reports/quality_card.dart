import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'reports_providers.dart';

/// The Reports dashboard's tracking-quality block: what is missing from
/// the range, rather than what is in it.
///
/// Every line states a figure *and* what it means — a bare "2" next to an
/// icon would leave the reader guessing at exactly the moment the app is
/// telling them something is wrong. A clean range says so in one sentence
/// instead of showing three zeroes.
class QualityCard extends ConsumerWidget {
  const QualityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final figures = ref.watch(qualityFiguresProvider).value;
    if (figures == null) return const SizedBox.shrink();

    final absences = figures.absenceDaysByTypeName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.reportsQualityTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (figures.isClean)
              Text(l10n.reportsQualityClean, style: theme.textTheme.bodyMedium),
            if (figures.unbookedWorkDays.isNotEmpty)
              _Line(
                icon: Icons.event_busy_outlined,
                text: l10n.reportsQualityUnbooked(figures.unbookedWorkDays.length),
              ),
            if (figures.shortBreakDays.isNotEmpty)
              _Line(
                icon: Icons.free_breakfast_outlined,
                text: l10n.reportsQualityShortBreak(figures.shortBreakDays.length),
              ),
            if (figures.failedPushCount > 0)
              _Line(
                icon: Icons.cloud_off_outlined,
                text: l10n.reportsQualityFailedPushes(figures.failedPushCount),
              ),
            if (absences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.reportsQualityAbsences, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              for (final entry in absences.entries)
                Text('${entry.key}: ${entry.value}', style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// One finding: an icon that repeats what the sentence says, never
/// replaces it.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}
