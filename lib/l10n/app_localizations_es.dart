// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Open-red';

  @override
  String get navTracks => 'Tracks';

  @override
  String get navMap => 'Mapa';

  @override
  String get navDevice => 'Dispositivo';

  @override
  String get navProfile => 'Perfil';

  @override
  String get navAbout => 'Acerca de';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get languageEnglish => 'Inglés';

  @override
  String get languageSpanish => 'Español';

  @override
  String todayAt(Object time) {
    return 'Hoy, $time';
  }

  @override
  String yesterdayAt(Object time) {
    return 'Ayer, $time';
  }

  @override
  String get login => 'Iniciar sesión';

  @override
  String get logout => 'Cerrar sesión';

  @override
  String get retry => 'Reintentar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get upload => 'Subir';

  @override
  String get tracksLoginToSync =>
      'Inicia sesión para sincronizar y descargar tracks de la nube';

  @override
  String get tracksNeedLoginToView =>
      'Necesitas iniciar sesión para ver tus tracks.';

  @override
  String get tracksNoTracksYet => 'Aún no hay tracks';

  @override
  String get tracksNoTracksSubtitle =>
      'Graba un track o inicia sesión para descargar tracks de la nube.';

  @override
  String get tracksUnnamed => 'Track sin nombre';

  @override
  String get tracksTooltipExportLocalJson => 'Exportar JSON local';

  @override
  String get tracksTooltipRefresh => 'Actualizar';

  @override
  String get tracksTooltipViewOnMap => 'Ver en el mapa';

  @override
  String get tracksStatusPending => 'Pendiente';

  @override
  String get tracksStatusSynced => 'Sincronizado';

  @override
  String get tracksStatusLocalAndCloud => 'Local + Nube';

  @override
  String get tracksStatusDownloading => 'Descargando…';

  @override
  String get tracksStatusDownloadFailed => 'Fallo al descargar';

  @override
  String get tracksStatusCloudOnly => 'Solo nube';

  @override
  String get tracksStatusLocalOnly => 'Solo local';

  @override
  String tracksSummaryLine(
    String when,
    String distance,
    String duration,
    String points,
  ) {
    return '$when • $distance • $duration • $points pts';
  }

  @override
  String get tracksDeleteLocalTitle => '¿Eliminar track local?';

  @override
  String tracksDeleteLocalBody(String name) {
    return '\"$name\" se eliminará de este dispositivo.';
  }

  @override
  String get tracksDeleteCloudTitle => '¿Eliminar track de la nube?';

  @override
  String tracksDeleteCloudBody(String name) {
    return '\"$name\" se eliminará de la nube.';
  }

  @override
  String get tracksSnackLocalDeleted => 'Track local eliminado.';

  @override
  String get tracksSnackCloudDeleted => 'Track eliminado de la nube.';

  @override
  String get tracksSnackFileNotFound => 'Archivo no encontrado.';

  @override
  String get tracksSnackNoLocalJsonToExport =>
      'No se encontraron archivos JSON locales para exportar.';

  @override
  String tracksErrorDeleteFailed(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String tracksErrorExportFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String tracksErrorDownloadFailed(String error) {
    return 'Error al descargar: $error';
  }

  @override
  String tracksSnackCloudNoMeasurementsYet(String status) {
    return 'El track está $status (aún no hay mediciones).';
  }

  @override
  String get loginWelcomeBack => 'Bienvenido/a';

  @override
  String get loginToYourAccount => 'Inicia sesión en tu cuenta';

  @override
  String get email => 'Email';

  @override
  String get password => 'Contraseña';

  @override
  String get or => 'o';

  @override
  String get continueWithGoogle => 'Continuar con Google';

  @override
  String get dontHaveAccountRegister => '¿No tienes cuenta? Regístrate';

  @override
  String get validationEnterEmail => 'Introduce tu email';

  @override
  String get validationEnterValidEmail => 'Introduce un email válido';

  @override
  String get validationEnterPassword => 'Introduce tu contraseña';

  @override
  String validationPasswordMin(Object min) {
    return 'La contraseña debe tener al menos $min caracteres';
  }

  @override
  String get snackLoginSuccessful => '¡Inicio de sesión correcto!';

  @override
  String get snackLoginFailed => 'Error al iniciar sesión';

  @override
  String get snackGoogleCancelled => 'Inicio de sesión con Google cancelado';

  @override
  String get snackGoogleNoAccessToken => 'Google no devolvió un access token';

  @override
  String get snackGoogleLoginFailed => 'Error al iniciar sesión con Google';

  @override
  String get snackGoogleNotSupported =>
      'El inicio de sesión con Google no está disponible en esta plataforma';

  @override
  String get snackLoggedOut => 'Sesión cerrada correctamente';

  @override
  String get na => 'N/A';

  @override
  String get profileUserFallback => 'Usuario';

  @override
  String get profileStatusActive => 'Activo';

  @override
  String get profileStatusInactive => 'Inactivo';

  @override
  String get profileUserIdLabel => 'ID de usuario';

  @override
  String get profileUsernameLabel => 'Usuario';

  @override
  String get profileMemberSinceLabel => 'Miembro desde';

  @override
  String get deviceDisconnected => 'Desconectado';

  @override
  String get deviceConnecting => 'Conectando…';

  @override
  String get deviceSearchingRadiaCode => 'Buscando dispositivos RadiaCode...';

  @override
  String get deviceNoRadiaCodeDevicesFound =>
      'No se encontraron dispositivos RadiaCode\nPulsa el botón de escaneo para empezar';

  @override
  String get deviceUnknownDevice => 'Dispositivo desconocido';

  @override
  String deviceListId(String id) {
    return 'ID: $id';
  }

  @override
  String deviceListRssi(int rssi) {
    return 'RSSI: $rssi dBm';
  }

  @override
  String get deviceConnect => 'Conectar';

  @override
  String get deviceStartScan => 'Iniciar escaneo';

  @override
  String get deviceStopScan => 'Detener escaneo';

  @override
  String get deviceDisconnect => 'Desconectar';

  @override
  String get deviceDisconnecting => 'Desconectando…';

  @override
  String get deviceDisconnectDialogTitle => '¿Desconectar dispositivo?';

  @override
  String get deviceDisconnectDialogBody =>
      'Esto detendrá las lecturas en vivo y cerrará la conexión Bluetooth.';

  @override
  String get deviceMuteGeiger => 'Silenciar Geiger';

  @override
  String get deviceUnmuteGeiger => 'Activar Geiger';

  @override
  String get deviceMetricCps => 'CPS';

  @override
  String get deviceMetricDoseRate => 'Tasa de dosis';

  @override
  String deviceGpsAccuracy(String meters) {
    return 'Precisión GPS: $meters m';
  }

  @override
  String get trackingNeedLogin => 'Necesitas iniciar sesión para trackear';

  @override
  String get trackingHighPrecisionOk => 'Precisión suficiente';

  @override
  String trackingNeedAccuracyToRecord(String meters) {
    return 'Necesitas ≤ $meters m para grabar';
  }

  @override
  String get discard => 'Descartar';

  @override
  String get save => 'Guardar';

  @override
  String get pause => 'Pausar';

  @override
  String get resume => 'Reanudar';

  @override
  String get stop => 'Detener';

  @override
  String get trackingStatusRecording => 'Track • Grabando';

  @override
  String get trackingStatusPaused => 'Track • En pausa';

  @override
  String get trackingTrack => 'Trackear';

  @override
  String get deviceGettingHighAccuracyGpsFix =>
      'Obteniendo posición GPS de alta precisión...';

  @override
  String get deviceSnackConnectedReady => '¡RadiaCode conectado y listo!';

  @override
  String get aboutBody =>
      'Open-red es un proyecto surgido de un convenio entre el Consejo de Seguridad Nuclear y la Fundación Ibercivis. En él colaboran también la Universitat Politècnica de Catalunya, la Universidad de Zaragoza, la Universidad de Cantabria y el Centro de Investigaciones Energéticas, Medioambientales y Tecnológicas. Para más información, sigue los enlaces a continuación.';

  @override
  String get aboutProjectWebpage => 'Página web del proyecto';

  @override
  String get aboutProjectMap => 'Mapa del proyecto';

  @override
  String get aboutCommunityTelegram => 'Comunidad (Telegram)';

  @override
  String get aboutDevelopedBy => 'Desarrollado por Ibercivis';

  @override
  String aboutOpenUrlFailed(String url) {
    return 'No se pudo abrir: $url';
  }
}
