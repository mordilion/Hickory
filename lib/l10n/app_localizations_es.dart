// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get trayOpen => 'Abrir';

  @override
  String get trayQuit => 'Salir';

  @override
  String get trayBackgroundNotice =>
      'Hickory sigue ejecutándose en segundo plano.';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String settingsLanguageSystem(String language) {
    return 'Predeterminado del sistema ($language)';
  }

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAutostart => 'Abrir al iniciar el sistema';

  @override
  String get settingsDateFormat => 'Formato de fecha';

  @override
  String get settingsTimeFormat => 'Formato de hora';

  @override
  String get syncTitle => 'Ajustes de sincronización';

  @override
  String get syncNoFolderSelected =>
      'Ninguna carpeta seleccionada: los datos permanecen solo en este dispositivo.';

  @override
  String syncFolderPath(String path) {
    return 'Carpeta de sincronización: $path';
  }

  @override
  String syncError(String error) {
    return 'Error: $error';
  }

  @override
  String get syncFolderDescription =>
      'Elige una carpeta que ya esté sincronizada por iCloud Drive, Google Drive, Dropbox o similar. Hickory solo escribe sus propios archivos ahí y no se sincroniza con la nube por sí mismo.';

  @override
  String get syncNowButton => 'Sincronizar ahora';

  @override
  String get syncChooseFolderButton => 'Elegir carpeta';

  @override
  String syncFolderChosen(String path) {
    return 'Carpeta seleccionada: $path';
  }

  @override
  String get syncCompleted => 'Sincronización completada.';
}
