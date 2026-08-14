// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get trayOpen => 'Open';

  @override
  String get trayQuit => 'Quit';

  @override
  String get trayBackgroundNotice => 'Hickory keeps running in the background.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String settingsLanguageSystem(String language) {
    return 'System default ($language)';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsCategoryGeneral => 'General';

  @override
  String get settingsCategoryTimeTracking => 'Time tracking';

  @override
  String get settingsAutostart => 'Launch at system startup';

  @override
  String get settingsDateFormat => 'Date format';

  @override
  String get settingsTimeFormat => 'Time format';

  @override
  String get settingsUpdateTitle => 'Updates';

  @override
  String settingsUpdateCurrentVersion(Object version) {
    return 'Current version: $version';
  }

  @override
  String get settingsUpdateCheckButton => 'Check for updates';

  @override
  String get settingsUpdateChecking => 'Checking for updates...';

  @override
  String get settingsUpdateUpToDate => 'You\'re on the latest version.';

  @override
  String get settingsUpdateCheckError =>
      'Update check failed. Please try again later.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'Version $version is available.';
  }

  @override
  String get settingsUpdateInstallButton => 'Install now';

  @override
  String get settingsUpdateInstalling => 'Installing update...';

  @override
  String get settingsUpdateInstallError =>
      'Installation failed. Please try again or download the new version manually from GitHub.';

  @override
  String get settingsUpdateInstallErrorPermission =>
      'Hickory doesn\'t have write access to its installation folder. Move it somewhere you can write to, or update manually from GitHub.';

  @override
  String get syncTitle => 'Sync settings';

  @override
  String get syncNoFolderSelected =>
      'No folder selected – data stays only on this device.';

  @override
  String syncFolderPath(String path) {
    return 'Sync folder: $path';
  }

  @override
  String syncError(String error) {
    return 'Error: $error';
  }

  @override
  String get syncFolderDescription =>
      'Choose a folder that\'s already synced by iCloud Drive, Google Drive, Dropbox, or similar. Hickory only writes its own files there and doesn\'t sync itself with the cloud.';

  @override
  String get syncNowButton => 'Sync now';

  @override
  String get syncChooseFolderButton => 'Choose folder';

  @override
  String syncFolderChosen(String path) {
    return 'Folder selected: $path';
  }

  @override
  String get syncCompleted => 'Sync completed.';

  @override
  String get syncJiraSectionTitle => 'Jira Integration';

  @override
  String get syncJiraBaseUrlLabel => 'Jira URL';

  @override
  String get syncJiraEmailLabel => 'Email';

  @override
  String get syncJiraApiTokenLabel => 'API token';

  @override
  String get syncJiraSaveCredentialsButton => 'Save credentials';

  @override
  String get syncJiraCredentialsSaved => 'Credentials saved.';

  @override
  String get syncJiraTestConnectionButton => 'Test connection';

  @override
  String get syncJiraTestConnectionSuccess => 'Connection successful.';

  @override
  String get syncJiraTestConnectionFailure =>
      'Connection failed. Please check your credentials.';

  @override
  String get syncJiraSyncButton => 'Sync to Jira now';

  @override
  String get syncJiraNotConfigured => 'Jira isn\'t configured yet.';

  @override
  String get syncJiraInvalidCredentials =>
      'Please enter a valid Jira URL, email, and API token.';

  @override
  String get syncJiraUnexpectedError =>
      'Something went wrong. Please try again.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created created, $updated updated, $deleted deleted, $failed failed.';
  }

  @override
  String get syncPersonioSectionTitle => 'Personio Integration';

  @override
  String get syncPersonioClientIdLabel => 'Client ID';

  @override
  String get syncPersonioClientSecretLabel => 'Client Secret';

  @override
  String get syncPersonioEmployeeIdLabel => 'Employee ID';

  @override
  String get syncPersonioSaveCredentialsButton => 'Save credentials';

  @override
  String get syncPersonioCredentialsSaved => 'Credentials saved.';

  @override
  String get syncPersonioTestConnectionButton => 'Test connection';

  @override
  String get syncPersonioTestConnectionSuccess => 'Connection successful.';

  @override
  String get syncPersonioTestConnectionFailure =>
      'Connection failed. Please check your credentials.';

  @override
  String get syncPersonioNotConfigured => 'Personio isn\'t configured yet.';

  @override
  String get syncPersonioInvalidCredentials =>
      'Please enter a Client ID, Client Secret, and Employee ID.';

  @override
  String get syncPersonioUnexpectedError =>
      'Something went wrong. Please try again.';

  @override
  String get syncPersonioFromLabel => 'From';

  @override
  String get syncPersonioToLabel => 'To';

  @override
  String get syncPersonioPushButton => 'Push to Personio';

  @override
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  ) {
    return '$created created, $updated updated, $deleted deleted, $failed failed.';
  }

  @override
  String get navTimer => 'Timer';

  @override
  String get navReports => 'Reports';

  @override
  String get navSync => 'Sync';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonNoProject => 'No project';

  @override
  String timerError(String error) {
    return 'Error: $error';
  }

  @override
  String get timerResume => 'Resume';

  @override
  String get timerPause => 'Pause';

  @override
  String get timerStop => 'Stop';

  @override
  String get timerDescriptionLabel => 'What are you working on?';

  @override
  String get timerProjectLabel => 'Project';

  @override
  String get timerNewProjectTooltip => 'New project';

  @override
  String get jiraTicketFieldLabel => 'Jira ticket';

  @override
  String get timerStart => 'Start';

  @override
  String get timerModeManual => 'Manual';

  @override
  String get timerIdleTitle => 'Idle detected';

  @override
  String timerIdleMessage(int minutes) {
    return 'You\'ve been idle for $minutes minutes. Should this time be deducted from the running entry?';
  }

  @override
  String get timerIdleKeepTime => 'Keep time';

  @override
  String get timerIdleTrimTime => 'Deduct idle time';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonClose => 'Close';

  @override
  String get entriesEmpty => 'No entries yet.';

  @override
  String get entriesNoDescription => 'No description';

  @override
  String entriesError(String error) {
    return 'Error: $error';
  }

  @override
  String get entriesManualEntryTitle => 'Manual entry';

  @override
  String get entriesEditEntryTitle => 'Edit entry';

  @override
  String get entriesDescriptionLabel => 'Description';

  @override
  String get entriesProjectLabel => 'Project';

  @override
  String get entriesStartLabel => 'Start';

  @override
  String get entriesEndLabel => 'End';

  @override
  String get entriesEndBeforeStartError => 'End must be after the start.';

  @override
  String get entriesDeleteConfirmTitle => 'Delete entry?';

  @override
  String get entriesDeleteConfirmMessage =>
      'This entry will be permanently deleted. This cannot be undone.';

  @override
  String entriesBreakLabel(String duration) {
    return 'Break: $duration';
  }

  @override
  String get entriesBreakInsufficientTooltip => 'Break too short';

  @override
  String get entriesToday => 'Today';

  @override
  String get entriesYesterday => 'Yesterday';

  @override
  String entriesDayHeader(String day, String total) {
    return '$day · $total';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get quickAddMoreTooltip => 'More options';

  @override
  String get quickAddSubmitTooltip => 'Add entry';

  @override
  String get settingsQuickAddTitle => 'Quick Add';

  @override
  String get settingsQuickAddDescription =>
      'These durations appear as quick-add buttons on the Timer tab.';

  @override
  String get settingsQuickAddAddLabel => 'Add';

  @override
  String get settingsQuickAddRemoveTooltip => 'Remove';

  @override
  String get settingsQuickAddNewDurationLabel => 'Minutes';

  @override
  String get settingsBreakRuleTitle => 'Break rules';

  @override
  String get settingsBreakRuleDescription =>
      'Sets how much break time is required after how much work. The day overview warns when the break was too short.';

  @override
  String get settingsBreakRulePresetGermany => 'Germany';

  @override
  String get settingsBreakRulePresetAustria => 'Austria';

  @override
  String get settingsBreakRulePresetSwitzerland => 'Switzerland';

  @override
  String get settingsBreakRuleNone => 'None';

  @override
  String settingsBreakRuleTierLabel(String worked, String breakTime) {
    return 'After $worked → $breakTime break';
  }

  @override
  String get settingsBreakRuleRemoveTooltip => 'Remove';

  @override
  String get settingsBreakRuleAddLabel => 'Add rule';

  @override
  String get settingsBreakRuleAddTitle => 'New break rule';

  @override
  String get settingsBreakRuleAfterMinutesLabel => 'After minutes worked';

  @override
  String get settingsBreakRuleRequiredMinutesLabel => 'Minutes break required';

  @override
  String get settingsBreakRuleSaveError => 'Could not save the change.';

  @override
  String get settingsBreakRuleInvalidTierError =>
      'Please enter valid minute values.';

  @override
  String get settingsBreakRuleIncludePausedTime => 'Include pause-button time';

  @override
  String get settingsBreakRuleIncludePausedTimeDescription =>
      'Counts time paused via the Timer\'s pause button toward break time, in addition to gaps between entries.';

  @override
  String get settingsProjectsTitle => 'Projects';

  @override
  String get settingsProjectsDescription =>
      'Create, edit, and archive projects.';

  @override
  String get settingsProjectsAddLabel => 'Add project';

  @override
  String get settingsProjectsArchivedSection => 'Archived projects';

  @override
  String get settingsProjectsSaveError => 'Could not save the change.';

  @override
  String get projectsNewProjectTitle => 'New project';

  @override
  String get projectsNameLabel => 'Name';

  @override
  String get projectsCreateButton => 'Create';

  @override
  String get projectsEditTitle => 'Edit project';

  @override
  String get projectsBillableLabel => 'Billable';

  @override
  String get projectsHourlyRateLabel => 'Hourly rate';

  @override
  String get projectsCurrencyLabel => 'Currency';

  @override
  String get projectsArchiveTooltip => 'Archive';

  @override
  String get projectsUnarchiveTooltip => 'Reactivate';

  @override
  String get projectsEditTooltip => 'Edit';

  @override
  String get projectsDeleteTooltip => 'Delete';

  @override
  String get projectsDeleteConfirmTitle => 'Delete project?';

  @override
  String get projectsDeleteConfirmMessage =>
      'This project will be permanently deleted. This cannot be undone.';

  @override
  String get projectsDeleteHasEntriesError =>
      'This project still has time entries assigned and can\'t be deleted.';

  @override
  String get projectsInvalidRateError => 'Please enter a valid amount.';

  @override
  String get settingsClientsTitle => 'Clients';

  @override
  String get settingsClientsDescription => 'Create, edit, and archive clients.';

  @override
  String get settingsClientsAddLabel => 'Add client';

  @override
  String get settingsClientsArchivedSection => 'Archived clients';

  @override
  String get settingsClientsSaveError => 'Could not save the change.';

  @override
  String get clientsNewClientTitle => 'New client';

  @override
  String get clientsNameLabel => 'Name';

  @override
  String get clientsCreateButton => 'Create';

  @override
  String get clientsEditTitle => 'Edit client';

  @override
  String get clientsEditTooltip => 'Edit';

  @override
  String get clientsArchiveTooltip => 'Archive';

  @override
  String get clientsUnarchiveTooltip => 'Reactivate';

  @override
  String get clientsDeleteTooltip => 'Delete';

  @override
  String get clientsDeleteConfirmTitle => 'Delete client?';

  @override
  String get clientsDeleteConfirmMessage =>
      'This client will be permanently deleted. This cannot be undone.';

  @override
  String get clientsDeleteHasProjectsError =>
      'This client still has projects assigned and can\'t be deleted.';

  @override
  String get projectsClientLabel => 'Client';

  @override
  String get projectsClientNone => 'No client';

  @override
  String get projectsClientCreateNew => '+ New client…';

  @override
  String projectsClientArchivedLabel(String name) {
    return '$name (archived)';
  }

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsThisWeek => 'This week';

  @override
  String get reportsThisMonth => 'This month';

  @override
  String get reportsLast30Days => 'Last 30 days';

  @override
  String get reportsAll => 'All';

  @override
  String get reportsCustomRange => 'Custom…';

  @override
  String get reportsToday => 'Today';

  @override
  String get reportsYesterday => 'Yesterday';

  @override
  String reportsError(String error) {
    return 'Error: $error';
  }

  @override
  String get reportsExportCsv => 'Export CSV';

  @override
  String reportsExportedTo(String path) {
    return 'Exported to: $path';
  }

  @override
  String reportsTotal(String duration) {
    return 'Total: $duration';
  }

  @override
  String get reportsEmptyRange => 'No entries in this period.';

  @override
  String get reportsEmptyFiltered =>
      'No entries for this period and these filters.';

  @override
  String get reportsFilterTooltip => 'Filter';

  @override
  String get reportsFilterDialogTitle => 'Filter';

  @override
  String get reportsFilterProjectsLabel => 'Projects';

  @override
  String get reportsFilterProjectsHint => 'No selection means all projects.';

  @override
  String get reportsFilterBillableLabel => 'Billable';

  @override
  String get reportsFilterBillableAll => 'All';

  @override
  String get reportsFilterBillableOnly => 'Billable only';

  @override
  String get reportsFilterBillableNonOnly => 'Non-billable only';

  @override
  String get reportsFilterReset => 'Reset filters';

  @override
  String get csvHeaderDate => 'Date';

  @override
  String get csvHeaderStart => 'Start';

  @override
  String get csvHeaderEnd => 'End';

  @override
  String get csvHeaderDurationHours => 'Duration (h)';

  @override
  String get csvHeaderProject => 'Project';

  @override
  String get csvHeaderDescription => 'Description';

  @override
  String get csvHeaderBillable => 'Billable';

  @override
  String get csvHeaderAmount => 'Amount';

  @override
  String get csvHeaderCurrency => 'Currency';

  @override
  String get csvYes => 'yes';

  @override
  String get csvNo => 'no';

  @override
  String get entriesJiraStatusSynced => 'Booked in Jira';

  @override
  String get entriesJiraStatusPending => 'Jira booking pending';

  @override
  String get entriesJiraStatusError => 'Jira booking failed';

  @override
  String get settingsResetTitle => 'Reset';

  @override
  String get settingsResetDescription =>
      'Deletes all of this device\'s local data (projects, clients, time entries, settings, Jira/Personio links), permanently removes this device\'s own history from the sync folder, and disconnects it. Other devices are not affected, but can no longer see the removed history either.';

  @override
  String get settingsResetButton => 'Reset everything';

  @override
  String get settingsResetConfirmTitle => 'Really reset everything?';

  @override
  String get settingsResetConfirmMessage =>
      'Projects, clients, time entries, settings, and Jira/Personio links on this device will be permanently deleted. This device\'s own history will also be permanently removed from the sync folder, and the connection to it will be removed. This cannot be undone.';

  @override
  String get settingsResetConfirmButton => 'Yes, reset everything';

  @override
  String get settingsResetSuccess => 'The app has been reset.';

  @override
  String get settingsResetError => 'Reset failed.';
}
