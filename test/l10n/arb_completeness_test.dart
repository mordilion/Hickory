// test/l10n/arb_completeness_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every language must define exactly the same message keys as the German
/// template. Metadata entries (@key, @@locale) are ignored.
void main() {
  const languages = ['de', 'en', 'fr', 'es', 'it', 'nl'];

  Set<String> keysOf(String lang) {
    final file = File('lib/l10n/app_$lang.arb');
    expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
    final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return map.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('all ARB files define the same keys as the template', () {
    final template = keysOf('de');
    expect(template, isNotEmpty);
    for (final lang in languages.skip(1)) {
      final keys = keysOf(lang);
      expect(keys.difference(template), isEmpty, reason: 'extra keys in $lang');
      expect(template.difference(keys), isEmpty, reason: 'missing keys in $lang');
    }
  });
}
