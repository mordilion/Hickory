import 'dart:ui';

/// The six languages Hickory ships translations for. Order = picker order.
const supportedLocales = [
  Locale('de'),
  Locale('en'),
  Locale('fr'),
  Locale('es'),
  Locale('it'),
  Locale('nl'),
];

/// Endonyms for the language picker — deliberately NOT localized, every
/// language is shown in its own name.
const languageDisplayNames = {
  'de': 'Deutsch',
  'en': 'English',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'nl': 'Nederlands',
};

/// Maps a device/system locale onto a supported one; English is the
/// spec-mandated fallback for unsupported (or unknown) system languages.
Locale resolveLocale(Locale? deviceLocale) {
  final code = deviceLocale?.languageCode;
  for (final locale in supportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return const Locale('en');
}
