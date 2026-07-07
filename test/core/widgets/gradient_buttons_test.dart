import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/widgets/gradient_buttons.dart';

void main() {
  testWidgets('GradientPillButton renders its label and invokes onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradientPillButton(
            label: 'Stop',
            icon: Icons.stop,
            gradient: const [Color(0xFFB678FF), Color(0xFFFF6FA9)],
            foregroundColor: const Color(0xFF160A22),
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('GradientFab renders its icon and invokes onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradientFab(
            icon: Icons.add,
            gradient: const [Color(0xFFB678FF), Color(0xFFFF6FA9)],
            foregroundColor: const Color(0xFF160A22),
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
