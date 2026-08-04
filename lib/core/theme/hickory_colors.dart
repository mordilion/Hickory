import 'package:flutter/material.dart';

/// Design tokens from docs/superpowers/specs/2026-08-04-forest-amber-retheme-design.md
/// that don't map onto Flutter's built-in ColorScheme roles: gradients,
/// chip colors, nav-bar colors, and the hero timer-numeral color.
/// `background`/`surface`/`onSurface`/text-primary are pinned directly on
/// ColorScheme instead (see AppTheme) rather than duplicated here.
@immutable
class HickoryColors extends ThemeExtension<HickoryColors> {
  const HickoryColors({
    required this.surfaceGradient,
    required this.primaryGradient,
    required this.onPrimaryGradient,
    required this.textMuted,
    required this.chipBackground,
    required this.chipText,
    required this.timerNumeral,
    required this.navBackground,
    required this.navBorder,
    required this.navInactive,
    required this.navActiveLabel,
    required this.navActiveIcon,
  });

  final List<Color> surfaceGradient;
  final List<Color> primaryGradient;
  final Color onPrimaryGradient;
  final Color textMuted;
  final Color chipBackground;
  final Color chipText;
  final Color timerNumeral;
  final Color navBackground;
  final Color navBorder;
  final Color navInactive;
  final Color navActiveLabel;
  final Color navActiveIcon;

  static const light = HickoryColors(
    surfaceGradient: [Color(0xFFE3F2E8), Color(0xFFFDEEDD)],
    primaryGradient: [Color(0xFF2F6B4F), Color(0xFFC97D1E)],
    onPrimaryGradient: Color(0xFFFFFFFF),
    textMuted: Color(0x99152A1F),
    chipBackground: Color(0xFFFFFFFF),
    chipText: Color(0xFF8A5810),
    timerNumeral: Color(0xFF1E7A4F),
    navBackground: Color(0xFFFFFFFF),
    navBorder: Color(0xFFDCEEE0),
    navInactive: Color(0xFF8FA89A),
    navActiveLabel: Color(0xFF153D28),
    navActiveIcon: Color(0xFF1E7A4F),
  );

  static const dark = HickoryColors(
    surfaceGradient: [Color(0xFF1B2E22), Color(0xFF20362A)],
    primaryGradient: [Color(0xFF5FBF8F), Color(0xFFE8A548)],
    onPrimaryGradient: Color(0xFF12241A),
    textMuted: Color(0x99F3EFE2),
    chipBackground: Color(0xFF26402F),
    chipText: Color(0xFFF2BD7A),
    timerNumeral: Color(0xFF7DDBA8),
    navBackground: Color(0xFF0F1912),
    navBorder: Color(0xFF1E3226),
    navInactive: Color(0xFF6B7A70),
    navActiveLabel: Color(0xFFD7EDDF),
    navActiveIcon: Color(0xFF7DDBA8),
  );

  @override
  HickoryColors copyWith({
    List<Color>? surfaceGradient,
    List<Color>? primaryGradient,
    Color? onPrimaryGradient,
    Color? textMuted,
    Color? chipBackground,
    Color? chipText,
    Color? timerNumeral,
    Color? navBackground,
    Color? navBorder,
    Color? navInactive,
    Color? navActiveLabel,
    Color? navActiveIcon,
  }) {
    return HickoryColors(
      surfaceGradient: surfaceGradient ?? this.surfaceGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      onPrimaryGradient: onPrimaryGradient ?? this.onPrimaryGradient,
      textMuted: textMuted ?? this.textMuted,
      chipBackground: chipBackground ?? this.chipBackground,
      chipText: chipText ?? this.chipText,
      timerNumeral: timerNumeral ?? this.timerNumeral,
      navBackground: navBackground ?? this.navBackground,
      navBorder: navBorder ?? this.navBorder,
      navInactive: navInactive ?? this.navInactive,
      navActiveLabel: navActiveLabel ?? this.navActiveLabel,
      navActiveIcon: navActiveIcon ?? this.navActiveIcon,
    );
  }

  @override
  HickoryColors lerp(ThemeExtension<HickoryColors>? other, double t) {
    if (other is! HickoryColors) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> lerpGradient(List<Color> a, List<Color> b) =>
        [lerpColor(a[0], b[0]), lerpColor(a[1], b[1])];
    return HickoryColors(
      surfaceGradient: lerpGradient(surfaceGradient, other.surfaceGradient),
      primaryGradient: lerpGradient(primaryGradient, other.primaryGradient),
      onPrimaryGradient: lerpColor(onPrimaryGradient, other.onPrimaryGradient),
      textMuted: lerpColor(textMuted, other.textMuted),
      chipBackground: lerpColor(chipBackground, other.chipBackground),
      chipText: lerpColor(chipText, other.chipText),
      timerNumeral: lerpColor(timerNumeral, other.timerNumeral),
      navBackground: lerpColor(navBackground, other.navBackground),
      navBorder: lerpColor(navBorder, other.navBorder),
      navInactive: lerpColor(navInactive, other.navInactive),
      navActiveLabel: lerpColor(navActiveLabel, other.navActiveLabel),
      navActiveIcon: lerpColor(navActiveIcon, other.navActiveIcon),
    );
  }

  /// `Theme.of(context).extension<HickoryColors>()` always succeeds in this
  /// app (registered on both themes by AppTheme), so this throws in debug
  /// mode rather than silently returning a wrong-looking fallback.
  static HickoryColors of(BuildContext context) {
    final colors = Theme.of(context).extension<HickoryColors>();
    assert(colors != null, 'HickoryColors not registered on the current Theme');
    return colors!;
  }
}
