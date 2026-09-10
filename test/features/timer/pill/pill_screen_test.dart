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
}) => ProviderScope(
  overrides: [
    runningEntryProvider.overrideWith((ref) => Stream.value(entry)),
    activeProjectsProvider.overrideWith((ref) => Stream.value(projects)),
    allClientsProvider.overrideWith((ref) => Stream.value(clients)),
    timerTickProvider.overrideWith((ref) => Stream.value(0)),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PillScreen(
      onPause: onPause ?? () {},
      onResume: onResume ?? () {},
      onStop: onStop ?? () {},
      onExpand: onExpand ?? () {},
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

  testWidgets('every icon button carries a tooltip', (tester) async {
    await tester.pumpWidget(_host(entry: _entry()));
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsNWidgets(3));
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
