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
  String get settingsCategoryGeneral => 'Algemeen';

  @override
  String get settingsCategoryTimeTracking => 'Tijdregistratie';

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
  String settingsUpdateInstallErrorPermission(String path) {
    return 'Hickory kan zijn installatiemap niet vervangen ($path). Dat gebeurt wanneer de app van een ander gebruikersaccount is. Verplaats hem naar je eigen Programma\'s-map of werk handmatig bij via GitHub.';
  }

  @override
  String settingsUpdateDownloading(String received, String total) {
    return 'Update downloaden … $received van $total MB';
  }

  @override
  String settingsUpdateDownloadingUnknownSize(String received) {
    return 'Update downloaden … $received MB';
  }

  @override
  String get settingsUpdateVerifying => 'Controlesom controleren …';

  @override
  String get settingsUpdateExtracting => 'Update uitpakken …';

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
  String get commonClose => 'Sluiten';

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
  String get migrationFailedTitle => 'Gegevens konden niet worden overgezet';

  @override
  String migrationFailedMessage(String path, String error) {
    return 'Hickory heeft je bestaande gegevens gevonden maar kon ze niet naar de nieuwe locatie kopiëren. De app gaat opzettelijk niet verder, zodat er geen lege database ontstaat en de oude gegevens bereikbaar blijven. Ze staan in:\n\n$path\n\nDe vorige versie kan ze nog openen. Fout: $error';
  }

  @override
  String entriesWeekLabel(int week) {
    return 'Week $week';
  }

  @override
  String get entriesUpOneLevelTooltip => 'Eén niveau omhoog';

  @override
  String get entriesAllYearsLabel => 'Alle jaren';

  @override
  String entriesWeekDayRange(int first, int last) {
    return '$first–$last';
  }

  @override
  String entriesWeekHeader(int week, String range) {
    return 'Week $week · $range';
  }

  @override
  String entriesWorkLabel(String duration) {
    return 'Gewerkt: $duration';
  }

  @override
  String entriesBreakInsufficientDaysTooltip(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagen met te korte pauzes',
      one: '1 dag met een te korte pauze',
    );
    return '$_temp0';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get quickAddSubmitLabel => 'Invoer toevoegen';

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
  String get projectsDeleteTooltip => 'Verwijderen';

  @override
  String get projectsDeleteConfirmTitle => 'Project verwijderen?';

  @override
  String get projectsDeleteConfirmMessage =>
      'Dit project wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get projectsDeleteHasEntriesError =>
      'Dit project heeft nog gekoppelde tijdregistraties en kan niet worden verwijderd.';

  @override
  String get projectsInvalidRateError => 'Voer een geldig bedrag in.';

  @override
  String get settingsClientsTitle => 'Klanten';

  @override
  String get settingsClientsDescription =>
      'Klanten aanmaken, bewerken en archiveren.';

  @override
  String get settingsClientsAddLabel => 'Klant toevoegen';

  @override
  String get settingsClientsArchivedSection => 'Gearchiveerde klanten';

  @override
  String get settingsClientsSaveError =>
      'Wijziging kon niet worden opgeslagen.';

  @override
  String get clientsNewClientTitle => 'Nieuwe klant';

  @override
  String get clientsNameLabel => 'Naam';

  @override
  String get clientsCreateButton => 'Aanmaken';

  @override
  String get clientsEditTitle => 'Klant bewerken';

  @override
  String get clientsEditTooltip => 'Bewerken';

  @override
  String get clientsArchiveTooltip => 'Archiveren';

  @override
  String get clientsUnarchiveTooltip => 'Heractiveren';

  @override
  String get clientsDeleteTooltip => 'Verwijderen';

  @override
  String get clientsDeleteConfirmTitle => 'Klant verwijderen?';

  @override
  String get clientsDeleteConfirmMessage =>
      'Deze klant wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get clientsDeleteHasProjectsError =>
      'Deze klant heeft nog gekoppelde projecten en kan niet worden verwijderd.';

  @override
  String get projectsClientLabel => 'Klant';

  @override
  String get projectsClientNone => 'Geen klant';

  @override
  String get projectsClientCreateNew => '+ Nieuwe klant…';

  @override
  String projectsClientArchivedLabel(String name) {
    return '$name (gearchiveerd)';
  }

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
  String get reportsToday => 'Vandaag';

  @override
  String get reportsYesterday => 'Gisteren';

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
  String get reportsEmptyFiltered =>
      'Geen invoer voor deze periode en deze filters.';

  @override
  String get reportsFilterTooltip => 'Filter';

  @override
  String get reportsFilterDialogTitle => 'Filter';

  @override
  String get reportsFilterProjectsLabel => 'Projecten';

  @override
  String get reportsFilterProjectsHint =>
      'Geen selectie betekent alle projecten.';

  @override
  String get reportsFilterBillableLabel => 'Factureerbaar';

  @override
  String get reportsFilterBillableAll => 'Alles';

  @override
  String get reportsFilterBillableOnly => 'Alleen factureerbaar';

  @override
  String get reportsFilterBillableNonOnly => 'Alleen niet-factureerbaar';

  @override
  String get reportsFilterReset => 'Filters resetten';

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

  @override
  String get entriesPersonioStatusSynced => 'Geregistreerd in Personio';

  @override
  String get entriesPersonioStatusPending =>
      'Personio-registratie in behandeling';

  @override
  String get entriesPersonioStatusError => 'Personio-registratie mislukt';

  @override
  String get settingsResetTitle => 'Resetten';

  @override
  String get settingsResetDescription =>
      'Verwijdert alle lokale gegevens van dit apparaat (projecten, klanten, tijdregistraties, instellingen, Jira-/Personio-koppelingen), verwijdert de eigen geschiedenis van dit apparaat definitief uit de synchronisatiemap en koppelt het apparaat los. Andere apparaten worden niet beïnvloed, maar kunnen de verwijderde geschiedenis ook niet meer zien.';

  @override
  String get settingsResetButton => 'Alles resetten';

  @override
  String get settingsResetConfirmTitle => 'Alles echt resetten?';

  @override
  String get settingsResetConfirmMessage =>
      'Projecten, klanten, tijdregistraties, instellingen en Jira-/Personio-koppelingen op dit apparaat worden permanent verwijderd. Ook de eigen geschiedenis van dit apparaat wordt definitief uit de synchronisatiemap verwijderd, en de verbinding ermee wordt verbroken. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get settingsResetConfirmButton => 'Ja, alles resetten';

  @override
  String get settingsResetSuccess => 'De app is gereset.';

  @override
  String get settingsResetError => 'Resetten is mislukt.';
}
