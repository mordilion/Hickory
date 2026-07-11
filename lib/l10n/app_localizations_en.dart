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
}
