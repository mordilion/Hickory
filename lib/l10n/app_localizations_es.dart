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
  String get settingsCategoryGeneral => 'General';

  @override
  String get settingsCategoryTimeTracking => 'Seguimiento de tiempo';

  @override
  String get settingsAutostart => 'Abrir al iniciar el sistema';

  @override
  String get settingsDateFormat => 'Formato de fecha';

  @override
  String get settingsTimeFormat => 'Formato de hora';

  @override
  String get settingsUpdateTitle => 'Actualizaciones';

  @override
  String settingsUpdateCurrentVersion(Object version) {
    return 'Versión actual: $version';
  }

  @override
  String get settingsUpdateCheckButton => 'Buscar actualizaciones';

  @override
  String get settingsUpdateChecking => 'Buscando actualizaciones...';

  @override
  String get settingsUpdateUpToDate => 'Tienes la última versión.';

  @override
  String get settingsUpdateCheckError =>
      'La comprobación de actualizaciones falló. Inténtalo de nuevo más tarde.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'La versión $version está disponible.';
  }

  @override
  String get settingsUpdateInstallButton => 'Instalar ahora';

  @override
  String get settingsUpdateInstalling => 'Instalando actualización...';

  @override
  String get settingsUpdateInstallError =>
      'La instalación falló. Inténtalo de nuevo o descarga la nueva versión manualmente desde GitHub.';

  @override
  String get settingsUpdateInstallErrorPermission =>
      'Hickory no puede escribir en su carpeta de instalación: la app se ejecuta en la sandbox de macOS, que lo impide independientemente de los permisos de la carpeta. Descarga la nueva versión desde GitHub y reemplaza la app en el Finder.';

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
  String get syncJiraSectionTitle => 'Integración con Jira';

  @override
  String get syncJiraBaseUrlLabel => 'URL de Jira';

  @override
  String get syncJiraEmailLabel => 'Correo electrónico';

  @override
  String get syncJiraApiTokenLabel => 'Token de API';

  @override
  String get syncJiraSaveCredentialsButton => 'Guardar credenciales';

  @override
  String get syncJiraCredentialsSaved => 'Credenciales guardadas.';

  @override
  String get syncJiraTestConnectionButton => 'Probar conexión';

  @override
  String get syncJiraTestConnectionSuccess => 'Conexión correcta.';

  @override
  String get syncJiraTestConnectionFailure =>
      'Error de conexión. Comprueba tus credenciales.';

  @override
  String get syncJiraSyncButton => 'Sincronizar con Jira ahora';

  @override
  String get syncJiraNotConfigured => 'Jira aún no está configurado.';

  @override
  String get syncJiraInvalidCredentials =>
      'Introduce una URL de Jira, correo electrónico y token de API válidos.';

  @override
  String get syncJiraUnexpectedError =>
      'Se produjo un error. Inténtalo de nuevo.';

  @override
  String syncJiraSyncResult(int created, int updated, int deleted, int failed) {
    return '$created creadas, $updated actualizadas, $deleted eliminadas, $failed fallidas.';
  }

  @override
  String get syncPersonioSectionTitle => 'Integración con Personio';

  @override
  String get syncPersonioClientIdLabel => 'Client ID';

  @override
  String get syncPersonioClientSecretLabel => 'Client Secret';

  @override
  String get syncPersonioEmployeeIdLabel => 'ID de empleado';

  @override
  String get syncPersonioSaveCredentialsButton => 'Guardar credenciales';

  @override
  String get syncPersonioCredentialsSaved => 'Credenciales guardadas.';

  @override
  String get syncPersonioTestConnectionButton => 'Probar conexión';

  @override
  String get syncPersonioTestConnectionSuccess => 'Conexión exitosa.';

  @override
  String get syncPersonioTestConnectionFailure =>
      'Conexión fallida. Por favor, verifica tus credenciales.';

  @override
  String get syncPersonioNotConfigured => 'Personio aún no está configurado.';

  @override
  String get syncPersonioInvalidCredentials =>
      'Introduce el Client ID, el Client Secret y el ID de empleado.';

  @override
  String get syncPersonioUnexpectedError =>
      'Algo salió mal. Por favor, inténtalo de nuevo.';

  @override
  String get syncPersonioFromLabel => 'Desde';

  @override
  String get syncPersonioToLabel => 'Hasta';

  @override
  String get syncPersonioPushButton => 'Enviar a Personio';

  @override
  String syncPersonioPushResult(
    int created,
    int updated,
    int deleted,
    int failed,
  ) {
    return '$created creado(s), $updated actualizado(s), $deleted eliminado(s), $failed fallido(s).';
  }

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
  String get timerModeManual => 'Manual';

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
  String get commonDelete => 'Eliminar';

  @override
  String get commonClose => 'Cerrar';

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
  String get entriesDeleteConfirmTitle => '¿Eliminar entrada?';

  @override
  String get entriesDeleteConfirmMessage =>
      'Esta entrada se eliminará permanentemente. Esta acción no se puede deshacer.';

  @override
  String entriesBreakLabel(String duration) {
    return 'Pausa: $duration';
  }

  @override
  String get entriesBreakInsufficientTooltip => 'Pausa demasiado corta';

  @override
  String get entriesToday => 'Hoy';

  @override
  String get entriesYesterday => 'Ayer';

  @override
  String get migrationFailedTitle => 'No se pudieron trasladar los datos';

  @override
  String migrationFailedMessage(String path, String error) {
    return 'Hickory encontró tus datos existentes pero no pudo copiarlos a su nueva ubicación. No continúa a propósito, para no crear una base de datos vacía y mantener accesibles los datos antiguos. Están en:\n\n$path\n\nLa versión anterior todavía puede abrirlos. Error: $error';
  }

  @override
  String entriesWeekLabel(int week) {
    return 'Semana $week';
  }

  @override
  String get entriesUpOneLevelTooltip => 'Subir un nivel';

  @override
  String get entriesAllYearsLabel => 'Todos los años';

  @override
  String entriesWeekDayRange(int first, int last) {
    return '$first–$last';
  }

  @override
  String entriesWeekHeader(int week, String range) {
    return 'Semana $week · $range';
  }

  @override
  String entriesWorkLabel(String duration) {
    return 'Trabajado: $duration';
  }

  @override
  String entriesBreakInsufficientDaysTooltip(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días con pausas demasiado cortas',
      one: '1 día con una pausa demasiado corta',
    );
    return '$_temp0';
  }

  @override
  String quickAddDurationChipLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get quickAddSubmitLabel => 'Añadir entrada';

  @override
  String get settingsQuickAddTitle => 'Entrada rápida';

  @override
  String get settingsQuickAddDescription =>
      'Estas duraciones aparecen como botones de entrada rápida en la pestaña Timer.';

  @override
  String get settingsQuickAddAddLabel => 'Añadir';

  @override
  String get settingsQuickAddRemoveTooltip => 'Eliminar';

  @override
  String get settingsQuickAddNewDurationLabel => 'Minutos';

  @override
  String get settingsBreakRuleTitle => 'Reglas de descanso';

  @override
  String get settingsBreakRuleDescription =>
      'Define cuánto descanso se necesita a partir de cuánto tiempo trabajado. El resumen diario avisa si la pausa fue demasiado corta.';

  @override
  String get settingsBreakRulePresetGermany => 'Alemania';

  @override
  String get settingsBreakRulePresetAustria => 'Austria';

  @override
  String get settingsBreakRulePresetSwitzerland => 'Suiza';

  @override
  String get settingsBreakRuleNone => 'Ninguna';

  @override
  String settingsBreakRuleTierLabel(String worked, String breakTime) {
    return 'Tras $worked → $breakTime de descanso';
  }

  @override
  String get settingsBreakRuleRemoveTooltip => 'Eliminar';

  @override
  String get settingsBreakRuleAddLabel => 'Añadir regla';

  @override
  String get settingsBreakRuleAddTitle => 'Nueva regla de descanso';

  @override
  String get settingsBreakRuleAfterMinutesLabel => 'Tras minutos trabajados';

  @override
  String get settingsBreakRuleRequiredMinutesLabel =>
      'Minutos de descanso necesarios';

  @override
  String get settingsBreakRuleSaveError => 'No se pudo guardar el cambio.';

  @override
  String get settingsBreakRuleInvalidTierError =>
      'Introduce valores de minutos válidos.';

  @override
  String get settingsBreakRuleIncludePausedTime =>
      'Incluir el tiempo del botón de pausa';

  @override
  String get settingsBreakRuleIncludePausedTimeDescription =>
      'Cuenta el tiempo pausado con el botón de pausa como descanso, además de los huecos entre entradas.';

  @override
  String get settingsProjectsTitle => 'Proyectos';

  @override
  String get settingsProjectsDescription => 'Crea, edita y archiva proyectos.';

  @override
  String get settingsProjectsAddLabel => 'Añadir proyecto';

  @override
  String get settingsProjectsArchivedSection => 'Proyectos archivados';

  @override
  String get settingsProjectsSaveError => 'No se pudo guardar el cambio.';

  @override
  String get projectsNewProjectTitle => 'Nuevo proyecto';

  @override
  String get projectsNameLabel => 'Nombre';

  @override
  String get projectsCreateButton => 'Crear';

  @override
  String get projectsEditTitle => 'Editar proyecto';

  @override
  String get projectsBillableLabel => 'Facturable';

  @override
  String get projectsHourlyRateLabel => 'Tarifa por hora';

  @override
  String get projectsCurrencyLabel => 'Moneda';

  @override
  String get projectsArchiveTooltip => 'Archivar';

  @override
  String get projectsUnarchiveTooltip => 'Reactivar';

  @override
  String get projectsEditTooltip => 'Editar';

  @override
  String get projectsDeleteTooltip => 'Eliminar';

  @override
  String get projectsDeleteConfirmTitle => '¿Eliminar proyecto?';

  @override
  String get projectsDeleteConfirmMessage =>
      'Este proyecto se eliminará permanentemente. Esta acción no se puede deshacer.';

  @override
  String get projectsDeleteHasEntriesError =>
      'Este proyecto todavía tiene entradas de tiempo asignadas y no se puede eliminar.';

  @override
  String get projectsInvalidRateError => 'Introduce un importe válido.';

  @override
  String get settingsClientsTitle => 'Clientes';

  @override
  String get settingsClientsDescription => 'Crea, edita y archiva clientes.';

  @override
  String get settingsClientsAddLabel => 'Añadir cliente';

  @override
  String get settingsClientsArchivedSection => 'Clientes archivados';

  @override
  String get settingsClientsSaveError => 'No se pudo guardar el cambio.';

  @override
  String get clientsNewClientTitle => 'Nuevo cliente';

  @override
  String get clientsNameLabel => 'Nombre';

  @override
  String get clientsCreateButton => 'Crear';

  @override
  String get clientsEditTitle => 'Editar cliente';

  @override
  String get clientsEditTooltip => 'Editar';

  @override
  String get clientsArchiveTooltip => 'Archivar';

  @override
  String get clientsUnarchiveTooltip => 'Reactivar';

  @override
  String get clientsDeleteTooltip => 'Eliminar';

  @override
  String get clientsDeleteConfirmTitle => '¿Eliminar cliente?';

  @override
  String get clientsDeleteConfirmMessage =>
      'Este cliente se eliminará permanentemente. Esta acción no se puede deshacer.';

  @override
  String get clientsDeleteHasProjectsError =>
      'Este cliente todavía tiene proyectos asignados y no se puede eliminar.';

  @override
  String get projectsClientLabel => 'Cliente';

  @override
  String get projectsClientNone => 'Sin cliente';

  @override
  String get projectsClientCreateNew => '+ Nuevo cliente…';

  @override
  String projectsClientArchivedLabel(String name) {
    return '$name (archivado)';
  }

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
  String get reportsToday => 'Hoy';

  @override
  String get reportsYesterday => 'Ayer';

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
  String get reportsEmptyFiltered =>
      'No hay entradas para este período y estos filtros.';

  @override
  String get reportsFilterTooltip => 'Filtro';

  @override
  String get reportsFilterDialogTitle => 'Filtro';

  @override
  String get reportsFilterProjectsLabel => 'Proyectos';

  @override
  String get reportsFilterProjectsHint =>
      'Ninguna selección equivale a todos los proyectos.';

  @override
  String get reportsFilterBillableLabel => 'Facturable';

  @override
  String get reportsFilterBillableAll => 'Todo';

  @override
  String get reportsFilterBillableOnly => 'Solo facturable';

  @override
  String get reportsFilterBillableNonOnly => 'Solo no facturable';

  @override
  String get reportsFilterReset => 'Restablecer filtros';

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

  @override
  String get settingsResetTitle => 'Restablecer';

  @override
  String get settingsResetDescription =>
      'Elimina todos los datos locales de este dispositivo (proyectos, clientes, entradas de tiempo, ajustes, vínculos de Jira/Personio), elimina de forma permanente el historial propio de este dispositivo de la carpeta de sincronización y lo desconecta. Los demás dispositivos no se ven afectados, pero tampoco podrán ver ya el historial eliminado.';

  @override
  String get settingsResetButton => 'Restablecer todo';

  @override
  String get settingsResetConfirmTitle => '¿Restablecer todo de verdad?';

  @override
  String get settingsResetConfirmMessage =>
      'Los proyectos, clientes, entradas de tiempo, ajustes y vínculos de Jira/Personio de este dispositivo se eliminarán permanentemente. El historial propio de este dispositivo también se eliminará de forma permanente de la carpeta de sincronización, y se eliminará la conexión con ella. Esta acción no se puede deshacer.';

  @override
  String get settingsResetConfirmButton => 'Sí, restablecer todo';

  @override
  String get settingsResetSuccess => 'La aplicación se ha restablecido.';

  @override
  String get settingsResetError => 'No se pudo restablecer.';
}
