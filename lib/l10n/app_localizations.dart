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

  /// No description provided for @settingsCategoryGeneral.
  ///
  /// In de, this message translates to:
  /// **'Allgemein'**
  String get settingsCategoryGeneral;

  /// No description provided for @settingsCategoryTimeTracking.
  ///
  /// In de, this message translates to:
  /// **'Zeiterfassung'**
  String get settingsCategoryTimeTracking;

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

  /// No description provided for @settingsUpdateTitle.
  ///
  /// In de, this message translates to:
  /// **'Updates'**
  String get settingsUpdateTitle;

  /// No description provided for @settingsUpdateCurrentVersion.
  ///
  /// In de, this message translates to:
  /// **'Aktuelle Version: {version}'**
  String settingsUpdateCurrentVersion(Object version);

  /// No description provided for @settingsUpdateCheckButton.
  ///
  /// In de, this message translates to:
  /// **'Nach Updates suchen'**
  String get settingsUpdateCheckButton;

  /// No description provided for @settingsUpdateChecking.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Updates...'**
  String get settingsUpdateChecking;

  /// No description provided for @settingsUpdateUpToDate.
  ///
  /// In de, this message translates to:
  /// **'Du hast die neueste Version.'**
  String get settingsUpdateUpToDate;

  /// No description provided for @settingsUpdateCheckError.
  ///
  /// In de, this message translates to:
  /// **'Update-Prüfung fehlgeschlagen. Bitte versuche es später erneut.'**
  String get settingsUpdateCheckError;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In de, this message translates to:
  /// **'Version {version} ist verfügbar.'**
  String settingsUpdateAvailable(Object version);

  /// No description provided for @settingsUpdateInstallButton.
  ///
  /// In de, this message translates to:
  /// **'Jetzt installieren'**
  String get settingsUpdateInstallButton;

  /// No description provided for @settingsUpdateInstalling.
  ///
  /// In de, this message translates to:
  /// **'Update wird installiert...'**
  String get settingsUpdateInstalling;

  /// No description provided for @settingsUpdateInstallError.
  ///
  /// In de, this message translates to:
  /// **'Installation fehlgeschlagen. Bitte versuche es erneut oder lade die neue Version manuell von GitHub herunter.'**
  String get settingsUpdateInstallError;

  /// No description provided for @settingsUpdateInstallErrorPermission.
  ///
  /// In de, this message translates to:
  /// **'Hickory hat keinen Schreibzugriff auf den Installationsordner. Verschiebe die App an einen Ort mit Schreibzugriff oder aktualisiere manuell über GitHub.'**
  String get settingsUpdateInstallErrorPermission;

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

  /// No description provided for @syncJiraSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Jira-Integration'**
  String get syncJiraSectionTitle;

  /// No description provided for @syncJiraBaseUrlLabel.
  ///
  /// In de, this message translates to:
  /// **'Jira-URL'**
  String get syncJiraBaseUrlLabel;

  /// No description provided for @syncJiraEmailLabel.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get syncJiraEmailLabel;

  /// No description provided for @syncJiraApiTokenLabel.
  ///
  /// In de, this message translates to:
  /// **'API-Token'**
  String get syncJiraApiTokenLabel;

  /// No description provided for @syncJiraSaveCredentialsButton.
  ///
  /// In de, this message translates to:
  /// **'Zugangsdaten speichern'**
  String get syncJiraSaveCredentialsButton;

  /// No description provided for @syncJiraCredentialsSaved.
  ///
  /// In de, this message translates to:
  /// **'Zugangsdaten gespeichert.'**
  String get syncJiraCredentialsSaved;

  /// No description provided for @syncJiraTestConnectionButton.
  ///
  /// In de, this message translates to:
  /// **'Verbindung testen'**
  String get syncJiraTestConnectionButton;

  /// No description provided for @syncJiraTestConnectionSuccess.
  ///
  /// In de, this message translates to:
  /// **'Verbindung erfolgreich.'**
  String get syncJiraTestConnectionSuccess;

  /// No description provided for @syncJiraTestConnectionFailure.
  ///
  /// In de, this message translates to:
  /// **'Verbindung fehlgeschlagen. Bitte Zugangsdaten prüfen.'**
  String get syncJiraTestConnectionFailure;

  /// No description provided for @syncJiraSyncButton.
  ///
  /// In de, this message translates to:
  /// **'Jetzt zu Jira synchronisieren'**
  String get syncJiraSyncButton;

  /// No description provided for @syncJiraNotConfigured.
  ///
  /// In de, this message translates to:
  /// **'Jira ist noch nicht konfiguriert.'**
  String get syncJiraNotConfigured;

  /// No description provided for @syncJiraInvalidCredentials.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib eine gültige Jira-URL sowie E-Mail und API-Token an.'**
  String get syncJiraInvalidCredentials;

  /// No description provided for @syncJiraUnexpectedError.
  ///
  /// In de, this message translates to:
  /// **'Es ist ein Fehler aufgetreten. Bitte versuche es erneut.'**
  String get syncJiraUnexpectedError;

  /// No description provided for @syncJiraSyncResult.
  ///
  /// In de, this message translates to:
  /// **'{created} erstellt, {updated} aktualisiert, {deleted} gelöscht, {failed} fehlgeschlagen.'**
  String syncJiraSyncResult(int created, int updated, int deleted, int failed);

  /// No description provided for @syncPersonioSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Personio-Integration'**
  String get syncPersonioSectionTitle;

  /// No description provided for @syncPersonioClientIdLabel.
  ///
  /// In de, this message translates to:
  /// **'Client ID'**
  String get syncPersonioClientIdLabel;

  /// No description provided for @syncPersonioClientSecretLabel.
  ///
  /// In de, this message translates to:
  /// **'Client Secret'**
  String get syncPersonioClientSecretLabel;

  /// No description provided for @syncPersonioEmployeeIdLabel.
  ///
  /// In de, this message translates to:
  /// **'Mitarbeiter-ID'**
  String get syncPersonioEmployeeIdLabel;

  /// No description provided for @syncPersonioSaveCredentialsButton.
  ///
  /// In de, this message translates to:
  /// **'Zugangsdaten speichern'**
  String get syncPersonioSaveCredentialsButton;

  /// No description provided for @syncPersonioCredentialsSaved.
  ///
  /// In de, this message translates to:
  /// **'Zugangsdaten gespeichert.'**
  String get syncPersonioCredentialsSaved;

  /// No description provided for @syncPersonioTestConnectionButton.
  ///
  /// In de, this message translates to:
  /// **'Verbindung testen'**
  String get syncPersonioTestConnectionButton;

  /// No description provided for @syncPersonioTestConnectionSuccess.
  ///
  /// In de, this message translates to:
  /// **'Verbindung erfolgreich.'**
  String get syncPersonioTestConnectionSuccess;

  /// No description provided for @syncPersonioTestConnectionFailure.
  ///
  /// In de, this message translates to:
  /// **'Verbindung fehlgeschlagen. Bitte Zugangsdaten prüfen.'**
  String get syncPersonioTestConnectionFailure;

  /// No description provided for @syncPersonioNotConfigured.
  ///
  /// In de, this message translates to:
  /// **'Personio ist noch nicht konfiguriert.'**
  String get syncPersonioNotConfigured;

  /// No description provided for @syncPersonioInvalidCredentials.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib Client ID, Client Secret und Mitarbeiter-ID an.'**
  String get syncPersonioInvalidCredentials;

  /// No description provided for @syncPersonioUnexpectedError.
  ///
  /// In de, this message translates to:
  /// **'Es ist ein Fehler aufgetreten. Bitte versuche es erneut.'**
  String get syncPersonioUnexpectedError;

  /// No description provided for @syncPersonioFromLabel.
  ///
  /// In de, this message translates to:
  /// **'Von'**
  String get syncPersonioFromLabel;

  /// No description provided for @syncPersonioToLabel.
  ///
  /// In de, this message translates to:
  /// **'Bis'**
  String get syncPersonioToLabel;

  /// No description provided for @syncPersonioPushButton.
  ///
  /// In de, this message translates to:
  /// **'Zeiten nach Personio pushen'**
  String get syncPersonioPushButton;

  /// No description provided for @syncPersonioPushResult.
  ///
  /// In de, this message translates to:
  /// **'{created} erstellt, {updated} aktualisiert, {deleted} gelöscht, {failed} fehlgeschlagen.'**
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  );

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

  /// No description provided for @jiraTicketFieldLabel.
  ///
  /// In de, this message translates to:
  /// **'Jira-Ticket'**
  String get jiraTicketFieldLabel;

  /// No description provided for @timerStart.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get timerStart;

  /// No description provided for @timerModeManual.
  ///
  /// In de, this message translates to:
  /// **'Manuell'**
  String get timerModeManual;

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

  /// No description provided for @commonCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get commonDelete;

  /// No description provided for @commonClose.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get commonClose;

  /// No description provided for @entriesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge.'**
  String get entriesEmpty;

  /// No description provided for @entriesNoDescription.
  ///
  /// In de, this message translates to:
  /// **'Ohne Beschreibung'**
  String get entriesNoDescription;

  /// No description provided for @entriesError.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {error}'**
  String entriesError(String error);

  /// No description provided for @entriesManualEntryTitle.
  ///
  /// In de, this message translates to:
  /// **'Manueller Eintrag'**
  String get entriesManualEntryTitle;

  /// No description provided for @entriesEditEntryTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag bearbeiten'**
  String get entriesEditEntryTitle;

  /// No description provided for @entriesDescriptionLabel.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get entriesDescriptionLabel;

  /// No description provided for @entriesProjectLabel.
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get entriesProjectLabel;

  /// No description provided for @entriesStartLabel.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get entriesStartLabel;

  /// No description provided for @entriesEndLabel.
  ///
  /// In de, this message translates to:
  /// **'Ende'**
  String get entriesEndLabel;

  /// No description provided for @entriesEndBeforeStartError.
  ///
  /// In de, this message translates to:
  /// **'Ende muss nach dem Start liegen.'**
  String get entriesEndBeforeStartError;

  /// No description provided for @entriesDeleteConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag löschen?'**
  String get entriesDeleteConfirmTitle;

  /// No description provided for @entriesDeleteConfirmMessage.
  ///
  /// In de, this message translates to:
  /// **'Dieser Eintrag wird endgültig gelöscht. Das kann nicht rückgängig gemacht werden.'**
  String get entriesDeleteConfirmMessage;

  /// No description provided for @entriesBreakLabel.
  ///
  /// In de, this message translates to:
  /// **'Pause: {duration}'**
  String entriesBreakLabel(String duration);

  /// No description provided for @entriesBreakInsufficientTooltip.
  ///
  /// In de, this message translates to:
  /// **'Pause zu kurz'**
  String get entriesBreakInsufficientTooltip;

  /// No description provided for @entriesToday.
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get entriesToday;

  /// No description provided for @entriesYesterday.
  ///
  /// In de, this message translates to:
  /// **'Gestern'**
  String get entriesYesterday;

  /// No description provided for @entriesWeekHeader.
  ///
  /// In de, this message translates to:
  /// **'KW {week} · {range}'**
  String entriesWeekHeader(int week, String range);

  /// No description provided for @entriesWorkLabel.
  ///
  /// In de, this message translates to:
  /// **'Arbeitszeit: {duration}'**
  String entriesWorkLabel(String duration);

  /// No description provided for @entriesBreakInsufficientDaysTooltip.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Tag mit zu kurzer Pause} other{{count} Tage mit zu kurzer Pause}}'**
  String entriesBreakInsufficientDaysTooltip(num count);

  /// No description provided for @quickAddDurationChipLabel.
  ///
  /// In de, this message translates to:
  /// **'{minutes} Min'**
  String quickAddDurationChipLabel(int minutes);

  /// No description provided for @quickAddSubmitLabel.
  ///
  /// In de, this message translates to:
  /// **'Eintrag hinzufügen'**
  String get quickAddSubmitLabel;

  /// No description provided for @settingsQuickAddTitle.
  ///
  /// In de, this message translates to:
  /// **'Schnelleingabe'**
  String get settingsQuickAddTitle;

  /// No description provided for @settingsQuickAddDescription.
  ///
  /// In de, this message translates to:
  /// **'Diese Zeitdauern erscheinen als Schnellauswahl im Timer-Tab.'**
  String get settingsQuickAddDescription;

  /// No description provided for @settingsQuickAddAddLabel.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get settingsQuickAddAddLabel;

  /// No description provided for @settingsQuickAddRemoveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get settingsQuickAddRemoveTooltip;

  /// No description provided for @settingsQuickAddNewDurationLabel.
  ///
  /// In de, this message translates to:
  /// **'Minuten'**
  String get settingsQuickAddNewDurationLabel;

  /// No description provided for @settingsBreakRuleTitle.
  ///
  /// In de, this message translates to:
  /// **'Pausenregeln'**
  String get settingsBreakRuleTitle;

  /// No description provided for @settingsBreakRuleDescription.
  ///
  /// In de, this message translates to:
  /// **'Legt fest, ab wie viel Arbeitszeit wie viel Pause nötig ist. Die Tagesübersicht warnt, wenn die Pause zu kurz war.'**
  String get settingsBreakRuleDescription;

  /// No description provided for @settingsBreakRulePresetGermany.
  ///
  /// In de, this message translates to:
  /// **'Deutschland'**
  String get settingsBreakRulePresetGermany;

  /// No description provided for @settingsBreakRulePresetAustria.
  ///
  /// In de, this message translates to:
  /// **'Österreich'**
  String get settingsBreakRulePresetAustria;

  /// No description provided for @settingsBreakRulePresetSwitzerland.
  ///
  /// In de, this message translates to:
  /// **'Schweiz'**
  String get settingsBreakRulePresetSwitzerland;

  /// No description provided for @settingsBreakRuleNone.
  ///
  /// In de, this message translates to:
  /// **'Keine'**
  String get settingsBreakRuleNone;

  /// No description provided for @settingsBreakRuleTierLabel.
  ///
  /// In de, this message translates to:
  /// **'Ab {worked} → {breakTime} Pause'**
  String settingsBreakRuleTierLabel(String worked, String breakTime);

  /// No description provided for @settingsBreakRuleRemoveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get settingsBreakRuleRemoveTooltip;

  /// No description provided for @settingsBreakRuleAddLabel.
  ///
  /// In de, this message translates to:
  /// **'Regel hinzufügen'**
  String get settingsBreakRuleAddLabel;

  /// No description provided for @settingsBreakRuleAddTitle.
  ///
  /// In de, this message translates to:
  /// **'Neue Pausenregel'**
  String get settingsBreakRuleAddTitle;

  /// No description provided for @settingsBreakRuleAfterMinutesLabel.
  ///
  /// In de, this message translates to:
  /// **'Ab Minuten Arbeit'**
  String get settingsBreakRuleAfterMinutesLabel;

  /// No description provided for @settingsBreakRuleRequiredMinutesLabel.
  ///
  /// In de, this message translates to:
  /// **'Minuten Pause nötig'**
  String get settingsBreakRuleRequiredMinutesLabel;

  /// No description provided for @settingsBreakRuleSaveError.
  ///
  /// In de, this message translates to:
  /// **'Änderung konnte nicht gespeichert werden.'**
  String get settingsBreakRuleSaveError;

  /// No description provided for @settingsBreakRuleInvalidTierError.
  ///
  /// In de, this message translates to:
  /// **'Bitte gültige Minutenwerte eingeben.'**
  String get settingsBreakRuleInvalidTierError;

  /// No description provided for @settingsBreakRuleIncludePausedTime.
  ///
  /// In de, this message translates to:
  /// **'Pause-Button-Zeit einbeziehen'**
  String get settingsBreakRuleIncludePausedTime;

  /// No description provided for @settingsBreakRuleIncludePausedTimeDescription.
  ///
  /// In de, this message translates to:
  /// **'Zählt die über den Pause-Button pausierte Zeit zusätzlich zu Lücken zwischen Einträgen als Pause.'**
  String get settingsBreakRuleIncludePausedTimeDescription;

  /// No description provided for @settingsProjectsTitle.
  ///
  /// In de, this message translates to:
  /// **'Projekte'**
  String get settingsProjectsTitle;

  /// No description provided for @settingsProjectsDescription.
  ///
  /// In de, this message translates to:
  /// **'Projekte anlegen, bearbeiten und archivieren.'**
  String get settingsProjectsDescription;

  /// No description provided for @settingsProjectsAddLabel.
  ///
  /// In de, this message translates to:
  /// **'Projekt hinzufügen'**
  String get settingsProjectsAddLabel;

  /// No description provided for @settingsProjectsArchivedSection.
  ///
  /// In de, this message translates to:
  /// **'Archivierte Projekte'**
  String get settingsProjectsArchivedSection;

  /// No description provided for @settingsProjectsSaveError.
  ///
  /// In de, this message translates to:
  /// **'Änderung konnte nicht gespeichert werden.'**
  String get settingsProjectsSaveError;

  /// No description provided for @projectsNewProjectTitle.
  ///
  /// In de, this message translates to:
  /// **'Neues Projekt'**
  String get projectsNewProjectTitle;

  /// No description provided for @projectsNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get projectsNameLabel;

  /// No description provided for @projectsCreateButton.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get projectsCreateButton;

  /// No description provided for @projectsEditTitle.
  ///
  /// In de, this message translates to:
  /// **'Projekt bearbeiten'**
  String get projectsEditTitle;

  /// No description provided for @projectsBillableLabel.
  ///
  /// In de, this message translates to:
  /// **'Abrechenbar'**
  String get projectsBillableLabel;

  /// No description provided for @projectsHourlyRateLabel.
  ///
  /// In de, this message translates to:
  /// **'Stundensatz'**
  String get projectsHourlyRateLabel;

  /// No description provided for @projectsCurrencyLabel.
  ///
  /// In de, this message translates to:
  /// **'Währung'**
  String get projectsCurrencyLabel;

  /// No description provided for @projectsArchiveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get projectsArchiveTooltip;

  /// No description provided for @projectsUnarchiveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Reaktivieren'**
  String get projectsUnarchiveTooltip;

  /// No description provided for @projectsEditTooltip.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get projectsEditTooltip;

  /// No description provided for @projectsDeleteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get projectsDeleteTooltip;

  /// No description provided for @projectsDeleteConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Projekt löschen?'**
  String get projectsDeleteConfirmTitle;

  /// No description provided for @projectsDeleteConfirmMessage.
  ///
  /// In de, this message translates to:
  /// **'Dieses Projekt wird endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get projectsDeleteConfirmMessage;

  /// No description provided for @projectsDeleteHasEntriesError.
  ///
  /// In de, this message translates to:
  /// **'Dieses Projekt hat noch zugewiesene Zeiteinträge und kann nicht gelöscht werden.'**
  String get projectsDeleteHasEntriesError;

  /// No description provided for @projectsInvalidRateError.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen gültigen Betrag eingeben.'**
  String get projectsInvalidRateError;

  /// No description provided for @settingsClientsTitle.
  ///
  /// In de, this message translates to:
  /// **'Kunden'**
  String get settingsClientsTitle;

  /// No description provided for @settingsClientsDescription.
  ///
  /// In de, this message translates to:
  /// **'Kunden anlegen, bearbeiten und archivieren.'**
  String get settingsClientsDescription;

  /// No description provided for @settingsClientsAddLabel.
  ///
  /// In de, this message translates to:
  /// **'Kunde hinzufügen'**
  String get settingsClientsAddLabel;

  /// No description provided for @settingsClientsArchivedSection.
  ///
  /// In de, this message translates to:
  /// **'Archivierte Kunden'**
  String get settingsClientsArchivedSection;

  /// No description provided for @settingsClientsSaveError.
  ///
  /// In de, this message translates to:
  /// **'Änderung konnte nicht gespeichert werden.'**
  String get settingsClientsSaveError;

  /// No description provided for @clientsNewClientTitle.
  ///
  /// In de, this message translates to:
  /// **'Neuer Kunde'**
  String get clientsNewClientTitle;

  /// No description provided for @clientsNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get clientsNameLabel;

  /// No description provided for @clientsCreateButton.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get clientsCreateButton;

  /// No description provided for @clientsEditTitle.
  ///
  /// In de, this message translates to:
  /// **'Kunde bearbeiten'**
  String get clientsEditTitle;

  /// No description provided for @clientsEditTooltip.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get clientsEditTooltip;

  /// No description provided for @clientsArchiveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get clientsArchiveTooltip;

  /// No description provided for @clientsUnarchiveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Reaktivieren'**
  String get clientsUnarchiveTooltip;

  /// No description provided for @clientsDeleteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get clientsDeleteTooltip;

  /// No description provided for @clientsDeleteConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Kunde löschen?'**
  String get clientsDeleteConfirmTitle;

  /// No description provided for @clientsDeleteConfirmMessage.
  ///
  /// In de, this message translates to:
  /// **'Dieser Kunde wird endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get clientsDeleteConfirmMessage;

  /// No description provided for @clientsDeleteHasProjectsError.
  ///
  /// In de, this message translates to:
  /// **'Dieser Kunde hat noch zugewiesene Projekte und kann nicht gelöscht werden.'**
  String get clientsDeleteHasProjectsError;

  /// No description provided for @projectsClientLabel.
  ///
  /// In de, this message translates to:
  /// **'Kunde'**
  String get projectsClientLabel;

  /// No description provided for @projectsClientNone.
  ///
  /// In de, this message translates to:
  /// **'Kein Kunde'**
  String get projectsClientNone;

  /// No description provided for @projectsClientCreateNew.
  ///
  /// In de, this message translates to:
  /// **'+ Neuer Kunde…'**
  String get projectsClientCreateNew;

  /// No description provided for @projectsClientArchivedLabel.
  ///
  /// In de, this message translates to:
  /// **'{name} (archiviert)'**
  String projectsClientArchivedLabel(String name);

  /// No description provided for @reportsTitle.
  ///
  /// In de, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @reportsThisWeek.
  ///
  /// In de, this message translates to:
  /// **'Diese Woche'**
  String get reportsThisWeek;

  /// No description provided for @reportsThisMonth.
  ///
  /// In de, this message translates to:
  /// **'Dieser Monat'**
  String get reportsThisMonth;

  /// No description provided for @reportsLast30Days.
  ///
  /// In de, this message translates to:
  /// **'Letzte 30 Tage'**
  String get reportsLast30Days;

  /// No description provided for @reportsAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get reportsAll;

  /// No description provided for @reportsCustomRange.
  ///
  /// In de, this message translates to:
  /// **'Benutzerdefiniert…'**
  String get reportsCustomRange;

  /// No description provided for @reportsToday.
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get reportsToday;

  /// No description provided for @reportsYesterday.
  ///
  /// In de, this message translates to:
  /// **'Gestern'**
  String get reportsYesterday;

  /// No description provided for @reportsError.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {error}'**
  String reportsError(String error);

  /// No description provided for @reportsExportCsv.
  ///
  /// In de, this message translates to:
  /// **'CSV exportieren'**
  String get reportsExportCsv;

  /// No description provided for @reportsExportedTo.
  ///
  /// In de, this message translates to:
  /// **'Exportiert nach: {path}'**
  String reportsExportedTo(String path);

  /// No description provided for @reportsTotal.
  ///
  /// In de, this message translates to:
  /// **'Gesamt: {duration}'**
  String reportsTotal(String duration);

  /// No description provided for @reportsEmptyRange.
  ///
  /// In de, this message translates to:
  /// **'Keine Einträge in diesem Zeitraum.'**
  String get reportsEmptyRange;

  /// No description provided for @reportsEmptyFiltered.
  ///
  /// In de, this message translates to:
  /// **'Keine Einträge für diesen Zeitraum und diese Filter.'**
  String get reportsEmptyFiltered;

  /// No description provided for @reportsFilterTooltip.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get reportsFilterTooltip;

  /// No description provided for @reportsFilterDialogTitle.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get reportsFilterDialogTitle;

  /// No description provided for @reportsFilterProjectsLabel.
  ///
  /// In de, this message translates to:
  /// **'Projekte'**
  String get reportsFilterProjectsLabel;

  /// No description provided for @reportsFilterProjectsHint.
  ///
  /// In de, this message translates to:
  /// **'Keine Auswahl entspricht allen Projekten.'**
  String get reportsFilterProjectsHint;

  /// No description provided for @reportsFilterBillableLabel.
  ///
  /// In de, this message translates to:
  /// **'Abrechenbar'**
  String get reportsFilterBillableLabel;

  /// No description provided for @reportsFilterBillableAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get reportsFilterBillableAll;

  /// No description provided for @reportsFilterBillableOnly.
  ///
  /// In de, this message translates to:
  /// **'Nur abrechenbar'**
  String get reportsFilterBillableOnly;

  /// No description provided for @reportsFilterBillableNonOnly.
  ///
  /// In de, this message translates to:
  /// **'Nur nicht abrechenbar'**
  String get reportsFilterBillableNonOnly;

  /// No description provided for @reportsFilterReset.
  ///
  /// In de, this message translates to:
  /// **'Filter zurücksetzen'**
  String get reportsFilterReset;

  /// No description provided for @csvHeaderDate.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get csvHeaderDate;

  /// No description provided for @csvHeaderStart.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get csvHeaderStart;

  /// No description provided for @csvHeaderEnd.
  ///
  /// In de, this message translates to:
  /// **'Ende'**
  String get csvHeaderEnd;

  /// No description provided for @csvHeaderDurationHours.
  ///
  /// In de, this message translates to:
  /// **'Dauer (Std)'**
  String get csvHeaderDurationHours;

  /// No description provided for @csvHeaderProject.
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get csvHeaderProject;

  /// No description provided for @csvHeaderDescription.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get csvHeaderDescription;

  /// No description provided for @csvHeaderBillable.
  ///
  /// In de, this message translates to:
  /// **'Abrechenbar'**
  String get csvHeaderBillable;

  /// No description provided for @csvHeaderAmount.
  ///
  /// In de, this message translates to:
  /// **'Betrag'**
  String get csvHeaderAmount;

  /// No description provided for @csvHeaderCurrency.
  ///
  /// In de, this message translates to:
  /// **'Währung'**
  String get csvHeaderCurrency;

  /// No description provided for @csvYes.
  ///
  /// In de, this message translates to:
  /// **'ja'**
  String get csvYes;

  /// No description provided for @csvNo.
  ///
  /// In de, this message translates to:
  /// **'nein'**
  String get csvNo;

  /// No description provided for @entriesJiraStatusSynced.
  ///
  /// In de, this message translates to:
  /// **'In Jira gebucht'**
  String get entriesJiraStatusSynced;

  /// No description provided for @entriesJiraStatusPending.
  ///
  /// In de, this message translates to:
  /// **'Jira-Buchung ausstehend'**
  String get entriesJiraStatusPending;

  /// No description provided for @entriesJiraStatusError.
  ///
  /// In de, this message translates to:
  /// **'Jira-Buchung fehlgeschlagen'**
  String get entriesJiraStatusError;

  /// No description provided for @settingsResetTitle.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get settingsResetTitle;

  /// No description provided for @settingsResetDescription.
  ///
  /// In de, this message translates to:
  /// **'Löscht alle lokalen Daten dieses Geräts (Projekte, Kunden, Zeiteinträge, Einstellungen, Jira-/Personio-Verknüpfungen), entfernt den eigenen Verlauf dieses Geräts endgültig aus dem Sync-Ordner und trennt die Verbindung dazu. Andere Geräte sind davon nicht betroffen, können den entfernten Verlauf aber auch nicht mehr nachträglich sehen.'**
  String get settingsResetDescription;

  /// No description provided for @settingsResetButton.
  ///
  /// In de, this message translates to:
  /// **'Komplett zurücksetzen'**
  String get settingsResetButton;

  /// No description provided for @settingsResetConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Wirklich alles zurücksetzen?'**
  String get settingsResetConfirmTitle;

  /// No description provided for @settingsResetConfirmMessage.
  ///
  /// In de, this message translates to:
  /// **'Projekte, Kunden, Zeiteinträge, Einstellungen und Jira-/Personio-Verknüpfungen auf diesem Gerät werden unwiderruflich gelöscht. Der eigene Verlauf dieses Geräts wird auch endgültig aus dem Sync-Ordner entfernt, und die Verbindung dazu wird getrennt. Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get settingsResetConfirmMessage;

  /// No description provided for @settingsResetConfirmButton.
  ///
  /// In de, this message translates to:
  /// **'Ja, alles zurücksetzen'**
  String get settingsResetConfirmButton;

  /// No description provided for @settingsResetSuccess.
  ///
  /// In de, this message translates to:
  /// **'App wurde zurückgesetzt.'**
  String get settingsResetSuccess;

  /// No description provided for @settingsResetError.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen fehlgeschlagen.'**
  String get settingsResetError;
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
