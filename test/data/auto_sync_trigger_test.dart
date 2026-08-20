import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/sync/auto_sync_trigger.dart';

// Plain test() (not testWidgets): runs as a normal fast Dart VM test.
// Real timers, like sync_watcher_test.dart. Anything that must *happen* is
// polled with a deadline rather than slept for, because the whole suite runs
// several files in parallel and a fixed sleep turns into a flaky assertion
// under load; only the "nothing happens" assertions use a plain wait, where
// load can at worst hide a failure, never invent one.
void main() {
  const debounce = Duration(milliseconds: 20);

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) && !condition()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('collapses several triggers inside the debounce window into one run', () async {
    var runs = 0;
    final trigger = AutoSyncTrigger(() async => runs++, debounce: debounce);
    addTearDown(trigger.dispose);

    trigger.schedule();
    trigger.schedule();
    trigger.schedule();
    expect(runs, 0, reason: 'a trigger must not run synchronously');

    await waitFor(() => runs > 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(runs, 1, reason: 'three triggers in one window are one run');
  });

  test('runs once more when a trigger arrives while a run is in flight', () async {
    var runs = 0;
    // The run is held open by hand instead of by a delay, so "the second
    // trigger did not overlap the first" is a fact, not a race.
    final inFlight = Completer<void>();
    final trigger = AutoSyncTrigger(() async {
      runs++;
      if (runs == 1) await inFlight.future;
    }, debounce: debounce);
    addTearDown(trigger.dispose);

    trigger.schedule();
    await waitFor(() => runs > 0);

    trigger.schedule();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(runs, 1, reason: 'two reconciliations must never overlap');

    inFlight.complete();
    await waitFor(() => runs > 1);
    expect(runs, 2, reason: 'the trigger raised during the run must not be lost');
  });

  test('keeps working after a run fails', () async {
    var runs = 0;
    final trigger = AutoSyncTrigger(() async {
      runs++;
      throw StateError('sync failed');
    }, debounce: debounce);
    addTearDown(trigger.dispose);

    trigger.schedule();
    await waitFor(() => runs > 0);

    trigger.schedule();
    await waitFor(() => runs > 1);
    expect(runs, 2);
  });

  test('dispose cancels a run that has not started yet', () async {
    var runs = 0;
    final trigger = AutoSyncTrigger(() async => runs++, debounce: debounce);

    trigger.schedule();
    trigger.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(runs, 0);
  });

  test('ignores triggers raised after dispose', () async {
    var runs = 0;
    final trigger = AutoSyncTrigger(() async => runs++, debounce: debounce);

    trigger.dispose();
    trigger.schedule();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(runs, 0);
  });
}
