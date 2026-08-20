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
  String get settingsCategoryGeneral => 'Generale';

  @override
  String get settingsCategoryTimeTracking => 'Rilevamento del tempo';

  @override
  String get settingsAutostart => 'Avvia all\'accensione del sistema';

  @override
  String get settingsDateFormat => 'Formato data';

  @override
  String get settingsTimeFormat => 'Formato ora';

  @override
  String get settingsUpdateTitle => 'Aggiornamenti';

  @override
  String settingsUpdateCurrentVersion(Object version) {
    return 'Versione attuale: $version';
  }

  @override
  String get settingsUpdateCheckButton => 'Cerca aggiornamenti';

  @override
  String get settingsUpdateChecking => 'Ricerca aggiornamenti...';

  @override
  String get settingsUpdateUpToDate => 'Hai l\'ultima versione.';

  @override
  String get settingsUpdateCheckError =>
      'Controllo aggiornamenti non riuscito. Riprova più tardi.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'La versione $version è disponibile.';
  }

  @override
  String get settingsUpdateInstallButton => 'Installa ora';

  @override
  String get settingsUpdateInstalling => 'Installazione aggiornamento...';

  @override
  String get settingsUpdateInstallError =>
      'Installazione non riuscita. Riprova o scarica la nuova versione manualmente da GitHub.';

  @override
  String settingsUpdateInstallErrorPermission(String path) {
    return 'Hickory non può sostituire la sua cartella di installazione ($path). Succede quando l\'app appartiene a un altro account utente. Spostala nella tua cartella Applicazioni oppure aggiorna manualmente da GitHub.';
  }

  @override
  String settingsUpdateDownloading(String received, String total) {
    return 'Download aggiornamento … $received di $total MB';
  }

  @override
  String settingsUpdateDownloadingUnknownSize(String received) {
    return 'Download aggiornamento … $received MB';
  }

  @override
  String get settingsUpdateVerifying => 'Verifica del checksum …';

  @override
  String get settingsUpdateExtracting => 'Estrazione aggiornamento …';

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
  String get syncPersonioSectionTitle => 'Integrazione Personio';

  @override
  String get syncPersonioClientIdLabel => 'Client ID';

  @override
  String get syncPersonioClientSecretLabel => 'Client Secret';

  @override
  String get syncPersonioEmployeeIdLabel => 'ID dipendente';

  @override
  String get syncPersonioSaveCredentialsButton => 'Salva credenziali';

  @override
  String get syncPersonioCredentialsSaved => 'Credenziali salvate.';

  @override
  String get syncPersonioTestConnectionButton => 'Verifica connessione';

  @override
  String get syncPersonioTestConnectionSuccess => 'Connessione riuscita.';

  @override
  String get syncPersonioTestConnectionFailure =>
      'Connessione fallita. Controlla le credenziali.';

  @override
  String get syncPersonioNotConfigured => 'Personio non è ancora configurato.';

  @override
  String get syncPersonioInvalidCredentials =>
      'Inserisci Client ID, Client Secret e ID dipendente.';

  @override
  String get syncPersonioUnexpectedError =>
      'Si è verificato un errore. Riprova.';

  @override
  String get syncPersonioFromLabel => 'Da';

  @override
  String get syncPersonioToLabel => 'A';

  @override
  String get syncPersonioPushButton => 'Invia a Personio';

  @override
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  ) {
    return '$created creati, $updated aggiornati, $deleted eliminati, $failed falliti.';
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
  String get timerModeManual => 'Manuale';

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
  String get commonDelete => 'Elimina';

  @override
  String get commonClose => 'Chiudi';

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
  String get entriesDeleteConfirmTitle => 'Eliminare la voce?';

  @override
  String get entriesDeleteConfirmMessage =>
      'Questa voce verrà eliminata definitivamente. Questa azione non può essere annullata.';

  @override
  String entriesBreakLabel(String duration) {
    return 'Pausa: $duration';
  }

  @override
  String get entriesBreakInsufficientTooltip => 'Pausa troppo breve';

  @override
  String get entriesToday => 'Oggi';

  @override
  String get entriesYesterday => 'Ieri';

  @override
  String get migrationFailedTitle => 'Impossibile trasferire i dati';

  @override
  String migrationFailedMessage(String path, String error) {
    return 'Hickory ha trovato i dati esistenti ma non è riuscito a copiarli nella nuova posizione. Si ferma di proposito, per non creare un database vuoto e mantenere accessibili i vecchi dati. Si trovano in:\n\n$path\n\nLa versione precedente può ancora aprirli. Errore: $error';
  }

  @override
  String entriesWeekLabel(int week) {
    return 'Settimana $week';
  }

  @override
  String get entriesUpOneLevelTooltip => 'Su di un livello';

  @override
  String get entriesAllYearsLabel => 'Tutti gli anni';

  @override
  String entriesWeekDayRange(int first, int last) {
    return '$first–$last';
  }

  @override
  String entriesWeekHeader(int week, String range) {
    return 'Settimana $week · $range';
  }

  @override
  String entriesWorkLabel(String duration) {
    return 'Lavorato: $duration';
  }

  @override
  String entriesBreakInsufficientDaysTooltip(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni con pause troppo brevi',
      one: '1 giorno con una pausa troppo breve',
    );
    return '$_temp0';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get quickAddSubmitLabel => 'Aggiungi voce';

  @override
  String get settingsQuickAddTitle => 'Aggiunta rapida';

  @override
  String get settingsQuickAddDescription =>
      'Queste durate compaiono come pulsanti di aggiunta rapida nella scheda Timer.';

  @override
  String get settingsQuickAddAddLabel => 'Aggiungi';

  @override
  String get settingsQuickAddRemoveTooltip => 'Rimuovi';

  @override
  String get settingsQuickAddNewDurationLabel => 'Minuti';

  @override
  String get settingsBreakRuleTitle => 'Regole sulla pausa';

  @override
  String get settingsBreakRuleDescription =>
      'Definisce quanta pausa è necessaria in base al tempo lavorato. Il riepilogo giornaliero avvisa se la pausa è stata troppo breve.';

  @override
  String get settingsBreakRulePresetGermany => 'Germania';

  @override
  String get settingsBreakRulePresetAustria => 'Austria';

  @override
  String get settingsBreakRulePresetSwitzerland => 'Svizzera';

  @override
  String get settingsBreakRuleNone => 'Nessuna';

  @override
  String settingsBreakRuleTierLabel(String worked, String breakTime) {
    return 'Dopo $worked → $breakTime di pausa';
  }

  @override
  String get settingsBreakRuleRemoveTooltip => 'Rimuovi';

  @override
  String get settingsBreakRuleAddLabel => 'Aggiungi regola';

  @override
  String get settingsBreakRuleAddTitle => 'Nuova regola di pausa';

  @override
  String get settingsBreakRuleAfterMinutesLabel => 'Dopo minuti lavorati';

  @override
  String get settingsBreakRuleRequiredMinutesLabel =>
      'Minuti di pausa richiesti';

  @override
  String get settingsBreakRuleSaveError => 'Impossibile salvare la modifica.';

  @override
  String get settingsBreakRuleInvalidTierError =>
      'Inserisci valori validi in minuti.';

  @override
  String get settingsBreakRuleIncludePausedTime =>
      'Includi il tempo del pulsante pausa';

  @override
  String get settingsBreakRuleIncludePausedTimeDescription =>
      'Conta il tempo in pausa tramite il pulsante pausa come pausa, oltre agli intervalli tra le voci.';

  @override
  String get settingsProjectsTitle => 'Progetti';

  @override
  String get settingsProjectsDescription =>
      'Crea, modifica e archivia progetti.';

  @override
  String get settingsProjectsAddLabel => 'Aggiungi progetto';

  @override
  String get settingsProjectsArchivedSection => 'Progetti archiviati';

  @override
  String get settingsProjectsSaveError => 'Impossibile salvare la modifica.';

  @override
  String get projectsNewProjectTitle => 'Nuovo progetto';

  @override
  String get projectsNameLabel => 'Nome';

  @override
  String get projectsCreateButton => 'Crea';

  @override
  String get projectsEditTitle => 'Modifica progetto';

  @override
  String get projectsBillableLabel => 'Fatturabile';

  @override
  String get projectsHourlyRateLabel => 'Tariffa oraria';

  @override
  String get projectsCurrencyLabel => 'Valuta';

  @override
  String get projectsArchiveTooltip => 'Archivia';

  @override
  String get projectsUnarchiveTooltip => 'Riattiva';

  @override
  String get projectsEditTooltip => 'Modifica';

  @override
  String get projectsDeleteTooltip => 'Elimina';

  @override
  String get projectsDeleteConfirmTitle => 'Eliminare il progetto?';

  @override
  String get projectsDeleteConfirmMessage =>
      'Questo progetto verrà eliminato definitivamente. Questa azione non può essere annullata.';

  @override
  String get projectsDeleteHasEntriesError =>
      'Questo progetto ha ancora voci di tempo assegnate e non può essere eliminato.';

  @override
  String get projectsInvalidRateError => 'Inserisci un importo valido.';

  @override
  String get settingsClientsTitle => 'Clienti';

  @override
  String get settingsClientsDescription => 'Crea, modifica e archivia clienti.';

  @override
  String get settingsClientsAddLabel => 'Aggiungi cliente';

  @override
  String get settingsClientsArchivedSection => 'Clienti archiviati';

  @override
  String get settingsClientsSaveError => 'Impossibile salvare la modifica.';

  @override
  String get clientsNewClientTitle => 'Nuovo cliente';

  @override
  String get clientsNameLabel => 'Nome';

  @override
  String get clientsCreateButton => 'Crea';

  @override
  String get clientsEditTitle => 'Modifica cliente';

  @override
  String get clientsEditTooltip => 'Modifica';

  @override
  String get clientsArchiveTooltip => 'Archivia';

  @override
  String get clientsUnarchiveTooltip => 'Riattiva';

  @override
  String get clientsDeleteTooltip => 'Elimina';

  @override
  String get clientsDeleteConfirmTitle => 'Eliminare il cliente?';

  @override
  String get clientsDeleteConfirmMessage =>
      'Questo cliente verrà eliminato definitivamente. Questa azione non può essere annullata.';

  @override
  String get clientsDeleteHasProjectsError =>
      'Questo cliente ha ancora progetti assegnati e non può essere eliminato.';

  @override
  String get projectsClientLabel => 'Cliente';

  @override
  String get projectsClientNone => 'Nessun cliente';

  @override
  String get projectsClientCreateNew => '+ Nuovo cliente…';

  @override
  String projectsClientArchivedLabel(String name) {
    return '$name (archiviato)';
  }

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
  String get reportsToday => 'Oggi';

  @override
  String get reportsYesterday => 'Ieri';

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
  String get reportsEmptyFiltered =>
      'Nessuna voce per questo periodo e questi filtri.';

  @override
  String get reportsFilterTooltip => 'Filtro';

  @override
  String get reportsFilterDialogTitle => 'Filtro';

  @override
  String get reportsFilterProjectsLabel => 'Progetti';

  @override
  String get reportsFilterProjectsHint =>
      'Nessuna selezione equivale a tutti i progetti.';

  @override
  String get reportsFilterBillableLabel => 'Fatturabile';

  @override
  String get reportsFilterBillableAll => 'Tutti';

  @override
  String get reportsFilterBillableOnly => 'Solo fatturabile';

  @override
  String get reportsFilterBillableNonOnly => 'Solo non fatturabile';

  @override
  String get reportsFilterReset => 'Reimposta filtri';

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

  @override
  String get entriesPersonioStatusSynced => 'Registrato su Personio';

  @override
  String get entriesPersonioStatusPending =>
      'Registrazione Personio in sospeso';

  @override
  String get entriesPersonioStatusError =>
      'Registrazione Personio non riuscita';

  @override
  String get syncFailedEntriesTitle => 'Voci non riuscite';

  @override
  String get settingsResetTitle => 'Ripristina';

  @override
  String get settingsResetDescription =>
      'Elimina tutti i dati locali di questo dispositivo (progetti, clienti, voci di tempo, impostazioni, collegamenti Jira/Personio), rimuove definitivamente la cronologia di questo dispositivo dalla cartella di sincronizzazione e lo disconnette. Gli altri dispositivi non vengono interessati, ma non potranno più vedere la cronologia rimossa.';

  @override
  String get settingsResetButton => 'Ripristina tutto';

  @override
  String get settingsResetConfirmTitle => 'Ripristinare davvero tutto?';

  @override
  String get settingsResetConfirmMessage =>
      'Progetti, clienti, voci di tempo, impostazioni e collegamenti Jira/Personio su questo dispositivo verranno eliminati definitivamente. Anche la cronologia di questo dispositivo verrà rimossa definitivamente dalla cartella di sincronizzazione, e la connessione ad essa verrà rimossa. Questa azione non può essere annullata.';

  @override
  String get settingsResetConfirmButton => 'Sì, ripristina tutto';

  @override
  String get settingsResetSuccess => 'L\'app è stata ripristinata.';

  @override
  String get settingsResetError => 'Ripristino non riuscito.';
}
