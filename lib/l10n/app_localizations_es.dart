// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get trayOpen => 'Abrir';

  @override
  String get trayQuit => 'Salir';

  @override
  String get trayBackgroundNotice =>
      'Hickory sigue ejecutándose en segundo plano.';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String settingsLanguageSystem(String language) {
    return 'Predeterminado del sistema ($language)';
  }
}
