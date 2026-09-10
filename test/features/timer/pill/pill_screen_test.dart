import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/clients/clients_providers.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/pill/pill_screen.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:hickory/l10n/app_localizations_en.dart';

TimeEntry _entry({DateTime? pausedAt, String? projectId}) => TimeEntry(
  id: 'e1',
  deviceId: 'd1',
  startAt: DateTime.utc(2026, 9, 10, 8),
  endAt: null,
  pausedAt: pausedAt,
  totalPausedSeconds: 0,
  billableOverride: null,
  source: 'manual',
  projectId: projectId,
  description: null,
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 9, 10, 8),
  updatedAt: DateTime.utc(2026, 9, 10, 8),
);

Project _project() => Project(
  id: 'p1',
  name: 'Website-Relaunch',
  colorHex: '#2F6B4F',
  clientId: 'c1',
  archived: false,
  billable: true,
  hourlyRateCents: null,
  currency: null,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

// Drift generates `Value<String?> clientId` on Project.copyWith, so a bare
// `null` cannot clear the field (it would just mean "leave unchanged").
// A second literal is the only way to express "no client" here.
Project _projectWithoutClient() => Project(
  id: 'p1',
  name: 'Website-Relaunch',
  colorHex: '#2F6B4F',
  clientId: null,
  archived: false,
  billable: true,
  hourlyRateCents: null,
  currency: null,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Client _client() => Client(
  id: 'c1',
  name: 'Müller GmbH',
  archived: false,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Widget _host({
  required TimeEntry entry,
  List<Project> projects = const [],
  List<Client> clients = const [],
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onStop,
  VoidCallback? onExpand,
  VoidCallback? onDragStart,
}) => ProviderScope(
  overrides: [
    runningEntryProvider.overrideWith((ref) => Stream.value(entry)),
    activeProjectsProvider.overrideWith((ref) => Stream.value(projects)),
    allClientsProvider.overrideWith((ref) => Stream.value(clients)),
    timerTickProvider.overrideWith((ref) => Stream.value(0)),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PillScreen(
      onPause: onPause ?? () {},
      onResume: onResume ?? () {},
      onStop: onStop ?? () {},
      onExpand: onExpand ?? () {},
      onDragStart: onDragStart ?? () {},
    ),
  ),
);

void main() {
  testWidgets('shows the elapsed time', (tester) async {
    await tester.pumpWidget(_host(entry: _entry(pausedAt: DateTime.utc(2026, 9, 10, 9, 23, 45))));
    await tester.pumpAndSettle();

    expect(find.text('01:23:45'), findsOneWidget);
  });

  testWidgets('shows client and project when both are known', (tester) async {
    await tester.pumpWidget(
      _host(
        entry: _entry(projectId: 'p1'),
        projects: [_project()],
        clients: [_client()],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Müller GmbH · Website-Relaunch'), findsOneWidget);
  });

  testWidgets('shows the project alone when it has no client', (tester) async {
    await tester.pumpWidget(
      _host(entry: _entry(projectId: 'p1'), projects: [_projectWithoutClient()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Website-Relaunch'), findsOneWidget);
  });

  testWidgets('shows no project line when the entry has no project', (tester) async {
    await tester.pumpWidget(_host(entry: _entry()));
    await tester.pumpAndSettle();

    // The elapsed-time text is the only Text in the tree; _ProjectLine must
    // have taken its `projectId == null` early return, not merely rendered
    // an empty string.
    expect(find.byType(Text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows no project line when the project id is unknown', (tester) async {
    await tester.pumpWidget(
      _host(entry: _entry(projectId: 'missing'), projects: [_project()]),
    );
    await tester.pumpAndSettle();

    // A projectId with no match in activeProjectsProvider must render
    // nothing rather than throw when the lookup loop finds no candidate.
    expect(find.byType(Text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Split into two tests rather than pumping a second, differently-overridden
  // ProviderScope into the same tree: ProviderContainer.updateOverrides swaps
  // the override reference but does not force a StreamProvider to
  // re-subscribe, so a running entry's provider never emits the paused one
  // mid-test. A fresh widget tree per state sidesteps that entirely.
  testWidgets('running state offers pause', (tester) async {
    var paused = 0;
    await tester.pumpWidget(_host(entry: _entry(), onPause: () => paused++));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    expect(paused, 1);
  });

  testWidgets('paused state offers resume', (tester) async {
    var resumed = 0;
    await tester.pumpWidget(
      _host(entry: _entry(pausedAt: DateTime.utc(2026, 9, 10, 9)), onResume: () => resumed++),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(resumed, 1);
  });

  testWidgets('stop and expand fire their callbacks', (tester) async {
    var stopped = 0;
    var expanded = 0;
    await tester.pumpWidget(
      _host(entry: _entry(), onStop: () => stopped++, onExpand: () => expanded++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.stop));
    await tester.tap(find.byIcon(Icons.open_in_full));

    expect(stopped, 1);
    expect(expanded, 1);
  });

  testWidgets('every icon button carries its localized tooltip', (tester) async {
    await tester.pumpWidget(_host(entry: _entry()));
    await tester.pumpAndSettle();

    // Resolved through AppLocalizationsEn rather than hardcoded English, so
    // a swapped or blanked ARB value fails this test instead of only a
    // vacuous count check.
    final l10n = AppLocalizationsEn();
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message)
        .toSet();

    expect(messages, {l10n.pillPause, l10n.pillStop, l10n.pillExpand});
  });

  testWidgets('does not dim the surface while running', (tester) async {
    await tester.pumpWidget(_host(entry: _entry()));
    await tester.pumpAndSettle();

    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('dims the surface while paused', (tester) async {
    await tester.pumpWidget(
      _host(entry: _entry(pausedAt: DateTime.utc(2026, 9, 10, 9))),
    );
    await tester.pumpAndSettle();

    // The paused surface must differ in its own decoration -- not merely in
    // the pause/resume icon, which every other test already exercises.
    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('panning the surface starts the window drag', (tester) async {
    var dragged = 0;
    await tester.pumpWidget(_host(entry: _entry(), onDragStart: () => dragged++));
    await tester.pumpAndSettle();

    // The pill's centre sits over the client/project column, not over any
    // button -- it is draggable there only because the surface
    // GestureDetector uses HitTestBehavior.opaque, not because a button
    // happens to be under the pointer.
    await tester.dragFrom(tester.getCenter(find.byType(PillScreen)), const Offset(40, 0));

    expect(dragged, 1);
  });

  testWidgets('panning directly above a button still starts the window drag', (tester) async {
    var dragged = 0;
    await tester.pumpWidget(_host(entry: _entry(), onDragStart: () => dragged++));
    await tester.pumpAndSettle();

    // Each icon button is a tightly-constrained 32x32 hit area with no
    // horizontal gap between neighbours, so the only pixels provably off
    // every button sit above/below the row, in the same column as a button --
    // this drags from there to confirm the surface (not just the text
    // column) is draggable, per HitTestBehavior.opaque on the GestureDetector.
    final stopButtonCenter = tester.getCenter(find.byIcon(Icons.stop));
    await tester.dragFrom(stopButtonCenter - const Offset(0, 20), const Offset(0, 40));

    expect(dragged, 1);
  });

  testWidgets('does not overflow at the pill\'s fixed 320x56 size', (tester) async {
    tester.view.physicalSize = const Size(320, 56);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        entry: _entry(projectId: 'p1'),
        projects: [_project()],
        clients: [_client()],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
