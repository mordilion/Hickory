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

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsAutostart => 'Avvia all\'accensione del sistema';

  @override
  String get settingsDateFormat => 'Formato data';

  @override
  String get settingsTimeFormat => 'Formato ora';

  @override
  String get syncTitle => 'Impostazioni di sincronizzazione';

  @override
  String get syncNoFolderSelected =>
      'Nessuna cartella selezionata: i dati restano solo su questo dispositivo.';

  @override
  String syncFolderPath(String path) {
    return 'Cartella di sincronizzazione: $path';
  }

  @override
  String syncError(String error) {
    return 'Errore: $error';
  }

  @override
  String get syncFolderDescription =>
      'Scegli una cartella già sincronizzata da iCloud Drive, Google Drive, Dropbox o simili. Hickory scrive lì solo i propri file e non si sincronizza da solo con il cloud.';

  @override
  String get syncNowButton => 'Sincronizza ora';

  @override
  String get syncChooseFolderButton => 'Scegli cartella';

  @override
  String syncFolderChosen(String path) {
    return 'Cartella selezionata: $path';
  }

  @override
  String get syncCompleted => 'Sincronizzazione completata.';
}
