import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/hickory_colors.dart';

void main() {
  test('dark tokens match the spec', () {
    expect(HickoryColors.dark.primaryGradient, const [Color(0xFFB678FF), Color(0xFFFF6FA9)]);
    expect(HickoryColors.dark.surfaceGradient, const [Color(0xFF241A30), Color(0xFF2E1B38)]);
    expect(HickoryColors.dark.onPrimaryGradient, const Color(0xFF160A22));
    expect(HickoryColors.dark.timerNumeral, const Color(0xFFC89BFF));
    expect(HickoryColors.dark.chipBackground, const Color(0xFF3A2A4A));
    expect(HickoryColors.dark.chipText, const Color(0xFFFF9ED6));
    expect(HickoryColors.dark.navBackground, const Color(0xFF1A1420));
    expect(HickoryColors.dark.navBorder, const Color(0xFF2A2033));
    expect(HickoryColors.dark.navInactive, const Color(0xFF6E6478));
    expect(HickoryColors.dark.navActiveLabel, const Color(0xFFE4D5FF));
    expect(HickoryColors.dark.navActiveIcon, const Color(0xFFC89BFF));
  });

  test('light tokens match the spec', () {
    expect(HickoryColors.light.primaryGradient, const [Color(0xFF8B4FE0), Color(0xFFE0568F)]);
    expect(HickoryColors.light.surfaceGradient, const [Color(0xFFF1E4FF), Color(0xFFFDE6F1)]);
    expect(HickoryColors.light.onPrimaryGradient, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.timerNumeral, const Color(0xFF7C3AED));
    expect(HickoryColors.light.chipBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.chipText, const Color(0xFFC0287A));
    expect(HickoryColors.light.navBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.navBorder, const Color(0xFFEEE3FA));
    expect(HickoryColors.light.navInactive, const Color(0xFFA99BB8));
    expect(HickoryColors.light.navActiveLabel, const Color(0xFF4C1D95));
    expect(HickoryColors.light.navActiveIcon, const Color(0xFF7C3AED));
  });

  test('lerp interpolates toward the other extension, and passes through unrelated types', () {
    final atStart = HickoryColors.dark.lerp(HickoryColors.light, 0);
    final atEnd = HickoryColors.dark.lerp(HickoryColors.light, 1);
    expect(atStart.timerNumeral, HickoryColors.dark.timerNumeral);
    expect(atEnd.timerNumeral, HickoryColors.light.timerNumeral);

    final unchanged = HickoryColors.dark.lerp(null, 0.5);
    expect(unchanged, same(HickoryColors.dark));
  });
}
