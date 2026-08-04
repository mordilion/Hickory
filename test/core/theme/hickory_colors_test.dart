import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/hickory_colors.dart';

void main() {
  test('dark tokens match the spec', () {
    expect(HickoryColors.dark.primaryGradient, const [Color(0xFF5FBF8F), Color(0xFFE8A548)]);
    expect(HickoryColors.dark.surfaceGradient, const [Color(0xFF1B2E22), Color(0xFF20362A)]);
    expect(HickoryColors.dark.onPrimaryGradient, const Color(0xFF12241A));
    expect(HickoryColors.dark.timerNumeral, const Color(0xFF7DDBA8));
    expect(HickoryColors.dark.chipBackground, const Color(0xFF26402F));
    expect(HickoryColors.dark.chipText, const Color(0xFFF2BD7A));
    expect(HickoryColors.dark.navBackground, const Color(0xFF0F1912));
    expect(HickoryColors.dark.navBorder, const Color(0xFF1E3226));
    expect(HickoryColors.dark.navInactive, const Color(0xFF6B7A70));
    expect(HickoryColors.dark.navActiveLabel, const Color(0xFFD7EDDF));
    expect(HickoryColors.dark.navActiveIcon, const Color(0xFF7DDBA8));
  });

  test('light tokens match the spec', () {
    expect(HickoryColors.light.primaryGradient, const [Color(0xFF2F6B4F), Color(0xFFC97D1E)]);
    expect(HickoryColors.light.surfaceGradient, const [Color(0xFFE3F2E8), Color(0xFFFDEEDD)]);
    expect(HickoryColors.light.onPrimaryGradient, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.timerNumeral, const Color(0xFF1E7A4F));
    expect(HickoryColors.light.chipBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.chipText, const Color(0xFF8A5810));
    expect(HickoryColors.light.navBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.navBorder, const Color(0xFFDCEEE0));
    expect(HickoryColors.light.navInactive, const Color(0xFF8FA89A));
    expect(HickoryColors.light.navActiveLabel, const Color(0xFF153D28));
    expect(HickoryColors.light.navActiveIcon, const Color(0xFF1E7A4F));
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
