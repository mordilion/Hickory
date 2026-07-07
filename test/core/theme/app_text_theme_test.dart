import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hickory/core/theme/app_text_theme.dart';

void main() {
  setUpAll(() {
    // Disable runtime fetching for tests to avoid network requests
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('display and headline roles use Unbounded', (WidgetTester tester) async {
    final theme = buildAppTextTheme(Brightness.dark);
    expect(theme.displayLarge!.fontFamily, contains('Unbounded'));
    expect(theme.displayMedium!.fontFamily, contains('Unbounded'));
    expect(theme.headlineMedium!.fontFamily, contains('Unbounded'));
    expect(theme.titleLarge!.fontFamily, contains('Unbounded'));
  });

  testWidgets('body and label roles use Manrope', (WidgetTester tester) async {
    final theme = buildAppTextTheme(Brightness.dark);
    expect(theme.bodyLarge!.fontFamily, contains('Manrope'));
    expect(theme.bodyMedium!.fontFamily, contains('Manrope'));
    expect(theme.labelSmall!.fontFamily, contains('Manrope'));
    expect(theme.titleMedium!.fontFamily, contains('Manrope'));
  });

  testWidgets('builds for both brightnesses without throwing', (WidgetTester tester) async {
    expect(() => buildAppTextTheme(Brightness.light), returnsNormally);
    expect(() => buildAppTextTheme(Brightness.dark), returnsNormally);
  });
}
