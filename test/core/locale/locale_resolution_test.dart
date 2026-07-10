import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/locale/locale_resolution.dart';

void main() {
  test('supported device locale is used as-is (language code match)', () {
    expect(resolveLocale(const Locale('de', 'AT')), const Locale('de'));
    expect(resolveLocale(const Locale('fr')), const Locale('fr'));
  });

  test('unsupported device locale falls back to English', () {
    expect(resolveLocale(const Locale('ja')), const Locale('en'));
  });

  test('null device locale falls back to English', () {
    expect(resolveLocale(null), const Locale('en'));
  });

  test('display names cover exactly the supported locales', () {
    expect(
      languageDisplayNames.keys.toSet(),
      supportedLocales.map((l) => l.languageCode).toSet(),
    );
    expect(languageDisplayNames['de'], 'Deutsch');
    expect(languageDisplayNames['nl'], 'Nederlands');
  });
}
