import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

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
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Open-red'**
  String get appTitle;

  /// No description provided for @navTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get navTracks;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get navDevice;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get navAbout;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String todayAt(Object time);

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String yesterdayAt(Object time);

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @tracksLoginToSync.
  ///
  /// In en, this message translates to:
  /// **'Login to sync and download cloud tracks'**
  String get tracksLoginToSync;

  /// No description provided for @tracksNeedLoginToView.
  ///
  /// In en, this message translates to:
  /// **'You need to log in to view your tracks.'**
  String get tracksNeedLoginToView;

  /// No description provided for @tracksNoTracksYet.
  ///
  /// In en, this message translates to:
  /// **'No tracks yet'**
  String get tracksNoTracksYet;

  /// No description provided for @tracksNoTracksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record a track, or login to download cloud tracks.'**
  String get tracksNoTracksSubtitle;

  /// No description provided for @tracksUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Track'**
  String get tracksUnnamed;

  /// No description provided for @tracksTooltipExportLocalJson.
  ///
  /// In en, this message translates to:
  /// **'Export local JSON'**
  String get tracksTooltipExportLocalJson;

  /// No description provided for @tracksTooltipRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get tracksTooltipRefresh;

  /// No description provided for @tracksTooltipViewOnMap.
  ///
  /// In en, this message translates to:
  /// **'View on map'**
  String get tracksTooltipViewOnMap;

  /// No description provided for @tracksStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get tracksStatusPending;

  /// No description provided for @tracksStatusSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get tracksStatusSynced;

  /// No description provided for @tracksStatusLocalAndCloud.
  ///
  /// In en, this message translates to:
  /// **'Local + Cloud'**
  String get tracksStatusLocalAndCloud;

  /// No description provided for @tracksStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get tracksStatusDownloading;

  /// No description provided for @tracksStatusDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get tracksStatusDownloadFailed;

  /// No description provided for @tracksStatusCloudOnly.
  ///
  /// In en, this message translates to:
  /// **'Cloud only'**
  String get tracksStatusCloudOnly;

  /// No description provided for @tracksStatusLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get tracksStatusLocalOnly;

  /// No description provided for @tracksSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'{when} • {distance} • {duration} • {points} pts'**
  String tracksSummaryLine(
    String when,
    String distance,
    String duration,
    String points,
  );

  /// No description provided for @tracksDeleteLocalTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete local track?'**
  String get tracksDeleteLocalTitle;

  /// No description provided for @tracksDeleteLocalBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be deleted from this device.'**
  String tracksDeleteLocalBody(String name);

  /// No description provided for @tracksDeleteCloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete cloud track?'**
  String get tracksDeleteCloudTitle;

  /// No description provided for @tracksDeleteCloudBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be deleted from the cloud.'**
  String tracksDeleteCloudBody(String name);

  /// No description provided for @tracksSnackLocalDeleted.
  ///
  /// In en, this message translates to:
  /// **'Local track deleted.'**
  String get tracksSnackLocalDeleted;

  /// No description provided for @tracksSnackCloudDeleted.
  ///
  /// In en, this message translates to:
  /// **'Cloud track deleted.'**
  String get tracksSnackCloudDeleted;

  /// No description provided for @tracksSnackFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found.'**
  String get tracksSnackFileNotFound;

  /// No description provided for @tracksSnackNoLocalJsonToExport.
  ///
  /// In en, this message translates to:
  /// **'No local JSON files found to export.'**
  String get tracksSnackNoLocalJsonToExport;

  /// No description provided for @tracksErrorDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String tracksErrorDeleteFailed(String error);

  /// No description provided for @tracksErrorExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String tracksErrorExportFailed(String error);

  /// No description provided for @tracksErrorDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String tracksErrorDownloadFailed(String error);

  /// No description provided for @tracksSnackCloudNoMeasurementsYet.
  ///
  /// In en, this message translates to:
  /// **'Track is {status} (no measurements yet).'**
  String tracksSnackCloudNoMeasurementsYet(String status);

  /// No description provided for @loginWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get loginWelcomeBack;

  /// No description provided for @loginToYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Login to your account'**
  String get loginToYourAccount;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @dontHaveAccountRegister.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Register'**
  String get dontHaveAccountRegister;

  /// No description provided for @validationEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get validationEnterEmail;

  /// No description provided for @validationEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get validationEnterValidEmail;

  /// No description provided for @validationEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get validationEnterPassword;

  /// No description provided for @validationPasswordMin.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {min} characters'**
  String validationPasswordMin(Object min);

  /// No description provided for @snackLoginSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Login successful!'**
  String get snackLoginSuccessful;

  /// No description provided for @snackLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get snackLoginFailed;

  /// No description provided for @snackGoogleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in cancelled'**
  String get snackGoogleCancelled;

  /// No description provided for @snackGoogleNoAccessToken.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in did not return an access token'**
  String get snackGoogleNoAccessToken;

  /// No description provided for @snackGoogleLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Google login failed'**
  String get snackGoogleLoginFailed;

  /// No description provided for @snackGoogleNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is not available on this platform'**
  String get snackGoogleNotSupported;

  /// No description provided for @snackLoggedOut.
  ///
  /// In en, this message translates to:
  /// **'Logged out successfully'**
  String get snackLoggedOut;

  /// No description provided for @na.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get na;

  /// No description provided for @profileUserFallback.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get profileUserFallback;

  /// No description provided for @profileStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get profileStatusActive;

  /// No description provided for @profileStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get profileStatusInactive;

  /// No description provided for @profileUserIdLabel.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get profileUserIdLabel;

  /// No description provided for @profileUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get profileUsernameLabel;

  /// No description provided for @profileMemberSinceLabel.
  ///
  /// In en, this message translates to:
  /// **'Member Since'**
  String get profileMemberSinceLabel;

  /// No description provided for @deviceDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get deviceDisconnected;

  /// No description provided for @deviceConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get deviceConnecting;

  /// No description provided for @deviceSearchingRadiaCode.
  ///
  /// In en, this message translates to:
  /// **'Searching for RadiaCode devices...'**
  String get deviceSearchingRadiaCode;

  /// No description provided for @deviceNoRadiaCodeDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No RadiaCode devices found\nTap the scan button to start'**
  String get deviceNoRadiaCodeDevicesFound;

  /// No description provided for @deviceUnknownDevice.
  ///
  /// In en, this message translates to:
  /// **'Unknown device'**
  String get deviceUnknownDevice;

  /// No description provided for @deviceListId.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String deviceListId(String id);

  /// No description provided for @deviceListRssi.
  ///
  /// In en, this message translates to:
  /// **'RSSI: {rssi} dBm'**
  String deviceListRssi(int rssi);

  /// No description provided for @deviceConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get deviceConnect;

  /// No description provided for @deviceStartScan.
  ///
  /// In en, this message translates to:
  /// **'Start Scan'**
  String get deviceStartScan;

  /// No description provided for @deviceStopScan.
  ///
  /// In en, this message translates to:
  /// **'Stop Scan'**
  String get deviceStopScan;

  /// No description provided for @deviceDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get deviceDisconnect;

  /// No description provided for @deviceDisconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting…'**
  String get deviceDisconnecting;

  /// No description provided for @deviceDisconnectDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect device?'**
  String get deviceDisconnectDialogTitle;

  /// No description provided for @deviceDisconnectDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This will stop live readings and end the Bluetooth connection.'**
  String get deviceDisconnectDialogBody;

  /// No description provided for @deviceMuteGeiger.
  ///
  /// In en, this message translates to:
  /// **'Mute Geiger'**
  String get deviceMuteGeiger;

  /// No description provided for @deviceUnmuteGeiger.
  ///
  /// In en, this message translates to:
  /// **'Unmute Geiger'**
  String get deviceUnmuteGeiger;

  /// No description provided for @deviceMetricCps.
  ///
  /// In en, this message translates to:
  /// **'CPS'**
  String get deviceMetricCps;

  /// No description provided for @deviceMetricDoseRate.
  ///
  /// In en, this message translates to:
  /// **'Dose Rate'**
  String get deviceMetricDoseRate;

  /// No description provided for @deviceGpsAccuracy.
  ///
  /// In en, this message translates to:
  /// **'GPS Accuracy: {meters} m'**
  String deviceGpsAccuracy(String meters);

  /// No description provided for @trackingNeedLogin.
  ///
  /// In en, this message translates to:
  /// **'You need to log in to track'**
  String get trackingNeedLogin;

  /// No description provided for @trackingHighPrecisionOk.
  ///
  /// In en, this message translates to:
  /// **'High precision OK'**
  String get trackingHighPrecisionOk;

  /// No description provided for @trackingNeedAccuracyToRecord.
  ///
  /// In en, this message translates to:
  /// **'Need ≤ {meters} m to record'**
  String trackingNeedAccuracyToRecord(String meters);

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @trackingStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Track • Recording'**
  String get trackingStatusRecording;

  /// No description provided for @trackingStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Track • Paused'**
  String get trackingStatusPaused;

  /// No description provided for @trackingTrack.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get trackingTrack;

  /// No description provided for @deviceGettingHighAccuracyGpsFix.
  ///
  /// In en, this message translates to:
  /// **'Getting high-accuracy GPS fix...'**
  String get deviceGettingHighAccuracyGpsFix;

  /// No description provided for @deviceSnackConnectedReady.
  ///
  /// In en, this message translates to:
  /// **'RadiaCode connected and ready!'**
  String get deviceSnackConnectedReady;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'Open-red is a project arising from an agreement between the Consejo de Seguridad Nuclear and the Ibercivis Foundation. The project also involves the Universitat Politècnica de Catalunya, the University of Zaragoza, the University of Cantabria and the Centro de Investigaciones Energéticas, Medioambientales y Tecnológicas. For more information, follow the links below.'**
  String get aboutBody;

  /// No description provided for @aboutProjectWebpage.
  ///
  /// In en, this message translates to:
  /// **'Project webpage'**
  String get aboutProjectWebpage;

  /// No description provided for @aboutProjectMap.
  ///
  /// In en, this message translates to:
  /// **'Project map'**
  String get aboutProjectMap;

  /// No description provided for @aboutCommunityTelegram.
  ///
  /// In en, this message translates to:
  /// **'Community (Telegram)'**
  String get aboutCommunityTelegram;

  /// No description provided for @aboutDevelopedBy.
  ///
  /// In en, this message translates to:
  /// **'Developed by Ibercivis'**
  String get aboutDevelopedBy;

  /// No description provided for @aboutOpenUrlFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open: {url}'**
  String aboutOpenUrlFailed(String url);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
