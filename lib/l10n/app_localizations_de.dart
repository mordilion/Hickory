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

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAutostart => 'Beim Systemstart öffnen';

  @override
  String get settingsDateFormat => 'Datumsformat';

  @override
  String get settingsTimeFormat => 'Zeitformat';

  @override
  String get syncTitle => 'Sync-Einstellungen';

  @override
  String get syncNoFolderSelected =>
      'Kein Ordner gewählt – Daten bleiben nur lokal auf diesem Gerät.';

  @override
  String syncFolderPath(String path) {
    return 'Sync-Ordner: $path';
  }

  @override
  String syncError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get syncFolderDescription =>
      'Wähle einen Ordner, der bereits von iCloud Drive, Google Drive, Dropbox o.ä. synchronisiert wird. Hickory schreibt dort nur eigene Dateien und synchronisiert sich selbst nicht mit der Cloud.';

  @override
  String get syncNowButton => 'Jetzt synchronisieren';

  @override
  String get syncChooseFolderButton => 'Ordner wählen';

  @override
  String syncFolderChosen(String path) {
    return 'Ordner gewählt: $path';
  }

  @override
  String get syncCompleted => 'Synchronisierung abgeschlossen.';
}
