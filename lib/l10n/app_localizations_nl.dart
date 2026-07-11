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
}
