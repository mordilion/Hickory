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

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsAutostart => 'Ouvrir au démarrage du système';

  @override
  String get settingsDateFormat => 'Format de date';

  @override
  String get settingsTimeFormat => 'Format d\'heure';

  @override
  String get syncTitle => 'Paramètres de synchronisation';

  @override
  String get syncNoFolderSelected =>
      'Aucun dossier sélectionné – les données restent uniquement sur cet appareil.';

  @override
  String syncFolderPath(String path) {
    return 'Dossier de synchronisation : $path';
  }

  @override
  String syncError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get syncFolderDescription =>
      'Choisissez un dossier déjà synchronisé par iCloud Drive, Google Drive, Dropbox ou similaire. Hickory y écrit uniquement ses propres fichiers et ne se synchronise pas lui-même avec le cloud.';

  @override
  String get syncNowButton => 'Synchroniser maintenant';

  @override
  String get syncChooseFolderButton => 'Choisir un dossier';

  @override
  String syncFolderChosen(String path) {
    return 'Dossier sélectionné : $path';
  }

  @override
  String get syncCompleted => 'Synchronisation terminée.';
}
