// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get trayOpen => 'Openen';

  @override
  String get trayQuit => 'Afsluiten';

  @override
  String get trayBackgroundNotice =>
      'Hickory blijft op de achtergrond draaien.';

  @override
  String get settingsLanguage => 'Taal';

  @override
  String settingsLanguageSystem(String language) {
    return 'Systeemstandaard ($language)';
  }

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String get settingsAutostart => 'Openen bij systeemstart';

  @override
  String get settingsDateFormat => 'Datumnotatie';

  @override
  String get settingsTimeFormat => 'Tijdnotatie';

  @override
  String get settingsUpdateTitle => 'Updates';

  @override
  String settingsUpdateCurrentVersion(Object version) {
    return 'Huidige versie: $version';
  }

  @override
  String get settingsUpdateCheckButton => 'Naar updates zoeken';

  @override
  String get settingsUpdateChecking => 'Zoeken naar updates...';

  @override
  String get settingsUpdateUpToDate => 'Je hebt de nieuwste versie.';

  @override
  String get settingsUpdateCheckError =>
      'Update-controle mislukt. Probeer het later opnieuw.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'Versie $version is beschikbaar.';
  }

  @override
  String get settingsUpdateInstallButton => 'Nu installeren';

  @override
  String get settingsUpdateInstalling => 'Update wordt geïnstalleerd...';

  @override
  String get settingsUpdateInstallError =>
      'Installatie mislukt. Probeer het opnieuw of download de nieuwe versie handmatig van GitHub.';

  @override
  String get settingsUpdateInstallErrorPermission =>
      'Hickory heeft geen schrijftoegang tot de installatiemap. Verplaats de app naar een locatie waar je wel kunt schrijven, of werk handmatig bij via GitHub.';

  @override
  String get syncTitle => 'Synchronisatie-instellingen';

  @override
  String get syncNoFolderSelected =>
      'Geen map geselecteerd – gegevens blijven alleen op dit apparaat.';

  @override
  String syncFolderPath(String path) {
    return 'Synchronisatiemap: $path';
  }

  @override
  String syncError(String error) {
    return 'Fout: $error';
  }

  @override
  String get syncFolderDescription =>
      'Kies een map die al wordt gesynchroniseerd door iCloud Drive, Google Drive, Dropbox of vergelijkbaar. Hickory schrijft daar alleen eigen bestanden en synchroniseert zichzelf niet met de cloud.';

  @override
  String get syncNowButton => 'Nu synchroniseren';

  @override
  String get syncChooseFolderButton => 'Map kiezen';

  @override
  String syncFolderChosen(String path) {
    return 'Map geselecteerd: $path';
  }

  @override
  String get syncCompleted => 'Synchronisatie voltooid.';

  @override
  String get syncJiraSectionTitle => 'Jira-integratie';

  @override
  String get syncJiraBaseUrlLabel => 'Jira-URL';

  @override
  String get syncJiraEmailLabel => 'E-mail';

  @override
  String get syncJiraApiTokenLabel => 'API-token';

  @override
  String get syncJiraSaveCredentialsButton => 'Gegevens opslaan';

  @override
  String get syncJiraCredentialsSaved => 'Gegevens opgeslagen.';

  @override
  String get syncJiraTestConnectionButton => 'Verbinding testen';

  @override
  String get syncJiraTestConnectionSuccess => 'Verbinding geslaagd.';

  @override
  String get syncJiraTestConnectionFailure =>
      'Verbinding mislukt. Controleer je gegevens.';

  @override
  String get syncJiraSyncButton => 'Nu synchroniseren met Jira';

  @override
  String get syncJiraNotConfigured => 'Jira is nog niet geconfigureerd.';

  @override
  String get syncJiraInvalidCredentials =>
      'Voer een geldige Jira-URL, e-mail en API-token in.';

  @override
  String get syncJiraUnexpectedError =>
      'Er is een fout opgetreden. Probeer het opnieuw.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created aangemaakt, $updated bijgewerkt, $deleted verwijderd, $failed mislukt.';
  }

  @override
  String get syncPersonioSectionTitle => 'Personio-integratie';

  @override
  String get syncPersonioClientIdLabel => 'Client ID';

  @override
  String get syncPersonioClientSecretLabel => 'Client Secret';

  @override
  String get syncPersonioEmployeeIdLabel => 'Werknemers-ID';

  @override
  String get syncPersonioSaveCredentialsButton => 'Gegevens opslaan';

  @override
  String get syncPersonioCredentialsSaved => 'Gegevens opgeslagen.';

  @override
  String get syncPersonioTestConnectionButton => 'Verbinding testen';

  @override
  String get syncPersonioTestConnectionSuccess => 'Verbinding gelukt.';

  @override
  String get syncPersonioTestConnectionFailure =>
      'Verbinding mislukt. Controleer je gegevens.';

  @override
  String get syncPersonioNotConfigured =>
      'Personio is nog niet geconfigureerd.';

  @override
  String get syncPersonioInvalidCredentials =>
      'Voer Client ID, Client Secret en werknemers-ID in.';

  @override
  String get syncPersonioUnexpectedError =>
      'Er is iets misgegaan. Probeer het opnieuw.';

  @override
  String get syncPersonioFromLabel => 'Van';

  @override
  String get syncPersonioToLabel => 'Tot';

  @override
  String get syncPersonioPushButton => 'Naar Personio pushen';

  @override
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  ) {
    return '$created aangemaakt, $updated bijgewerkt, $deleted verwijderd, $failed mislukt.';
  }

  @override
  String get navTimer => 'Timer';

  @override
  String get navReports => 'Rapporten';

  @override
  String get navSync => 'Synchronisatie';

  @override
  String get navSettings => 'Instellingen';

  @override
  String get commonNoProject => 'Geen project';

  @override
  String timerError(String error) {
    return 'Fout: $error';
  }

  @override
  String get timerResume => 'Hervatten';

  @override
  String get timerPause => 'Pauzeren';

  @override
  String get timerStop => 'Stoppen';

  @override
  String get timerDescriptionLabel => 'Waar werk je aan?';

  @override
  String get timerProjectLabel => 'Project';

  @override
  String get timerNewProjectTooltip => 'Nieuw project';

  @override
  String get jiraTicketFieldLabel => 'Jira-ticket';

  @override
  String get timerStart => 'Starten';

  @override
  String get timerModeManual => 'Handmatig';

  @override
  String get timerIdleTitle => 'Inactiviteit gedetecteerd';

  @override
  String timerIdleMessage(int minutes) {
    return 'Je bent al $minutes minuten inactief. Wil je deze tijd van de lopende invoer aftrekken?';
  }

  @override
  String get timerIdleKeepTime => 'Tijd behouden';

  @override
  String get timerIdleTrimTime => 'Inactieve tijd aftrekken';

  @override
  String get commonCancel => 'Annuleren';

  @override
  String get commonSave => 'Opslaan';

  @override
  String get commonDelete => 'Verwijderen';

  @override
  String get entriesEmpty => 'Nog geen invoer.';

  @override
  String get entriesNoDescription => 'Zonder beschrijving';

  @override
  String entriesError(String error) {
    return 'Fout: $error';
  }

  @override
  String get entriesManualEntryTitle => 'Handmatige invoer';

  @override
  String get entriesEditEntryTitle => 'Invoer bewerken';

  @override
  String get entriesDescriptionLabel => 'Beschrijving';

  @override
  String get entriesProjectLabel => 'Project';

  @override
  String get entriesStartLabel => 'Start';

  @override
  String get entriesEndLabel => 'Einde';

  @override
  String get entriesEndBeforeStartError =>
      'Het einde moet na het begin liggen.';

  @override
  String get entriesDeleteConfirmTitle => 'Item verwijderen?';

  @override
  String get entriesDeleteConfirmMessage =>
      'Dit item wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.';

  @override
  String entriesBreakLabel(String duration) {
    return 'Pauze: $duration';
  }

  @override
  String get entriesBreakInsufficientTooltip => 'Pauze te kort';

  @override
  String get entriesToday => 'Vandaag';

  @override
  String get entriesYesterday => 'Gisteren';

  @override
  String entriesDayHeader(String day, String total) {
    return '$day · $total';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get quickAddMoreTooltip => 'Meer opties';

  @override
  String get quickAddSubmitTooltip => 'Invoer toevoegen';

  @override
  String get settingsQuickAddTitle => 'Snel toevoegen';

  @override
  String get settingsQuickAddDescription =>
      'Deze duren verschijnen als snelkeuzeknoppen op het tabblad Timer.';

  @override
  String get settingsQuickAddAddLabel => 'Toevoegen';

  @override
  String get settingsQuickAddRemoveTooltip => 'Verwijderen';

  @override
  String get settingsQuickAddNewDurationLabel => 'Minuten';

  @override
  String get settingsBreakRuleTitle => 'Pauzeregels';

  @override
  String get settingsBreakRuleDescription =>
      'Bepaalt hoeveel pauze nodig is na hoeveel werktijd. Het dagoverzicht waarschuwt als de pauze te kort was.';

  @override
  String get settingsBreakRulePresetGermany => 'Duitsland';

  @override
  String get settingsBreakRulePresetAustria => 'Oostenrijk';

  @override
  String get settingsBreakRulePresetSwitzerland => 'Zwitserland';

  @override
  String get settingsBreakRuleNone => 'Geen';

  @override
  String settingsBreakRuleTierLabel(String worked, String breakTime) {
    return 'Na $worked → $breakTime pauze';
  }

  @override
  String get settingsBreakRuleRemoveTooltip => 'Verwijderen';

  @override
  String get settingsBreakRuleAddLabel => 'Regel toevoegen';

  @override
  String get settingsBreakRuleAddTitle => 'Nieuwe pauzeregel';

  @override
  String get settingsBreakRuleAfterMinutesLabel => 'Na minuten gewerkt';

  @override
  String get settingsBreakRuleRequiredMinutesLabel => 'Minuten pauze nodig';

  @override
  String get settingsBreakRuleSaveError =>
      'Wijziging kon niet worden opgeslagen.';

  @override
  String get settingsBreakRuleInvalidTierError =>
      'Voer geldige minutenwaarden in.';

  @override
  String get settingsBreakRuleIncludePausedTime => 'Pauzeknoptijd meetellen';

  @override
  String get settingsBreakRuleIncludePausedTimeDescription =>
      'Telt de tijd die via de pauzeknop is gepauzeerd mee als pauze, naast de hiaten tussen items.';

  @override
  String get settingsProjectsTitle => 'Projecten';

  @override
  String get settingsProjectsDescription =>
      'Projecten aanmaken, bewerken en archiveren.';

  @override
  String get settingsProjectsAddLabel => 'Project toevoegen';

  @override
  String get settingsProjectsArchivedSection => 'Gearchiveerde projecten';

  @override
  String get settingsProjectsSaveError =>
      'Wijziging kon niet worden opgeslagen.';

  @override
  String get projectsNewProjectTitle => 'Nieuw project';

  @override
  String get projectsNameLabel => 'Naam';

  @override
  String get projectsCreateButton => 'Aanmaken';

  @override
  String get projectsEditTitle => 'Project bewerken';

  @override
  String get projectsBillableLabel => 'Factureerbaar';

  @override
  String get projectsHourlyRateLabel => 'Uurtarief';

  @override
  String get projectsCurrencyLabel => 'Valuta';

  @override
  String get projectsArchiveTooltip => 'Archiveren';

  @override
  String get projectsUnarchiveTooltip => 'Heractiveren';

  @override
  String get projectsEditTooltip => 'Bewerken';

  @override
  String get projectsInvalidRateError => 'Voer een geldig bedrag in.';

  @override
  String get reportsTitle => 'Rapporten';

  @override
  String get reportsThisWeek => 'Deze week';

  @override
  String get reportsThisMonth => 'Deze maand';

  @override
  String get reportsLast30Days => 'Laatste 30 dagen';

  @override
  String get reportsAll => 'Alles';

  @override
  String get reportsCustomRange => 'Aangepast…';

  @override
  String reportsError(String error) {
    return 'Fout: $error';
  }

  @override
  String get reportsExportCsv => 'CSV exporteren';

  @override
  String reportsExportedTo(String path) {
    return 'Geëxporteerd naar: $path';
  }

  @override
  String reportsTotal(String duration) {
    return 'Totaal: $duration';
  }

  @override
  String get reportsEmptyRange => 'Geen invoer in deze periode.';

  @override
  String get csvHeaderDate => 'Datum';

  @override
  String get csvHeaderStart => 'Start';

  @override
  String get csvHeaderEnd => 'Einde';

  @override
  String get csvHeaderDurationHours => 'Duur (u)';

  @override
  String get csvHeaderProject => 'Project';

  @override
  String get csvHeaderDescription => 'Beschrijving';

  @override
  String get csvHeaderBillable => 'Factureerbaar';

  @override
  String get csvHeaderAmount => 'Bedrag';

  @override
  String get csvHeaderCurrency => 'Valuta';

  @override
  String get csvYes => 'ja';

  @override
  String get csvNo => 'nee';

  @override
  String get entriesJiraStatusSynced => 'Geboekt in Jira';

  @override
  String get entriesJiraStatusPending => 'Jira-boeking in behandeling';

  @override
  String get entriesJiraStatusError => 'Jira-boeking mislukt';
}
