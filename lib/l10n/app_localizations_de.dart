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
  String get jiraTicketFieldLabel => 'Jira-Ticket';

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

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get entriesEmpty => 'Noch keine Einträge.';

  @override
  String get entriesNoDescription => 'Ohne Beschreibung';

  @override
  String entriesError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get entriesManualEntryTitle => 'Manueller Eintrag';

  @override
  String get entriesEditEntryTitle => 'Eintrag bearbeiten';

  @override
  String get entriesDescriptionLabel => 'Beschreibung';

  @override
  String get entriesProjectLabel => 'Projekt';

  @override
  String get entriesStartLabel => 'Start';

  @override
  String get entriesEndLabel => 'Ende';

  @override
  String get entriesEndBeforeStartError => 'Ende muss nach dem Start liegen.';

  @override
  String get projectsNewProjectTitle => 'Neues Projekt';

  @override
  String get projectsNameLabel => 'Name';

  @override
  String get projectsCreateButton => 'Erstellen';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsThisWeek => 'Diese Woche';

  @override
  String get reportsThisMonth => 'Dieser Monat';

  @override
  String get reportsLast30Days => 'Letzte 30 Tage';

  @override
  String get reportsAll => 'Alle';

  @override
  String get reportsCustomRange => 'Benutzerdefiniert…';

  @override
  String reportsError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get reportsExportCsv => 'CSV exportieren';

  @override
  String reportsExportedTo(String path) {
    return 'Exportiert nach: $path';
  }

  @override
  String reportsTotal(String duration) {
    return 'Gesamt: $duration';
  }

  @override
  String get reportsEmptyRange => 'Keine Einträge in diesem Zeitraum.';

  @override
  String get csvHeaderDate => 'Datum';

  @override
  String get csvHeaderStart => 'Start';

  @override
  String get csvHeaderEnd => 'Ende';

  @override
  String get csvHeaderDurationHours => 'Dauer (Std)';

  @override
  String get csvHeaderProject => 'Projekt';

  @override
  String get csvHeaderDescription => 'Beschreibung';

  @override
  String get csvHeaderBillable => 'Abrechenbar';

  @override
  String get csvHeaderAmount => 'Betrag';

  @override
  String get csvHeaderCurrency => 'Währung';

  @override
  String get csvYes => 'ja';

  @override
  String get csvNo => 'nein';

  @override
  String get entriesJiraStatusSynced => 'In Jira gebucht';

  @override
  String get entriesJiraStatusPending => 'Jira-Buchung ausstehend';

  @override
  String get entriesJiraStatusError => 'Jira-Buchung fehlgeschlagen';
}
