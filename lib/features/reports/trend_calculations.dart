// Bars for the Reports dashboard's trend chart. Pure: no Riverpod, no
// Flutter beyond DateTimeRange — the same shape as the other calculation
// modules here.

import 'package:flutter/material.dart' show DateTimeRange;

import '../../core/format/iso_week.dart' show mondayOf;
import 'balance_calculations.dart' show DayBalance;

enum TrendGranularity { day, week, month }

/// One column of the chart: what was worked against what was owed.
typedef TrendBar = ({DateTime start, Duration worked, Duration target});

DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Days per bar beyond which the chart switches to weeks — roughly two
/// months, past which a per-day chart is a picket fence nobody can read.
const _defaultDayLimit = 62;

/// And beyond which it switches again, to months: about two years, where
/// weekly bars would be a hundred pickets instead. The "all" range spans a
/// century on paper, so without this step it would draw one bar per week
/// of the user's whole history.
const _defaultWeekLimit = 730;

/// Whether [range] is drawn per day, per ISO week or per month.
TrendGranularity granularityFor(
  DateTimeRange range, {
  int dayLimit = _defaultDayLimit,
  int weekLimit = _defaultWeekLimit,
}) {
  final days = _dayOf(range.end).difference(_dayOf(range.start)).inDays;
  if (days <= dayLimit) return TrendGranularity.day;
  return days > weekLimit ? TrendGranularity.month : TrendGranularity.week;
}

/// First of [day]'s month, local midnight.
DateTime _monthOf(DateTime day) => DateTime(day.year, day.month);

/// Folds [balances] into one bar per day or per ISO week.
///
/// Drawing starts at the first day the data covers, not at the range's
/// start: the "all" range spans a century, and thirty thousand empty bars
/// are not a chart. It ends at [through] (normally today) clamped into the
/// range — a day inside that span with nothing tracked is still drawn, so
/// a forgotten week reads as a gap, while the rest of a running month is
/// not drawn as a row of zeroes that have not happened yet.
///
/// [range.end] is exclusive, matching `rangeForPreset`.
List<TrendBar> trendBars(
  List<DayBalance> balances,
  DateTimeRange range,
  TrendGranularity granularity, {
  DateTime? through,
}) {
  final rangeStart = _dayOf(range.start);
  final rangeEnd = _dayOf(range.end);
  final inRange = [
    for (final balance in balances)
      if (!balance.day.isBefore(rangeStart) && balance.day.isBefore(rangeEnd)) balance,
  ];
  if (inRange.isEmpty) return const [];

  var first = inRange.first.day;
  var last = inRange.first.day;
  for (final balance in inRange) {
    if (balance.day.isBefore(first)) first = balance.day;
    if (balance.day.isAfter(last)) last = balance.day;
  }
  if (through != null) {
    final lastDrawn = _dayOf(through);
    final rangeLast = rangeEnd.subtract(const Duration(days: 1));
    final limit = lastDrawn.isBefore(rangeLast) ? lastDrawn : rangeLast;
    if (limit.isAfter(last)) last = limit;
  }

  final worked = <DateTime, Duration>{};
  final target = <DateTime, Duration>{};
  DateTime bucketOf(DateTime day) => switch (granularity) {
    TrendGranularity.day => day,
    TrendGranularity.week => mondayOf(day),
    TrendGranularity.month => _monthOf(day),
  };

  for (final balance in inRange) {
    final bucket = bucketOf(balance.day);
    worked.update(bucket, (sum) => sum + balance.worked, ifAbsent: () => balance.worked);
    target.update(bucket, (sum) => sum + balance.target, ifAbsent: () => balance.target);
  }

  // Months are stepped through the DateTime constructor rather than by
  // adding days: their length varies, and a fixed step would drift.
  DateTime nextBucket(DateTime bucket) => switch (granularity) {
    TrendGranularity.day => _dayOf(bucket.add(const Duration(days: 1))),
    TrendGranularity.week => _dayOf(bucket.add(const Duration(days: 7))),
    TrendGranularity.month => DateTime(bucket.year, bucket.month + 1),
  };

  final bars = <TrendBar>[];
  for (
    var bucket = bucketOf(first);
    !bucket.isAfter(bucketOf(last));
    bucket = nextBucket(bucket)
  ) {
    bars.add((
      start: bucket,
      worked: worked[bucket] ?? Duration.zero,
      target: target[bucket] ?? Duration.zero,
    ));
  }
  return bars;
}
