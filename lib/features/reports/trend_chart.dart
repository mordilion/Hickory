import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../l10n/app_localizations.dart';
import 'reports_providers.dart';
import 'trend_calculations.dart';

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
    final bars = ref.watch(trendBarsProvider).value ?? const <TrendBar>[];
    final settings = ref.watch(appSettingsProvider).value;
    final timeStyle = settings.timeStyle;
    final localeName = Localizations.localeOf(context).languageCode;
    final dateFormat = DateFormat.Md(localeName);

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
                          message: _label(bar, l10n, dateFormat, timeStyle),
                          child: Semantics(
                            label: _label(bar, l10n, dateFormat, timeStyle),
                            child: CustomPaint(
                              painter: _BarPainter(
                                bar: bar,
                                maxValue: _maxValue(bars),
                                barColor: theme.colorScheme.primary,
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
      if (bar.worked > max) max = bar.worked;
      if (bar.target > max) max = bar.target;
    }
    return max;
  }

  static String _label(
    TrendBar bar,
    AppLocalizations l10n,
    DateFormat dateFormat,
    TimeFormatStyle timeStyle,
  ) => l10n.reportsTrendBarLabel(
    dateFormat.format(bar.start),
    formatDuration(bar.worked, timeStyle),
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
