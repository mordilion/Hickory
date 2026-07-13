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

  @override
  String get syncJiraSectionTitle => 'Integrazione Jira';

  @override
  String get syncJiraBaseUrlLabel => 'URL Jira';

  @override
  String get syncJiraEmailLabel => 'Email';

  @override
  String get syncJiraApiTokenLabel => 'Token API';

  @override
  String get syncJiraSaveCredentialsButton => 'Salva credenziali';

  @override
  String get syncJiraCredentialsSaved => 'Credenziali salvate.';

  @override
  String get syncJiraTestConnectionButton => 'Verifica connessione';

  @override
  String get syncJiraTestConnectionSuccess => 'Connessione riuscita.';

  @override
  String get syncJiraTestConnectionFailure =>
      'Connessione non riuscita. Controlla le credenziali.';

  @override
  String get syncJiraSyncButton => 'Sincronizza ora con Jira';

  @override
  String get syncJiraNotConfigured => 'Jira non è ancora configurato.';

  @override
  String get syncJiraInvalidCredentials =>
      'Inserisci un URL Jira, un\'email e un token API validi.';

  @override
  String get syncJiraUnexpectedError => 'Si è verificato un errore. Riprova.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created create, $updated aggiornate, $deleted eliminate, $failed non riuscite.';
  }

  @override
  String get navTimer => 'Timer';

  @override
  String get navReports => 'Report';

  @override
  String get navSync => 'Sincronizzazione';

  @override
  String get navSettings => 'Impostazioni';

  @override
  String get commonNoProject => 'Nessun progetto';

  @override
  String timerError(String error) {
    return 'Errore: $error';
  }

  @override
  String get timerResume => 'Riprendi';

  @override
  String get timerPause => 'Pausa';

  @override
  String get timerStop => 'Ferma';

  @override
  String get timerDescriptionLabel => 'Su cosa stai lavorando?';

  @override
  String get timerProjectLabel => 'Progetto';

  @override
  String get timerNewProjectTooltip => 'Nuovo progetto';

  @override
  String get jiraTicketFieldLabel => 'Ticket Jira';

  @override
  String get timerStart => 'Avvia';

  @override
  String get timerIdleTitle => 'Inattività rilevata';

  @override
  String timerIdleMessage(int minutes) {
    return 'Sei stato inattivo per $minutes minuti. Vuoi sottrarre questo tempo dalla voce in corso?';
  }

  @override
  String get timerIdleKeepTime => 'Mantieni il tempo';

  @override
  String get timerIdleTrimTime => 'Sottrai il tempo inattivo';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonSave => 'Salva';

  @override
  String get entriesEmpty => 'Ancora nessuna voce.';

  @override
  String get entriesNoDescription => 'Senza descrizione';

  @override
  String entriesError(String error) {
    return 'Errore: $error';
  }

  @override
  String get entriesManualEntryTitle => 'Voce manuale';

  @override
  String get entriesEditEntryTitle => 'Modifica voce';

  @override
  String get entriesDescriptionLabel => 'Descrizione';

  @override
  String get entriesProjectLabel => 'Progetto';

  @override
  String get entriesStartLabel => 'Inizio';

  @override
  String get entriesEndLabel => 'Fine';

  @override
  String get entriesEndBeforeStartError =>
      'La fine deve essere successiva all\'inizio.';

  @override
  String get projectsNewProjectTitle => 'Nuovo progetto';

  @override
  String get projectsNameLabel => 'Nome';

  @override
  String get projectsCreateButton => 'Crea';

  @override
  String get reportsTitle => 'Report';

  @override
  String get reportsThisWeek => 'Questa settimana';

  @override
  String get reportsThisMonth => 'Questo mese';

  @override
  String get reportsLast30Days => 'Ultimi 30 giorni';

  @override
  String get reportsAll => 'Tutti';

  @override
  String get reportsCustomRange => 'Personalizzato…';

  @override
  String reportsError(String error) {
    return 'Errore: $error';
  }

  @override
  String get reportsExportCsv => 'Esporta CSV';

  @override
  String reportsExportedTo(String path) {
    return 'Esportato in: $path';
  }

  @override
  String reportsTotal(String duration) {
    return 'Totale: $duration';
  }

  @override
  String get reportsEmptyRange => 'Nessuna voce in questo periodo.';

  @override
  String get csvHeaderDate => 'Data';

  @override
  String get csvHeaderStart => 'Inizio';

  @override
  String get csvHeaderEnd => 'Fine';

  @override
  String get csvHeaderDurationHours => 'Durata (h)';

  @override
  String get csvHeaderProject => 'Progetto';

  @override
  String get csvHeaderDescription => 'Descrizione';

  @override
  String get csvHeaderBillable => 'Fatturabile';

  @override
  String get csvHeaderAmount => 'Importo';

  @override
  String get csvHeaderCurrency => 'Valuta';

  @override
  String get csvYes => 'sì';

  @override
  String get csvNo => 'no';

  @override
  String get entriesJiraStatusSynced => 'Registrato su Jira';

  @override
  String get entriesJiraStatusPending => 'Registrazione Jira in sospeso';

  @override
  String get entriesJiraStatusError => 'Registrazione Jira non riuscita';
}
