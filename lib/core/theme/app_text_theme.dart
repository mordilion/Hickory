import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Display roles (large, high-impact text: app title, the timer's elapsed-
/// time numerals, screen headlines) use Unbounded; everything else uses
/// Manrope. Unbounded is deliberately not used for label/body roles — it
/// loses legibility at small sizes.
/// See docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md.
TextTheme buildAppTextTheme(Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true).textTheme;

  TextStyle display(TextStyle? style) =>
      GoogleFonts.unbounded(textStyle: style, fontWeight: FontWeight.w700);
  TextStyle body(TextStyle? style) => GoogleFonts.manrope(textStyle: style);

  return base.copyWith(
    displayLarge: display(base.displayLarge),
    displayMedium: display(base.displayMedium),
    displaySmall: display(base.displaySmall),
    headlineLarge: display(base.headlineLarge),
    headlineMedium: display(base.headlineMedium),
    headlineSmall: display(base.headlineSmall),
    titleLarge: display(base.titleLarge),
    titleMedium: body(base.titleMedium),
    titleSmall: body(base.titleSmall),
    bodyLarge: body(base.bodyLarge),
    bodyMedium: body(base.bodyMedium),
    bodySmall: body(base.bodySmall),
    labelLarge: body(base.labelLarge),
    labelMedium: body(base.labelMedium),
    labelSmall: body(base.labelSmall),
  );
}
