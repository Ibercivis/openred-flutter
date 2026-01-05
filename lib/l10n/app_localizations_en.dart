// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Open-red';

  @override
  String get navTracks => 'Tracks';

  @override
  String get navMap => 'Map';

  @override
  String get navDevice => 'Device';

  @override
  String get navProfile => 'Profile';

  @override
  String get navAbout => 'About';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSpanish => 'Spanish';

  @override
  String todayAt(Object time) {
    return 'Today, $time';
  }

  @override
  String yesterdayAt(Object time) {
    return 'Yesterday, $time';
  }

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get upload => 'Upload';

  @override
  String get tracksLoginToSync => 'Login to sync and download cloud tracks';

  @override
  String get tracksNeedLoginToView => 'You need to log in to view your tracks.';

  @override
  String get tracksNoTracksYet => 'No tracks yet';

  @override
  String get tracksNoTracksSubtitle =>
      'Record a track, or login to download cloud tracks.';

  @override
  String get tracksUnnamed => 'Unnamed Track';

  @override
  String get tracksTooltipExportLocalJson => 'Export local JSON';

  @override
  String get tracksTooltipRefresh => 'Refresh';

  @override
  String get tracksTooltipViewOnMap => 'View on map';

  @override
  String get tracksStatusPending => 'Pending';

  @override
  String get tracksStatusSynced => 'Synced';

  @override
  String get tracksStatusLocalAndCloud => 'Local + Cloud';

  @override
  String get tracksStatusDownloading => 'Downloading…';

  @override
  String get tracksStatusDownloadFailed => 'Download failed';

  @override
  String get tracksStatusCloudOnly => 'Cloud only';

  @override
  String get tracksStatusLocalOnly => 'Local only';

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
  String get tracksDeleteLocalTitle => 'Delete local track?';

  @override
  String tracksDeleteLocalBody(String name) {
    return '\"$name\" will be deleted from this device.';
  }

  @override
  String get tracksDeleteCloudTitle => 'Delete cloud track?';

  @override
  String tracksDeleteCloudBody(String name) {
    return '\"$name\" will be deleted from the cloud.';
  }

  @override
  String get tracksSnackLocalDeleted => 'Local track deleted.';

  @override
  String get tracksSnackCloudDeleted => 'Cloud track deleted.';

  @override
  String get tracksSnackFileNotFound => 'File not found.';

  @override
  String get tracksSnackNoLocalJsonToExport =>
      'No local JSON files found to export.';

  @override
  String tracksErrorDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String tracksErrorExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String tracksErrorDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String tracksSnackCloudNoMeasurementsYet(String status) {
    return 'Track is $status (no measurements yet).';
  }

  @override
  String get loginWelcomeBack => 'Welcome Back';

  @override
  String get loginToYourAccount => 'Login to your account';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get or => 'or';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get dontHaveAccountRegister => 'Don\'t have an account? Register';

  @override
  String get validationEnterEmail => 'Please enter your email';

  @override
  String get validationEnterValidEmail => 'Please enter a valid email';

  @override
  String get validationEnterPassword => 'Please enter your password';

  @override
  String validationPasswordMin(Object min) {
    return 'Password must be at least $min characters';
  }

  @override
  String get snackLoginSuccessful => 'Login successful!';

  @override
  String get snackLoginFailed => 'Login failed';

  @override
  String get snackGoogleCancelled => 'Google sign-in cancelled';

  @override
  String get snackGoogleNoAccessToken =>
      'Google sign-in did not return an access token';

  @override
  String get snackGoogleLoginFailed => 'Google login failed';

  @override
  String get snackGoogleNotSupported =>
      'Google sign-in is not available on this platform';

  @override
  String get snackLoggedOut => 'Logged out successfully';

  @override
  String get na => 'N/A';

  @override
  String get profileUserFallback => 'User';

  @override
  String get profileStatusActive => 'Active';

  @override
  String get profileStatusInactive => 'Inactive';

  @override
  String get profileUserIdLabel => 'User ID';

  @override
  String get profileUsernameLabel => 'Username';

  @override
  String get profileMemberSinceLabel => 'Member Since';

  @override
  String get deviceDisconnected => 'Disconnected';

  @override
  String get deviceConnecting => 'Connecting…';

  @override
  String get deviceSearchingRadiaCode => 'Searching for RadiaCode devices...';

  @override
  String get deviceNoRadiaCodeDevicesFound =>
      'No RadiaCode devices found\nTap the scan button to start';

  @override
  String get deviceUnknownDevice => 'Unknown device';

  @override
  String deviceListId(String id) {
    return 'ID: $id';
  }

  @override
  String deviceListRssi(int rssi) {
    return 'RSSI: $rssi dBm';
  }

  @override
  String get deviceConnect => 'Connect';

  @override
  String get deviceStartScan => 'Start Scan';

  @override
  String get deviceStopScan => 'Stop Scan';

  @override
  String get deviceDisconnect => 'Disconnect';

  @override
  String get deviceDisconnecting => 'Disconnecting…';

  @override
  String get deviceDisconnectDialogTitle => 'Disconnect device?';

  @override
  String get deviceDisconnectDialogBody =>
      'This will stop live readings and end the Bluetooth connection.';

  @override
  String get deviceMuteGeiger => 'Mute Geiger';

  @override
  String get deviceUnmuteGeiger => 'Unmute Geiger';

  @override
  String get deviceMetricCps => 'CPS';

  @override
  String get deviceMetricDoseRate => 'Dose Rate';

  @override
  String deviceGpsAccuracy(String meters) {
    return 'GPS Accuracy: $meters m';
  }

  @override
  String get trackingNeedLogin => 'You need to log in to track';

  @override
  String get trackingHighPrecisionOk => 'High precision OK';

  @override
  String trackingNeedAccuracyToRecord(String meters) {
    return 'Need ≤ $meters m to record';
  }

  @override
  String get discard => 'Discard';

  @override
  String get save => 'Save';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get trackingStatusRecording => 'Track • Recording';

  @override
  String get trackingStatusPaused => 'Track • Paused';

  @override
  String get trackingTrack => 'Track';

  @override
  String get deviceGettingHighAccuracyGpsFix =>
      'Getting high-accuracy GPS fix...';

  @override
  String get deviceSnackConnectedReady => 'RadiaCode connected and ready!';

  @override
  String get aboutBody =>
      'Open-red is a project arising from an agreement between the Consejo de Seguridad Nuclear and the Ibercivis Foundation. The project also involves the Universitat Politècnica de Catalunya, the University of Zaragoza, the University of Cantabria and the Centro de Investigaciones Energéticas, Medioambientales y Tecnológicas. For more information, follow the links below.';

  @override
  String get aboutProjectWebpage => 'Project webpage';

  @override
  String get aboutProjectMap => 'Project map';

  @override
  String get aboutCommunityTelegram => 'Community (Telegram)';

  @override
  String get aboutDevelopedBy => 'Developed by Ibercivis';

  @override
  String aboutOpenUrlFailed(String url) {
    return 'Could not open: $url';
  }
}
