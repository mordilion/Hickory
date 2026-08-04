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
  String get settingsAutostart => 'Launch at system startup';

  @override
  String get settingsDateFormat => 'Date format';

  @override
  String get settingsTimeFormat => 'Time format';

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
  String get projectsNewProjectTitle => 'New project';

  @override
  String get projectsNameLabel => 'Name';

  @override
  String get projectsCreateButton => 'Create';

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
}
