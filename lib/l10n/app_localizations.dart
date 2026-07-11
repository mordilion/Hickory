import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_nl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('nl'),
  ];

  /// No description provided for @trayOpen.
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get trayOpen;

  /// No description provided for @trayQuit.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get trayQuit;

  /// No description provided for @trayBackgroundNotice.
  ///
  /// In de, this message translates to:
  /// **'Hickory läuft im Hintergrund weiter.'**
  String get trayBackgroundNotice;

  /// No description provided for @settingsLanguage.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In de, this message translates to:
  /// **'Systemstandard ({language})'**
  String settingsLanguageSystem(String language);

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @settingsAutostart.
  ///
  /// In de, this message translates to:
  /// **'Beim Systemstart öffnen'**
  String get settingsAutostart;

  /// No description provided for @settingsDateFormat.
  ///
  /// In de, this message translates to:
  /// **'Datumsformat'**
  String get settingsDateFormat;

  /// No description provided for @settingsTimeFormat.
  ///
  /// In de, this message translates to:
  /// **'Zeitformat'**
  String get settingsTimeFormat;

  /// No description provided for @syncTitle.
  ///
  /// In de, this message translates to:
  /// **'Sync-Einstellungen'**
  String get syncTitle;

  /// No description provided for @syncNoFolderSelected.
  ///
  /// In de, this message translates to:
  /// **'Kein Ordner gewählt – Daten bleiben nur lokal auf diesem Gerät.'**
  String get syncNoFolderSelected;

  /// No description provided for @syncFolderPath.
  ///
  /// In de, this message translates to:
  /// **'Sync-Ordner: {path}'**
  String syncFolderPath(String path);

  /// No description provided for @syncError.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {error}'**
  String syncError(String error);

  /// No description provided for @syncFolderDescription.
  ///
  /// In de, this message translates to:
  /// **'Wähle einen Ordner, der bereits von iCloud Drive, Google Drive, Dropbox o.ä. synchronisiert wird. Hickory schreibt dort nur eigene Dateien und synchronisiert sich selbst nicht mit der Cloud.'**
  String get syncFolderDescription;

  /// No description provided for @syncNowButton.
  ///
  /// In de, this message translates to:
  /// **'Jetzt synchronisieren'**
  String get syncNowButton;

  /// No description provided for @syncChooseFolderButton.
  ///
  /// In de, this message translates to:
  /// **'Ordner wählen'**
  String get syncChooseFolderButton;

  /// No description provided for @syncFolderChosen.
  ///
  /// In de, this message translates to:
  /// **'Ordner gewählt: {path}'**
  String syncFolderChosen(String path);

  /// No description provided for @syncCompleted.
  ///
  /// In de, this message translates to:
  /// **'Synchronisierung abgeschlossen.'**
  String get syncCompleted;

  /// No description provided for @navTimer.
  ///
  /// In de, this message translates to:
  /// **'Timer'**
  String get navTimer;

  /// No description provided for @navReports.
  ///
  /// In de, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navSync.
  ///
  /// In de, this message translates to:
  /// **'Sync'**
  String get navSync;

  /// No description provided for @navSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get navSettings;

  /// No description provided for @commonNoProject.
  ///
  /// In de, this message translates to:
  /// **'Kein Projekt'**
  String get commonNoProject;

  /// No description provided for @timerError.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {error}'**
  String timerError(String error);

  /// No description provided for @timerResume.
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get timerResume;

  /// No description provided for @timerPause.
  ///
  /// In de, this message translates to:
  /// **'Pause'**
  String get timerPause;

  /// No description provided for @timerStop.
  ///
  /// In de, this message translates to:
  /// **'Stop'**
  String get timerStop;

  /// No description provided for @timerDescriptionLabel.
  ///
  /// In de, this message translates to:
  /// **'Was arbeitest du gerade?'**
  String get timerDescriptionLabel;

  /// No description provided for @timerProjectLabel.
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get timerProjectLabel;

  /// No description provided for @timerNewProjectTooltip.
  ///
  /// In de, this message translates to:
  /// **'Neues Projekt'**
  String get timerNewProjectTooltip;

  /// No description provided for @timerStart.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get timerStart;

  /// No description provided for @timerIdleTitle.
  ///
  /// In de, this message translates to:
  /// **'Inaktiv erkannt'**
  String get timerIdleTitle;

  /// No description provided for @timerIdleMessage.
  ///
  /// In de, this message translates to:
  /// **'Du warst seit {minutes} Minuten inaktiv. Soll diese Zeit vom laufenden Eintrag abgezogen werden?'**
  String timerIdleMessage(int minutes);

  /// No description provided for @timerIdleKeepTime.
  ///
  /// In de, this message translates to:
  /// **'Zeit behalten'**
  String get timerIdleKeepTime;

  /// No description provided for @timerIdleTrimTime.
  ///
  /// In de, this message translates to:
  /// **'Inaktive Zeit abziehen'**
  String get timerIdleTrimTime;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'nl',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
