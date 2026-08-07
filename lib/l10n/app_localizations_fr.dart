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
  String get settingsUpdateTitle => 'Mises à jour';

  @override
  String settingsUpdateCurrentVersion(Object version) {
    return 'Version actuelle : $version';
  }

  @override
  String get settingsUpdateCheckButton => 'Rechercher des mises à jour';

  @override
  String get settingsUpdateChecking => 'Recherche de mises à jour...';

  @override
  String get settingsUpdateUpToDate => 'Vous avez la dernière version.';

  @override
  String get settingsUpdateCheckError =>
      'La vérification des mises à jour a échoué. Veuillez réessayer plus tard.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'La version $version est disponible.';
  }

  @override
  String get settingsUpdateInstallButton => 'Installer maintenant';

  @override
  String get settingsUpdateInstalling => 'Installation de la mise à jour...';

  @override
  String get settingsUpdateInstallError =>
      'L\'installation a échoué. Veuillez réessayer ou télécharger la nouvelle version manuellement depuis GitHub.';

  @override
  String get settingsUpdateInstallErrorPermission =>
      'Hickory n\'a pas d\'accès en écriture à son dossier d\'installation. Déplacez l\'application vers un emplacement accessible en écriture, ou mettez-la à jour manuellement depuis GitHub.';

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
  String get syncJiraInvalidCredentials =>
      'Veuillez saisir une URL Jira, un e-mail et un jeton API valides.';

  @override
  String get syncJiraUnexpectedError =>
      'Une erreur s\'est produite. Veuillez réessayer.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created créées, $updated mises à jour, $deleted supprimées, $failed échouées.';
  }

  @override
  String get syncPersonioSectionTitle => 'Intégration Personio';

  @override
  String get syncPersonioClientIdLabel => 'Client ID';

  @override
  String get syncPersonioClientSecretLabel => 'Client Secret';

  @override
  String get syncPersonioEmployeeIdLabel => 'ID employé';

  @override
  String get syncPersonioSaveCredentialsButton =>
      'Enregistrer les identifiants';

  @override
  String get syncPersonioCredentialsSaved => 'Identifiants enregistrés.';

  @override
  String get syncPersonioTestConnectionButton => 'Tester la connexion';

  @override
  String get syncPersonioTestConnectionSuccess => 'Connexion réussie.';

  @override
  String get syncPersonioTestConnectionFailure =>
      'Échec de la connexion. Veuillez vérifier vos identifiants.';

  @override
  String get syncPersonioNotConfigured =>
      'Personio n\'est pas encore configuré.';

  @override
  String get syncPersonioInvalidCredentials =>
      'Veuillez saisir le Client ID, le Client Secret et l\'ID employé.';

  @override
  String get syncPersonioUnexpectedError =>
      'Une erreur s\'est produite. Veuillez réessayer.';

  @override
  String get syncPersonioFromLabel => 'Du';

  @override
  String get syncPersonioToLabel => 'Au';

  @override
  String get syncPersonioPushButton => 'Envoyer vers Personio';

  @override
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  ) {
    return '$created créé(s), $updated mis à jour, $deleted supprimé(s), $failed échoué(s).';
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
  String get timerModeManual => 'Manuel';

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
  String get commonDelete => 'Supprimer';

  @override
  String get commonClose => 'Fermer';

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
  String get entriesDeleteConfirmTitle => 'Supprimer l\'entrée ?';

  @override
  String get entriesDeleteConfirmMessage =>
      'Cette entrée sera définitivement supprimée. Cette action est irréversible.';

  @override
  String entriesBreakLabel(String duration) {
    return 'Pause : $duration';
  }

  @override
  String get entriesBreakInsufficientTooltip => 'Pause trop courte';

  @override
  String get entriesToday => 'Aujourd\'hui';

  @override
  String get entriesYesterday => 'Hier';

  @override
  String entriesDayHeader(String day, String total) {
    return '$day · $total';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get quickAddMoreTooltip => 'Plus d\'options';

  @override
  String get quickAddSubmitTooltip => 'Ajouter une entrée';

  @override
  String get settingsQuickAddTitle => 'Ajout rapide';

  @override
  String get settingsQuickAddDescription =>
      'Ces durées apparaissent comme boutons d\'ajout rapide dans l\'onglet Minuteur.';

  @override
  String get settingsQuickAddAddLabel => 'Ajouter';

  @override
  String get settingsQuickAddRemoveTooltip => 'Supprimer';

  @override
  String get settingsQuickAddNewDurationLabel => 'Minutes';

  @override
  String get settingsBreakRuleTitle => 'Règles de pause';

  @override
  String get settingsBreakRuleDescription =>
      'Définit la pause requise en fonction du temps travaillé. Le résumé du jour avertit si la pause était trop courte.';

  @override
  String get settingsBreakRulePresetGermany => 'Allemagne';

  @override
  String get settingsBreakRulePresetAustria => 'Autriche';

  @override
  String get settingsBreakRulePresetSwitzerland => 'Suisse';

  @override
  String get settingsBreakRuleNone => 'Aucune';

  @override
  String settingsBreakRuleTierLabel(String worked, String breakTime) {
    return 'Après $worked → $breakTime de pause';
  }

  @override
  String get settingsBreakRuleRemoveTooltip => 'Supprimer';

  @override
  String get settingsBreakRuleAddLabel => 'Ajouter une règle';

  @override
  String get settingsBreakRuleAddTitle => 'Nouvelle règle de pause';

  @override
  String get settingsBreakRuleAfterMinutesLabel => 'Après minutes travaillées';

  @override
  String get settingsBreakRuleRequiredMinutesLabel =>
      'Minutes de pause requises';

  @override
  String get settingsBreakRuleSaveError =>
      'Impossible d\'enregistrer la modification.';

  @override
  String get settingsBreakRuleInvalidTierError =>
      'Veuillez saisir des valeurs de minutes valides.';

  @override
  String get settingsBreakRuleIncludePausedTime =>
      'Inclure le temps du bouton pause';

  @override
  String get settingsBreakRuleIncludePausedTimeDescription =>
      'Compte le temps mis en pause via le bouton pause comme pause, en plus des écarts entre les entrées.';

  @override
  String get settingsProjectsTitle => 'Projets';

  @override
  String get settingsProjectsDescription =>
      'Créer, modifier et archiver des projets.';

  @override
  String get settingsProjectsAddLabel => 'Ajouter un projet';

  @override
  String get settingsProjectsArchivedSection => 'Projets archivés';

  @override
  String get settingsProjectsSaveError =>
      'Impossible d\'enregistrer la modification.';

  @override
  String get projectsNewProjectTitle => 'Nouveau projet';

  @override
  String get projectsNameLabel => 'Nom';

  @override
  String get projectsCreateButton => 'Créer';

  @override
  String get projectsEditTitle => 'Modifier le projet';

  @override
  String get projectsBillableLabel => 'Facturable';

  @override
  String get projectsHourlyRateLabel => 'Taux horaire';

  @override
  String get projectsCurrencyLabel => 'Devise';

  @override
  String get projectsArchiveTooltip => 'Archiver';

  @override
  String get projectsUnarchiveTooltip => 'Réactiver';

  @override
  String get projectsEditTooltip => 'Modifier';

  @override
  String get projectsDeleteTooltip => 'Supprimer';

  @override
  String get projectsDeleteConfirmTitle => 'Supprimer le projet ?';

  @override
  String get projectsDeleteConfirmMessage =>
      'Ce projet sera définitivement supprimé. Cette action est irréversible.';

  @override
  String get projectsDeleteHasEntriesError =>
      'Ce projet a encore des saisies de temps associées et ne peut pas être supprimé.';

  @override
  String get projectsInvalidRateError => 'Veuillez saisir un montant valide.';

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
  String get reportsToday => 'Aujourd\'hui';

  @override
  String get reportsYesterday => 'Hier';

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
  String get reportsEmptyFiltered =>
      'Aucune entrée pour cette période et ces filtres.';

  @override
  String get reportsFilterTooltip => 'Filtre';

  @override
  String get reportsFilterDialogTitle => 'Filtre';

  @override
  String get reportsFilterProjectsLabel => 'Projets';

  @override
  String get reportsFilterProjectsHint =>
      'Aucune sélection équivaut à tous les projets.';

  @override
  String get reportsFilterBillableLabel => 'Facturable';

  @override
  String get reportsFilterBillableAll => 'Tout';

  @override
  String get reportsFilterBillableOnly => 'Facturable uniquement';

  @override
  String get reportsFilterBillableNonOnly => 'Non facturable uniquement';

  @override
  String get reportsFilterReset => 'Réinitialiser les filtres';

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

  @override
  String get settingsResetTitle => 'Réinitialiser';

  @override
  String get settingsResetDescription =>
      'Supprime toutes les données locales de cet appareil (projets, clients, saisies de temps, paramètres, liens Jira/Personio), retire définitivement l\'historique propre à cet appareil du dossier de synchronisation, puis le déconnecte. Les autres appareils ne sont pas concernés, mais ne pourront plus non plus voir l\'historique retiré.';

  @override
  String get settingsResetButton => 'Tout réinitialiser';

  @override
  String get settingsResetConfirmTitle => 'Vraiment tout réinitialiser ?';

  @override
  String get settingsResetConfirmMessage =>
      'Les projets, clients, saisies de temps, paramètres et liens Jira/Personio de cet appareil seront définitivement supprimés. L\'historique propre à cet appareil sera également retiré définitivement du dossier de synchronisation, et la connexion à ce dossier sera supprimée. Cette action est irréversible.';

  @override
  String get settingsResetConfirmButton => 'Oui, tout réinitialiser';

  @override
  String get settingsResetSuccess => 'L\'application a été réinitialisée.';

  @override
  String get settingsResetError => 'La réinitialisation a échoué.';
}
