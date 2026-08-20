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
  String get settingsCategoryGeneral => 'Allgemein';

  @override
  String get settingsCategoryTimeTracking => 'Zeiterfassung';

  @override
  String get settingsAutostart => 'Beim Systemstart öffnen';

  @override
  String get settingsDateFormat => 'Datumsformat';

  @override
  String get settingsTimeFormat => 'Zeitformat';

  @override
  String get settingsUpdateTitle => 'Updates';

  @override
  String settingsUpdateCurrentVersion(Object version) {
    return 'Aktuelle Version: $version';
  }

  @override
  String get settingsUpdateCheckButton => 'Nach Updates suchen';

  @override
  String get settingsUpdateChecking => 'Suche nach Updates...';

  @override
  String get settingsUpdateUpToDate => 'Du hast die neueste Version.';

  @override
  String get settingsUpdateCheckError =>
      'Update-Prüfung fehlgeschlagen. Bitte versuche es später erneut.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'Version $version ist verfügbar.';
  }

  @override
  String get settingsUpdateInstallButton => 'Jetzt installieren';

  @override
  String get settingsUpdateInstalling => 'Update wird installiert...';

  @override
  String get settingsUpdateInstallError =>
      'Installation fehlgeschlagen. Bitte versuche es erneut oder lade die neue Version manuell von GitHub herunter.';

  @override
  String settingsUpdateInstallErrorPermission(String path) {
    return 'Hickory kann seinen Installationsordner nicht ersetzen ($path). Das passiert, wenn die App einem anderen Benutzerkonto gehört. Verschiebe sie in deinen eigenen Programme-Ordner oder aktualisiere manuell über GitHub.';
  }

  @override
  String settingsUpdateDownloading(String received, String total) {
    return 'Lade Update … $received von $total MB';
  }

  @override
  String settingsUpdateDownloadingUnknownSize(String received) {
    return 'Lade Update … $received MB';
  }

  @override
  String get settingsUpdateVerifying => 'Prüfsumme wird geprüft …';

  @override
  String get settingsUpdateExtracting => 'Update wird entpackt …';

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
  String get syncJiraSectionTitle => 'Jira-Integration';

  @override
  String get syncJiraBaseUrlLabel => 'Jira-URL';

  @override
  String get syncJiraEmailLabel => 'E-Mail';

  @override
  String get syncJiraApiTokenLabel => 'API-Token';

  @override
  String get syncJiraSaveCredentialsButton => 'Zugangsdaten speichern';

  @override
  String get syncJiraCredentialsSaved => 'Zugangsdaten gespeichert.';

  @override
  String get syncJiraTestConnectionButton => 'Verbindung testen';

  @override
  String get syncJiraTestConnectionSuccess => 'Verbindung erfolgreich.';

  @override
  String get syncJiraTestConnectionFailure =>
      'Verbindung fehlgeschlagen. Bitte Zugangsdaten prüfen.';

  @override
  String get syncJiraSyncButton => 'Jetzt zu Jira synchronisieren';

  @override
  String get syncJiraNotConfigured => 'Jira ist noch nicht konfiguriert.';

  @override
  String get syncJiraInvalidCredentials =>
      'Bitte gib eine gültige Jira-URL sowie E-Mail und API-Token an.';

  @override
  String get syncJiraUnexpectedError =>
      'Es ist ein Fehler aufgetreten. Bitte versuche es erneut.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created erstellt, $updated aktualisiert, $deleted gelöscht, $failed fehlgeschlagen.';
  }

  @override
  String get syncPersonioSectionTitle => 'Personio-Integration';

  @override
  String get syncPersonioClientIdLabel => 'Client ID';

  @override
  String get syncPersonioClientSecretLabel => 'Client Secret';

  @override
  String get syncPersonioEmployeeIdLabel => 'Mitarbeiter-ID';

  @override
  String get syncPersonioSaveCredentialsButton => 'Zugangsdaten speichern';

  @override
  String get syncPersonioCredentialsSaved => 'Zugangsdaten gespeichert.';

  @override
  String get syncPersonioTestConnectionButton => 'Verbindung testen';

  @override
  String get syncPersonioTestConnectionSuccess => 'Verbindung erfolgreich.';

  @override
  String get syncPersonioTestConnectionFailure =>
      'Verbindung fehlgeschlagen. Bitte Zugangsdaten prüfen.';

  @override
  String get syncPersonioNotConfigured =>
      'Personio ist noch nicht konfiguriert.';

  @override
  String get syncPersonioInvalidCredentials =>
      'Bitte gib Client ID, Client Secret und Mitarbeiter-ID an.';

  @override
  String get syncPersonioUnexpectedError =>
      'Es ist ein Fehler aufgetreten. Bitte versuche es erneut.';

  @override
  String get syncPersonioFromLabel => 'Von';

  @override
  String get syncPersonioToLabel => 'Bis';

  @override
  String get syncPersonioPushButton => 'Zeiten nach Personio pushen';

  @override
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  ) {
    return '$created erstellt, $updated aktualisiert, $deleted gelöscht, $failed fehlgeschlagen.';
  }

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
  String get timerModeManual => 'Manuell';

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
  String get commonDelete => 'Löschen';

  @override
  String get commonClose => 'Schließen';

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
  String get entriesDeleteConfirmTitle => 'Eintrag löschen?';

  @override
  String get entriesDeleteConfirmMessage =>
      'Dieser Eintrag wird endgültig gelöscht. Das kann nicht rückgängig gemacht werden.';

  @override
  String entriesBreakLabel(String duration) {
    return 'Pause: $duration';
  }

  @override
  String get entriesBreakInsufficientTooltip => 'Pause zu kurz';

  @override
  String get entriesToday => 'Heute';

  @override
  String get entriesYesterday => 'Gestern';

  @override
  String get migrationFailedTitle => 'Daten konnten nicht übernommen werden';

  @override
  String migrationFailedMessage(String path, String error) {
    return 'Hickory hat seine bisherigen Daten gefunden, konnte sie aber nicht an den neuen Ort kopieren. Die App startet absichtlich nicht weiter, damit keine leere Datenbank entsteht und die alten Daten erreichbar bleiben. Sie liegen unter:\n\n$path\n\nDie vorherige Version kann sie weiterhin öffnen. Fehler: $error';
  }

  @override
  String entriesWeekLabel(int week) {
    return 'KW $week';
  }

  @override
  String get entriesUpOneLevelTooltip => 'Eine Ebene höher';

  @override
  String get entriesAllYearsLabel => 'Alle Jahre';

  @override
  String entriesWeekDayRange(int first, int last) {
    return '$first.–$last.';
  }

  @override
  String entriesWeekHeader(int week, String range) {
    return 'KW $week · $range';
  }

  @override
  String entriesWorkLabel(String duration) {
    return 'Arbeitszeit: $duration';
  }

  @override
  String entriesBreakInsufficientDaysTooltip(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage mit zu kurzer Pause',
      one: '1 Tag mit zu kurzer Pause',
    );
    return '$_temp0';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes Min';
  }

  @override
  String get quickAddSubmitLabel => 'Eintrag hinzufügen';

  @override
  String get settingsQuickAddTitle => 'Schnelleingabe';

  @override
  String get settingsQuickAddDescription =>
      'Diese Zeitdauern erscheinen als Schnellauswahl im Timer-Tab.';

  @override
  String get settingsQuickAddAddLabel => 'Hinzufügen';

  @override
  String get settingsQuickAddRemoveTooltip => 'Entfernen';

  @override
  String get settingsQuickAddNewDurationLabel => 'Minuten';

  @override
  String get settingsBreakRuleTitle => 'Pausenregeln';

  @override
  String get settingsBreakRuleDescription =>
      'Legt fest, ab wie viel Arbeitszeit wie viel Pause nötig ist. Die Tagesübersicht warnt, wenn die Pause zu kurz war.';

  @override
  String get settingsBreakRulePresetGermany => 'Deutschland';

  @override
  String get settingsBreakRulePresetAustria => 'Österreich';

  @override
  String get settingsBreakRulePresetSwitzerland => 'Schweiz';

  @override
  String get settingsBreakRuleNone => 'Keine';

  @override
  String settingsBreakRuleTierLabel(String worked, String breakTime) {
    return 'Ab $worked → $breakTime Pause';
  }

  @override
  String get settingsBreakRuleRemoveTooltip => 'Entfernen';

  @override
  String get settingsBreakRuleAddLabel => 'Regel hinzufügen';

  @override
  String get settingsBreakRuleAddTitle => 'Neue Pausenregel';

  @override
  String get settingsBreakRuleAfterMinutesLabel => 'Ab Minuten Arbeit';

  @override
  String get settingsBreakRuleRequiredMinutesLabel => 'Minuten Pause nötig';

  @override
  String get settingsBreakRuleSaveError =>
      'Änderung konnte nicht gespeichert werden.';

  @override
  String get settingsBreakRuleInvalidTierError =>
      'Bitte gültige Minutenwerte eingeben.';

  @override
  String get settingsBreakRuleIncludePausedTime =>
      'Pause-Button-Zeit einbeziehen';

  @override
  String get settingsBreakRuleIncludePausedTimeDescription =>
      'Zählt die über den Pause-Button pausierte Zeit zusätzlich zu Lücken zwischen Einträgen als Pause.';

  @override
  String get settingsProjectsTitle => 'Projekte';

  @override
  String get settingsProjectsDescription =>
      'Projekte anlegen, bearbeiten und archivieren.';

  @override
  String get settingsProjectsAddLabel => 'Projekt hinzufügen';

  @override
  String get settingsProjectsArchivedSection => 'Archivierte Projekte';

  @override
  String get settingsProjectsSaveError =>
      'Änderung konnte nicht gespeichert werden.';

  @override
  String get projectsNewProjectTitle => 'Neues Projekt';

  @override
  String get projectsNameLabel => 'Name';

  @override
  String get projectsCreateButton => 'Erstellen';

  @override
  String get projectsEditTitle => 'Projekt bearbeiten';

  @override
  String get projectsBillableLabel => 'Abrechenbar';

  @override
  String get projectsHourlyRateLabel => 'Stundensatz';

  @override
  String get projectsCurrencyLabel => 'Währung';

  @override
  String get projectsArchiveTooltip => 'Archivieren';

  @override
  String get projectsUnarchiveTooltip => 'Reaktivieren';

  @override
  String get projectsEditTooltip => 'Bearbeiten';

  @override
  String get projectsDeleteTooltip => 'Löschen';

  @override
  String get projectsDeleteConfirmTitle => 'Projekt löschen?';

  @override
  String get projectsDeleteConfirmMessage =>
      'Dieses Projekt wird endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get projectsDeleteHasEntriesError =>
      'Dieses Projekt hat noch zugewiesene Zeiteinträge und kann nicht gelöscht werden.';

  @override
  String get projectsInvalidRateError =>
      'Bitte einen gültigen Betrag eingeben.';

  @override
  String get settingsClientsTitle => 'Kunden';

  @override
  String get settingsClientsDescription =>
      'Kunden anlegen, bearbeiten und archivieren.';

  @override
  String get settingsClientsAddLabel => 'Kunde hinzufügen';

  @override
  String get settingsClientsArchivedSection => 'Archivierte Kunden';

  @override
  String get settingsClientsSaveError =>
      'Änderung konnte nicht gespeichert werden.';

  @override
  String get clientsNewClientTitle => 'Neuer Kunde';

  @override
  String get clientsNameLabel => 'Name';

  @override
  String get clientsCreateButton => 'Erstellen';

  @override
  String get clientsEditTitle => 'Kunde bearbeiten';

  @override
  String get clientsEditTooltip => 'Bearbeiten';

  @override
  String get clientsArchiveTooltip => 'Archivieren';

  @override
  String get clientsUnarchiveTooltip => 'Reaktivieren';

  @override
  String get clientsDeleteTooltip => 'Löschen';

  @override
  String get clientsDeleteConfirmTitle => 'Kunde löschen?';

  @override
  String get clientsDeleteConfirmMessage =>
      'Dieser Kunde wird endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get clientsDeleteHasProjectsError =>
      'Dieser Kunde hat noch zugewiesene Projekte und kann nicht gelöscht werden.';

  @override
  String get projectsClientLabel => 'Kunde';

  @override
  String get projectsClientNone => 'Kein Kunde';

  @override
  String get projectsClientCreateNew => '+ Neuer Kunde…';

  @override
  String projectsClientArchivedLabel(String name) {
    return '$name (archiviert)';
  }

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
  String get reportsToday => 'Heute';

  @override
  String get reportsYesterday => 'Gestern';

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
  String get reportsEmptyFiltered =>
      'Keine Einträge für diesen Zeitraum und diese Filter.';

  @override
  String get reportsFilterTooltip => 'Filter';

  @override
  String get reportsFilterDialogTitle => 'Filter';

  @override
  String get reportsFilterProjectsLabel => 'Projekte';

  @override
  String get reportsFilterProjectsHint =>
      'Keine Auswahl entspricht allen Projekten.';

  @override
  String get reportsFilterBillableLabel => 'Abrechenbar';

  @override
  String get reportsFilterBillableAll => 'Alle';

  @override
  String get reportsFilterBillableOnly => 'Nur abrechenbar';

  @override
  String get reportsFilterBillableNonOnly => 'Nur nicht abrechenbar';

  @override
  String get reportsFilterReset => 'Filter zurücksetzen';

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

  @override
  String get entriesPersonioStatusSynced => 'In Personio erfasst';

  @override
  String get entriesPersonioStatusPending => 'Personio-Erfassung ausstehend';

  @override
  String get entriesPersonioStatusError => 'Personio-Erfassung fehlgeschlagen';

  @override
  String get syncFailedEntriesTitle => 'Fehlgeschlagene Einträge';

  @override
  String get settingsResetTitle => 'Zurücksetzen';

  @override
  String get settingsResetDescription =>
      'Löscht alle lokalen Daten dieses Geräts (Projekte, Kunden, Zeiteinträge, Einstellungen, Jira-/Personio-Verknüpfungen), entfernt den eigenen Verlauf dieses Geräts endgültig aus dem Sync-Ordner und trennt die Verbindung dazu. Andere Geräte sind davon nicht betroffen, können den entfernten Verlauf aber auch nicht mehr nachträglich sehen.';

  @override
  String get settingsResetButton => 'Komplett zurücksetzen';

  @override
  String get settingsResetConfirmTitle => 'Wirklich alles zurücksetzen?';

  @override
  String get settingsResetConfirmMessage =>
      'Projekte, Kunden, Zeiteinträge, Einstellungen und Jira-/Personio-Verknüpfungen auf diesem Gerät werden unwiderruflich gelöscht. Der eigene Verlauf dieses Geräts wird auch endgültig aus dem Sync-Ordner entfernt, und die Verbindung dazu wird getrennt. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get settingsResetConfirmButton => 'Ja, alles zurücksetzen';

  @override
  String get settingsResetSuccess => 'App wurde zurückgesetzt.';

  @override
  String get settingsResetError => 'Zurücksetzen fehlgeschlagen.';
}
