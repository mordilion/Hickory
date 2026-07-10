// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get trayOpen => 'Ouvrir';

  @override
  String get trayQuit => 'Quitter';

  @override
  String get trayBackgroundNotice =>
      'Hickory continue de fonctionner en arrière-plan.';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String settingsLanguageSystem(String language) {
    return 'Paramètre système ($language)';
  }
}
