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
  String get timerStart => 'Start';

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
  String get projectsNewProjectTitle => 'New project';

  @override
  String get projectsNameLabel => 'Name';

  @override
  String get projectsCreateButton => 'Create';
}
