import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import 'reports_providers.dart';

/// The Reports dashboard's tracking-quality block: what is missing from
/// the range, rather than what is in it.
///
/// Every line states a figure *and* what it means — a bare "2" next to an
/// icon would leave the reader guessing at exactly the moment the app is
/// telling them something is wrong. A clean range says so in one sentence
/// instead of showing three zeroes.
///
/// The two lines that stand for a set of days open on a tap and name them.
/// The count says that something is wrong, the dates say where to go and
/// fix it, and the days are already in hand — only the length of the list
/// was being shown.
class QualityCard extends ConsumerStatefulWidget {
  const QualityCard({super.key});

  @override
  ConsumerState<QualityCard> createState() => _QualityCardState();
}

class _QualityCardState extends ConsumerState<QualityCard> {
  /// Which day lists are open, by their line's key. Independent toggles:
  /// someone comparing the unbooked days with the short-break ones wants
  /// both at once.
  final _open = <String>{};

  void _toggle(String key) {
    setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final figures = ref.watch(qualityFiguresProvider).value;
    if (figures == null) return const SizedBox.shrink();

    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final languageCode = Localizations.localeOf(context).languageCode;
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
                days: figures.unbookedWorkDays,
                dateStyle: dateStyle,
                languageCode: languageCode,
                expanded: _open.contains('unbooked'),
                onToggle: () => _toggle('unbooked'),
              ),
            if (figures.shortBreakDays.isNotEmpty)
              _Line(
                icon: Icons.free_breakfast_outlined,
                text: l10n.reportsQualityShortBreak(figures.shortBreakDays.length),
                days: figures.shortBreakDays,
                dateStyle: dateStyle,
                languageCode: languageCode,
                expanded: _open.contains('shortBreak'),
                onToggle: () => _toggle('shortBreak'),
              ),
            if (figures.failedPushCount > 0)
              // No days of its own: the failed pushes are listed per entry
              // on the Sync tab, which is also where they can be retried.
              _Line(
                icon: Icons.cloud_off_outlined,
                text: l10n.reportsQualityFailedPushes(figures.failedPushCount),
              ),
            if (absences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.reportsQualityAbsences, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              for (final entry in absences.entries)
                Text(
                  // Days, not rows: a half day is 0.5 and has to read that
                  // way in the reader's own notation — a bare toString
                  // writes "10.5", which German reads as a thousands
                  // separator, and "11.0" for a whole number.
                  '${entry.key}: ${NumberFormat.decimalPattern(languageCode).format(entry.value)}',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One finding: an icon that repeats what the sentence says, never
/// replaces it, and — where the finding stands for a set of days — the
/// dates themselves behind a tap.
class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.text,
    this.days = const [],
    this.dateStyle = DateFormatStyle.iso,
    this.languageCode = 'en',
    this.expanded = false,
    this.onToggle,
  });

  final IconData icon;
  final String text;

  /// The days this finding stands for. Empty when the finding is only a
  /// count, in which case the line is plain text rather than a control
  /// that promises something it cannot show.
  final List<DateTime> days;
  final DateFormatStyle dateStyle;
  final String languageCode;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 8),
        Text(text),
        if (days.isNotEmpty) ...[
          const SizedBox(width: 4),
          Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: muted),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (days.isEmpty)
            row
          else
            Semantics(
              button: true,
              expanded: expanded,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: row,
                ),
              ),
            ),
          if (expanded && days.isNotEmpty)
            Padding(
              // Indented past the icon, so the dates read as belonging to
              // the line above them.
              padding: const EdgeInsets.only(left: 30, top: 4, bottom: 2),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final day in days)
                    Text(
                      formatDate(day, dateStyle, languageCode),
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
