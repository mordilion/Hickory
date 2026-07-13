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
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
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
  String get projectsNewProjectTitle => 'Nieuw project';

  @override
  String get projectsNameLabel => 'Naam';

  @override
  String get projectsCreateButton => 'Aanmaken';

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
