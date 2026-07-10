// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get trayOpen => 'Apri';

  @override
  String get trayQuit => 'Esci';

  @override
  String get trayBackgroundNotice =>
      'Hickory continua a funzionare in background.';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String settingsLanguageSystem(String language) {
    return 'Predefinita di sistema ($language)';
  }
}
