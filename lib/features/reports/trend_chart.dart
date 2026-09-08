import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/format/iso_week.dart';
import '../../l10n/app_localizations.dart';
import 'reports_providers.dart';
import 'trend_calculations.dart';

/// The colour a bar in [TrendBarStatus] is drawn in.
///
/// The same three the balance tiles use, so one glance covers the whole
/// dashboard: primary for a settled or beaten target, error for falling
/// short, a neutral outline for a day that was never owed. Colour is never
/// the only carrier — the target line shows the same relation, and every
/// bar carries its figures as an accessible label.
Color trendBarColor(TrendBarStatus status, ColorScheme scheme) => switch (status) {
  TrendBarStatus.surplus => scheme.primary,
  TrendBarStatus.deficit => scheme.error,
  TrendBarStatus.noTarget => scheme.outline,
};

/// Worked time per day (or per week over a long range) against the target,
/// drawn by hand: the project carries no charting dependency and one bar
/// chart does not warrant adding one.
///
/// Every bar also exists as a `Semantics` node carrying its date and its
/// two figures. That is not decoration — the hover tooltip has no keyboard
/// or screen-reader equivalent, so without it the whole block would be
/// invisible to anyone not using a mouse.
class TrendChart extends ConsumerWidget {
  const TrendChart({super.key});

  static const _chartHeight = 160.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final trend = ref.watch(trendBarsProvider).value;
    final bars = trend?.bars ?? const <TrendBar>[];
    final granularity = trend?.granularity ?? TrendGranularity.day;
    final settings = ref.watch(appSettingsProvider).value;
    final timeStyle = settings.timeStyle;
    final localeName = Localizations.localeOf(context).languageCode;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.reportsTrendTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (bars.isEmpty)
              Text(l10n.reportsTrendEmpty, style: theme.textTheme.bodyMedium)
            else
              SizedBox(
                key: const ValueKey('trendBars'),
                height: _chartHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final bar in bars)
                      Expanded(
                        child: Tooltip(
                          message: _label(bar, l10n, granularity, localeName, timeStyle),
                          child: Semantics(
                            label: _label(bar, l10n, granularity, localeName, timeStyle),
                            child: CustomPaint(
                              painter: _BarPainter(
                                bar: bar,
                                maxValue: _maxValue(bars),
                                barColor: trendBarColor(
                                  statusOf(bar),
                                  theme.colorScheme,
                                ),
                                targetColor: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The tallest figure any bar carries, so the target line always falls
  /// inside the box even on a day that was massively over or under.
  static Duration _maxValue(List<TrendBar> bars) {
    var max = Duration.zero;
    for (final bar in bars) {
      final covered = bar.worked + bar.credit;
      if (covered > max) max = covered;
      if (bar.target > max) max = bar.target;
    }
    return max;
  }

  /// What a bar stands for, spelled the way its granularity reads: a day
  /// date, "KW 37" for a week, the month's name for a month. A day date on
  /// a bar covering a whole week would read as if only that day were in it.
  static String _periodLabel(
    TrendBar bar,
    AppLocalizations l10n,
    TrendGranularity granularity,
    String localeName,
  ) => switch (granularity) {
    TrendGranularity.day => DateFormat.Md(localeName).format(bar.start),
    TrendGranularity.week => l10n.entriesWeekLabel(isoWeekNumber(bar.start)),
    TrendGranularity.month => DateFormat.yMMM(localeName).format(bar.start),
  };

  static String _label(
    TrendBar bar,
    AppLocalizations l10n,
    TrendGranularity granularity,
    String localeName,
    TimeFormatStyle timeStyle,
  ) => l10n.reportsTrendBarLabel(
    _periodLabel(bar, l10n, granularity, localeName),
    // Worked plus paid absence: the figure the bar's height and colour are
    // built from. Reporting tracked time alone would have a screen reader
    // announce "0:00 of 8:00" beside a bar painted as settled.
    formatDuration(bar.worked + bar.credit, timeStyle),
    formatDuration(bar.target, timeStyle),
  );
}

/// One bar plus the slice of the target line that crosses it.
class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.bar,
    required this.maxValue,
    required this.barColor,
    required this.targetColor,
  });

  final TrendBar bar;
  final Duration maxValue;
  final Color barColor;
  final Color targetColor;

  @override
  void paint(Canvas canvas, Size size) {
    final max = maxValue.inMinutes;
    if (max <= 0) return;

    const gap = 2.0;
    final barWidth = (size.width - gap * 2).clamp(1.0, size.width);
    final workedHeight = size.height * bar.worked.inMinutes / max;
    canvas.drawRect(
      Rect.fromLTWH(gap, size.height - workedHeight, barWidth, workedHeight),
      Paint()..color = barColor,
    );

    // Paid absence sits on top of the worked part, in the same colour at a
    // lower opacity: the column reaches the target line, and it is still
    // visible that the time was not worked.
    final creditHeight = size.height * bar.credit.inMinutes / max;
    if (creditHeight > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          gap,
          size.height - workedHeight - creditHeight,
          barWidth,
          creditHeight,
        ),
        Paint()..color = barColor.withValues(alpha: 0.4),
      );
    }

    if (bar.target == Duration.zero) return;
    final targetY = size.height - size.height * bar.target.inMinutes / max;
    canvas.drawLine(
      Offset(0, targetY),
      Offset(size.width, targetY),
      Paint()
        ..color = targetColor
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.bar != bar ||
      old.maxValue != maxValue ||
      old.barColor != barColor ||
      old.targetColor != targetColor;
}
