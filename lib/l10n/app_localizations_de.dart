// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get trayOpen => 'Öffnen';

  @override
  String get trayQuit => 'Beenden';

  @override
  String get trayBackgroundNotice => 'Hickory läuft im Hintergrund weiter.';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String settingsLanguageSystem(String language) {
    return 'Systemstandard ($language)';
  }
}
