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

  @override
  String get syncJiraSectionTitle => 'Intégration Jira';

  @override
  String get syncJiraBaseUrlLabel => 'URL Jira';

  @override
  String get syncJiraEmailLabel => 'E-mail';

  @override
  String get syncJiraApiTokenLabel => 'Jeton API';

  @override
  String get syncJiraSaveCredentialsButton => 'Enregistrer les identifiants';

  @override
  String get syncJiraCredentialsSaved => 'Identifiants enregistrés.';

  @override
  String get syncJiraTestConnectionButton => 'Tester la connexion';

  @override
  String get syncJiraTestConnectionSuccess => 'Connexion réussie.';

  @override
  String get syncJiraTestConnectionFailure =>
      'Échec de la connexion. Vérifiez vos identifiants.';

  @override
  String get syncJiraSyncButton => 'Synchroniser avec Jira maintenant';

  @override
  String get syncJiraNotConfigured => 'Jira n\'est pas encore configuré.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created créées, $updated mises à jour, $deleted supprimées, $failed échouées.';
  }

  @override
  String get navTimer => 'Minuteur';

  @override
  String get navReports => 'Rapports';

  @override
  String get navSync => 'Synchronisation';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get commonNoProject => 'Aucun projet';

  @override
  String timerError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get timerResume => 'Reprendre';

  @override
  String get timerPause => 'Pause';

  @override
  String get timerStop => 'Arrêter';

  @override
  String get timerDescriptionLabel => 'Sur quoi travaillez-vous ?';

  @override
  String get timerProjectLabel => 'Projet';

  @override
  String get timerNewProjectTooltip => 'Nouveau projet';

  @override
  String get jiraTicketFieldLabel => 'Ticket Jira';

  @override
  String get timerStart => 'Démarrer';

  @override
  String get timerIdleTitle => 'Inactivité détectée';

  @override
  String timerIdleMessage(int minutes) {
    return 'Vous êtes inactif(ve) depuis $minutes minutes. Voulez-vous déduire ce temps de l\'entrée en cours ?';
  }

  @override
  String get timerIdleKeepTime => 'Conserver le temps';

  @override
  String get timerIdleTrimTime => 'Déduire le temps inactif';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get entriesEmpty => 'Aucune entrée pour l\'instant.';

  @override
  String get entriesNoDescription => 'Sans description';

  @override
  String entriesError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get entriesManualEntryTitle => 'Entrée manuelle';

  @override
  String get entriesEditEntryTitle => 'Modifier l\'entrée';

  @override
  String get entriesDescriptionLabel => 'Description';

  @override
  String get entriesProjectLabel => 'Projet';

  @override
  String get entriesStartLabel => 'Début';

  @override
  String get entriesEndLabel => 'Fin';

  @override
  String get entriesEndBeforeStartError =>
      'La fin doit être postérieure au début.';

  @override
  String get projectsNewProjectTitle => 'Nouveau projet';

  @override
  String get projectsNameLabel => 'Nom';

  @override
  String get projectsCreateButton => 'Créer';

  @override
  String get reportsTitle => 'Rapports';

  @override
  String get reportsThisWeek => 'Cette semaine';

  @override
  String get reportsThisMonth => 'Ce mois-ci';

  @override
  String get reportsLast30Days => '30 derniers jours';

  @override
  String get reportsAll => 'Tout';

  @override
  String get reportsCustomRange => 'Personnalisé…';

  @override
  String reportsError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get reportsExportCsv => 'Exporter en CSV';

  @override
  String reportsExportedTo(String path) {
    return 'Exporté vers : $path';
  }

  @override
  String reportsTotal(String duration) {
    return 'Total : $duration';
  }

  @override
  String get reportsEmptyRange => 'Aucune entrée sur cette période.';

  @override
  String get csvHeaderDate => 'Date';

  @override
  String get csvHeaderStart => 'Début';

  @override
  String get csvHeaderEnd => 'Fin';

  @override
  String get csvHeaderDurationHours => 'Durée (h)';

  @override
  String get csvHeaderProject => 'Projet';

  @override
  String get csvHeaderDescription => 'Description';

  @override
  String get csvHeaderBillable => 'Facturable';

  @override
  String get csvHeaderAmount => 'Montant';

  @override
  String get csvHeaderCurrency => 'Devise';

  @override
  String get csvYes => 'oui';

  @override
  String get csvNo => 'non';

  @override
  String get entriesJiraStatusSynced => 'Enregistré dans Jira';

  @override
  String get entriesJiraStatusPending => 'Enregistrement Jira en attente';

  @override
  String get entriesJiraStatusError => 'Échec de l\'enregistrement Jira';
}
