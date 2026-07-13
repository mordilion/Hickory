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

  @override
  String get navTimer => 'Temporizador';

  @override
  String get navReports => 'Informes';

  @override
  String get navSync => 'Sincronización';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get commonNoProject => 'Sin proyecto';

  @override
  String timerError(String error) {
    return 'Error: $error';
  }

  @override
  String get timerResume => 'Reanudar';

  @override
  String get timerPause => 'Pausar';

  @override
  String get timerStop => 'Detener';

  @override
  String get timerDescriptionLabel => '¿En qué estás trabajando?';

  @override
  String get timerProjectLabel => 'Proyecto';

  @override
  String get timerNewProjectTooltip => 'Nuevo proyecto';

  @override
  String get jiraTicketFieldLabel => 'Ticket de Jira';

  @override
  String get timerStart => 'Iniciar';

  @override
  String get timerIdleTitle => 'Inactividad detectada';

  @override
  String timerIdleMessage(int minutes) {
    return 'Has estado inactivo durante $minutes minutos. ¿Quieres restar este tiempo de la entrada en curso?';
  }

  @override
  String get timerIdleKeepTime => 'Mantener el tiempo';

  @override
  String get timerIdleTrimTime => 'Restar el tiempo inactivo';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get entriesEmpty => 'Aún no hay entradas.';

  @override
  String get entriesNoDescription => 'Sin descripción';

  @override
  String entriesError(String error) {
    return 'Error: $error';
  }

  @override
  String get entriesManualEntryTitle => 'Entrada manual';

  @override
  String get entriesEditEntryTitle => 'Editar entrada';

  @override
  String get entriesDescriptionLabel => 'Descripción';

  @override
  String get entriesProjectLabel => 'Proyecto';

  @override
  String get entriesStartLabel => 'Inicio';

  @override
  String get entriesEndLabel => 'Fin';

  @override
  String get entriesEndBeforeStartError =>
      'El fin debe ser posterior al inicio.';

  @override
  String get projectsNewProjectTitle => 'Nuevo proyecto';

  @override
  String get projectsNameLabel => 'Nombre';

  @override
  String get projectsCreateButton => 'Crear';

  @override
  String get reportsTitle => 'Informes';

  @override
  String get reportsThisWeek => 'Esta semana';

  @override
  String get reportsThisMonth => 'Este mes';

  @override
  String get reportsLast30Days => 'Últimos 30 días';

  @override
  String get reportsAll => 'Todo';

  @override
  String get reportsCustomRange => 'Personalizado…';

  @override
  String reportsError(String error) {
    return 'Error: $error';
  }

  @override
  String get reportsExportCsv => 'Exportar CSV';

  @override
  String reportsExportedTo(String path) {
    return 'Exportado a: $path';
  }

  @override
  String reportsTotal(String duration) {
    return 'Total: $duration';
  }

  @override
  String get reportsEmptyRange => 'No hay entradas en este período.';

  @override
  String get csvHeaderDate => 'Fecha';

  @override
  String get csvHeaderStart => 'Inicio';

  @override
  String get csvHeaderEnd => 'Fin';

  @override
  String get csvHeaderDurationHours => 'Duración (h)';

  @override
  String get csvHeaderProject => 'Proyecto';

  @override
  String get csvHeaderDescription => 'Descripción';

  @override
  String get csvHeaderBillable => 'Facturable';

  @override
  String get csvHeaderAmount => 'Importe';

  @override
  String get csvHeaderCurrency => 'Moneda';

  @override
  String get csvYes => 'sí';

  @override
  String get csvNo => 'no';

  @override
  String get entriesJiraStatusSynced => 'Registrado en Jira';

  @override
  String get entriesJiraStatusPending => 'Registro en Jira pendiente';

  @override
  String get entriesJiraStatusError => 'Error al registrar en Jira';
}
