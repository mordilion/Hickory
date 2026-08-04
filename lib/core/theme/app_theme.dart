import 'package:flutter/material.dart';

import 'app_text_theme.dart';
import 'hickory_colors.dart';

/// Builds Hickory's light/dark ThemeData from the Forest & Amber tokens in
/// docs/superpowers/specs/2026-08-04-forest-amber-retheme-design.md (the
/// shape/typography/navigation decisions from the original Electric Violet
/// redesign, docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md,
/// are unchanged — only the color tokens were re-themed).
///
/// Starts from ColorScheme.fromSeed (so any Material component we haven't
/// explicitly themed still gets a reasonable, harmonious color) and then
/// pins the roles the spec cares about to its exact hex values — the seed
/// algorithm alone tends to desaturate toward muted, accessible-but-flat
/// tones and would lose the vividness validated in the design mockups.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static const _pillShape = StadiumBorder();
  static const _cardRadius = 24.0;

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? HickoryColors.dark : HickoryColors.light;
    final surface = isDark ? const Color(0xFF0E1712) : const Color(0xFFF5FAF6);
    final cardSurface = isDark ? const Color(0xFF182620) : Colors.white;
    final onSurface = isDark ? const Color(0xFFF3EFE2) : const Color(0xFF152A1F);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5FBF8F),
      brightness: brightness,
    ).copyWith(
      primary: tokens.timerNumeral,
      onPrimary: tokens.onPrimaryGradient,
      secondary: tokens.chipText,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      textTheme: buildAppTextTheme(brightness),
      extensions: [tokens],
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: _pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: _pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: _pillShape)),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.chipBackground,
        labelStyle: TextStyle(color: tokens.chipText, fontWeight: FontWeight.w600, fontSize: 11),
        shape: _pillShape,
        side: BorderSide.none,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.navBackground,
        indicatorColor: tokens.navActiveIcon.withValues(alpha: 0.16),
        indicatorShape: _pillShape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? tokens.navActiveIcon : tokens.navInactive,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? tokens.navActiveLabel : tokens.navInactive,
          ),
        ),
      ),
    );
  }
}
