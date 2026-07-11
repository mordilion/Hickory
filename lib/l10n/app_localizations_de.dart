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

  @override
  String get navTimer => 'Timer';

  @override
  String get navReports => 'Reports';

  @override
  String get navSync => 'Sync';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get commonNoProject => 'Kein Projekt';

  @override
  String timerError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get timerResume => 'Fortsetzen';

  @override
  String get timerPause => 'Pause';

  @override
  String get timerStop => 'Stop';

  @override
  String get timerDescriptionLabel => 'Was arbeitest du gerade?';

  @override
  String get timerProjectLabel => 'Projekt';

  @override
  String get timerNewProjectTooltip => 'Neues Projekt';

  @override
  String get timerStart => 'Start';

  @override
  String get timerIdleTitle => 'Inaktiv erkannt';

  @override
  String timerIdleMessage(int minutes) {
    return 'Du warst seit $minutes Minuten inaktiv. Soll diese Zeit vom laufenden Eintrag abgezogen werden?';
  }

  @override
  String get timerIdleKeepTime => 'Zeit behalten';

  @override
  String get timerIdleTrimTime => 'Inaktive Zeit abziehen';
}
