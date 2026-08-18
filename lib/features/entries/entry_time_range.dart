/// Returns the end timestamp that keeps its original distance from the start
/// after the start moved to [newStartAt] -- i.e. the end follows the start
/// instead of staying put.
///
/// Used by the manual-entry date/time pickers so that picking a start date
/// pulls the end date onto the same day (the overwhelmingly common
/// single-day entry) and picking a start time shifts the end time by the
/// same amount, leaving the entry's duration untouched. A range that spans
/// midnight keeps spanning it, and an already-inverted range (end before
/// start, which the submit-time guard rejects) stays inverted rather than
/// being silently repaired here.
DateTime endFollowingStart({
  required DateTime previousStartAt,
  required DateTime previousEndAt,
  required DateTime newStartAt,
}) => newStartAt.add(previousEndAt.difference(previousStartAt));
