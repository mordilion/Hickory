import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/core/window/window_mode.dart';
import 'package:hickory/core/window/window_mode_provider.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/clients/clients_providers.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/pill/pill_screen.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:hickory/l10n/app_localizations_en.dart';
import 'package:mocktail/mocktail.dart';

class _MockSyncedWrites extends Mock implements SyncedWrites {}

/// Records which window-mode calls `PillHost`'s expand button actually
/// drives, without touching the real `WindowModeController` (which throws
/// unless `windowModeControllerProvider` is overridden -- see
/// `timer_pill_coordinator_test.dart`, which uses the same fake).
class _FakeWindowModeNotifier extends WindowModeNotifier {
  final calls = <String>[];

  @override
  WindowMode build() => WindowMode.pill;

  @override
  Future<void> expand() async {
    calls.add('expand');
    state = WindowMode.full;
  }

  @override
  Future<void> collapse() async {
    calls.add('collapse');
  }
}

/// Simulates a platform-level expand() failure (spec 8.2's live Windows
/// risk: `setTitleBarStyle` may not restore there) without needing a real
/// `WindowModeController`. `succeedsAfter` lets a test also cover recovery:
/// the Nth call onward resolves normally instead of throwing.
class _FlakyWindowModeNotifier extends WindowModeNotifier {
  _FlakyWindowModeNotifier({this.succeedsAfter});

  final int? succeedsAfter;
  var _attempts = 0;

  @override
  WindowMode build() => WindowMode.pill;

  @override
  Future<void> expand() async {
    _attempts++;
    if (succeedsAfter != null && _attempts > succeedsAfter!) {
      state = WindowMode.full;
      return;
    }
    throw StateError('platform channel unavailable');
  }
}

TimeEntry _entry({DateTime? pausedAt}) => TimeEntry(
  id: 'e1',
  deviceId: 'd1',
  startAt: DateTime.utc(2026, 9, 10, 8),
  endAt: null,
  pausedAt: pausedAt,
  totalPausedSeconds: 0,
  billableOverride: null,
  source: 'manual',
  projectId: null,
  description: null,
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 8),
);

Widget _host({
  required TimeEntry? entry,
  required _MockSyncedWrites writes,
  WindowModeNotifier? windowMode,
}) => ProviderScope(
  overrides: [
    runningEntryProvider.overrideWith((ref) => Stream.value(entry)),
    activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
    allClientsProvider.overrideWith((ref) => Stream.value(const [])),
    timerTickProvider.overrideWith((ref) => Stream.value(0)),
    syncedWritesProvider.overrideWith((ref) async => writes),
    if (windowMode != null) windowModeProvider.overrideWith(() => windowMode),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const PillHost(),
  ),
);

void main() {
  late _MockSyncedWrites writes;

  setUp(() {
    writes = _MockSyncedWrites();
    // Every write is stubbed up front: an unstubbed call on a mocktail Mock
    // whose method returns a non-nullable Future throws, which would make a
    // missing stub look like a test failure in the write path itself rather
    // than a clear verify() mismatch.
    when(() => writes.pauseEntry(any())).thenAnswer((_) async {});
    when(() => writes.resumeEntry(any())).thenAnswer((_) async {});
    when(() => writes.stopEntry(any())).thenAnswer((_) async {});
  });

  testWidgets('pause writes pauseEntry with the running id, nothing else', (tester) async {
    await tester.pumpWidget(_host(entry: _entry(), writes: writes));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    verify(() => writes.pauseEntry('e1')).called(1);
    verifyNever(() => writes.resumeEntry(any()));
    verifyNever(() => writes.stopEntry(any()));
  });

  testWidgets('resume writes resumeEntry with the paused entry id', (tester) async {
    await tester.pumpWidget(
      _host(entry: _entry(pausedAt: DateTime.utc(2026, 9, 10, 9)), writes: writes),
    );
    await tester.pumpAndSettle();

    // The pill shows resume (▶) rather than pause once the entry is
    // paused -- tapping that same button position is what dispatches
    // resumeEntry instead of pauseEntry.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    verify(() => writes.resumeEntry('e1')).called(1);
    verifyNever(() => writes.pauseEntry(any()));
    verifyNever(() => writes.stopEntry(any()));
  });

  testWidgets('stop writes stopEntry with the running id', (tester) async {
    await tester.pumpWidget(_host(entry: _entry(), writes: writes));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    verify(() => writes.stopEntry('e1')).called(1);
    verifyNever(() => writes.pauseEntry(any()));
    verifyNever(() => writes.resumeEntry(any()));
  });

  testWidgets('with no running entry, every button writes nothing and throws nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_host(entry: null, writes: writes));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    verifyNever(() => writes.pauseEntry(any()));
    verifyNever(() => writes.resumeEntry(any()));
    verifyNever(() => writes.stopEntry(any()));
  });

  testWidgets('expand drives the window mode notifier, not a write', (tester) async {
    final windowMode = _FakeWindowModeNotifier();
    await tester.pumpWidget(_host(entry: _entry(), writes: writes, windowMode: windowMode));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    expect(windowMode.calls, ['expand']);
    verifyNever(() => writes.pauseEntry(any()));
    verifyNever(() => writes.resumeEntry(any()));
    verifyNever(() => writes.stopEntry(any()));
  });

  testWidgets('a failed expand surfaces as a warning icon, not silently', (tester) async {
    final windowMode = _FlakyWindowModeNotifier();
    await tester.pumpWidget(_host(entry: _entry(), writes: writes, windowMode: windowMode));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    // No unhandled exception reaches the test binding -- PillHost's own
    // catch is what stands between a thrown expand() and a crashed pill.
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    final l10n = AppLocalizationsEn();
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.byIcon(Icons.error_outline), matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, l10n.pillExpandError);
  });

  testWidgets('a later successful expand clears the warning icon', (tester) async {
    final windowMode = _FlakyWindowModeNotifier(succeedsAfter: 1);
    await tester.pumpWidget(_host(entry: _entry(), writes: writes, windowMode: windowMode));
    await tester.pumpAndSettle();

    // First tap fails and shows the warning ...
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    // ... the second tap is the retry the icon swap exists to invite, and it
    // succeeds, so the warning must not linger once the window is open.
    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
