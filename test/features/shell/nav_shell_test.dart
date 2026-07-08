import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/shell/nav_shell.dart';

void main() {
  testWidgets('shows the initial tab and its FAB, switches on tap, hides the FAB '
      'on tabs with none', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavShell(
          destinations: const [
            NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Timer'),
            NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          ],
          children: const [
            Center(child: Text('Timer content')),
            Center(child: Text('Reports content')),
          ],
          fabBuilder: (selectedIndex) =>
              selectedIndex == 0 ? FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)) : null,
        ),
      ),
    );

    expect(find.text('Timer content'), findsOneWidget);
    expect(find.text('Reports content'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Timer content'), findsNothing);
    expect(find.text('Reports content'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
