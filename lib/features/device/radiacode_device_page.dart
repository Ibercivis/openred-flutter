import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../../api_service.dart';
import '../../dose_color.dart';
import '../../l10n/app_localizations.dart';
import '../../models/recorded_track_point.dart';
import '../../radiacode_service.dart';
import '../../recording_foreground_task.dart';
import '../../devices/core/device_session.dart';

class RadiacodeDevicePage extends StatefulWidget {
  const RadiacodeDevicePage({
    super.key,
    required this.device,
    this.activeTabIndex,
    this.tabIndex,
  });

  final BluetoothDevice device;
  final ValueListenable<int>? activeTabIndex;
  final int? tabIndex;

  @override
  State<RadiacodeDevicePage> createState() => _RadiacodeDevicePageState();
}

class _RadiacodeDevicePageState extends State<RadiacodeDevicePage>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  String? _lastAuthTokenForTracking;
  bool _isLoggedInForTracking = false;
  bool _trackingAuthCheckInFlight = false;

  BluetoothDevice? connectedDevice;
  String statusMessage = 'Ready';

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _autoReconnectEnabled = true;

  geo.Position? _currentPosition;
  MapboxMap? _deviceMap;
  Point? _deviceMapInitialCenter;
  CircleAnnotationManager? _deviceTrackPointManager;

  static const double _deviceMapDefaultZoom = 14.0;
  static const double _deviceMapNavPitch = 45.0;

  static const double _requiredGpsAccuracyMeters = 10.0;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _autoPausedDueToGps = false;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;
  final List<RadiationTrackPoint> _recordedPoints = [];
  bool _deviceMapFollowUser = true;
  bool _isDisconnecting = false;

  bool _isConnecting = false;

  bool _geigerMuted = false;
  Timer? _geigerTimer;
  double _geigerTicksPerSecond = 0.0;
  final math.Random _geigerRng = math.Random();
  double _geigerLastPositiveCps = 0.0;
  DateTime? _geigerLastPositiveCpsAt;

  static const double _geigerMaxTicksPerSecond = 25.0;
  static const int _geigerMinIntervalMs = 40;
  static const int _geigerMaxIntervalMs = 30000;
  static const Duration _geigerHoldLastCpsFor = Duration(seconds: 3);

  AnimationController? _recPulseController;
  Animation<double> _recPulse = const AlwaysStoppedAnimation<double>(0.0);

  RadiaCodeService? _radiaCodeService;
  RadiaCodeData? _currentData;
  Timer? _dataUpdateTimer;
  bool _isReadingData = false;
  DateTime? _lastDoseDebugPrint;

  final List<double> _cpsHistory = [];
  final List<double> _doseHistory = [];
  static const int _historyMaxPoints = 40;

  bool get _isActiveTab {
    final active = widget.activeTabIndex;
    final tab = widget.tabIndex;
    if (active == null || tab == null) return true;
    return active.value == tab;
  }

  void _handleActiveTabChanged() {
    if (!_isActiveTab) {
      _deviceMap = null;
      _deviceTrackPointManager = null;
      return;
    }

    // If we come back to the Device tab and we're not connected, try to recover.
    if (_autoReconnectEnabled && connectedDevice == null) {
      _scheduleReconnect(immediate: true);
    }
  }

  @override
  void initState() {
    super.initState();

    widget.activeTabIndex?.addListener(_handleActiveTabChanged);

    _connectionStateSubscription = widget.device.connectionState.listen(
      _handleConnectionStateChanged,
    );

    _recPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _recPulse = CurvedAnimation(
      parent: _recPulseController!,
      curve: Curves.easeInOut,
    );

    unawaited(_checkBluetoothState());
    unawaited(_startLocationUpdates());
    unawaited(_refreshTrackingAuth(force: true));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_connectToDevice(widget.device));
    });
  }

  void _handleConnectionStateChanged(BluetoothConnectionState state) {
    if (state != BluetoothConnectionState.disconnected) return;
    if (_isDisconnecting) return;

    // If we thought we were connected, treat this as an unexpected disconnect.
    if (connectedDevice == null && _radiaCodeService == null) return;

    _handleUnexpectedDisconnect();
  }

  void _handleUnexpectedDisconnect() {
    _dataUpdateTimer?.cancel();
    _dataUpdateTimer = null;

    _geigerTimer?.cancel();
    _geigerTimer = null;
    _geigerTicksPerSecond = 0.0;

    // If we were recording, stop the session (best-effort).
    if (_isRecording) {
      _stopRecording();
    }

    try {
      unawaited(_radiaCodeService?.disconnect());
    } catch (_) {
      // ignore
    }
    _radiaCodeService = null;

    if (mounted) {
      setState(() {
        connectedDevice = null;
        _currentData = null;
        statusMessage = 'Connection lost. Reconnecting…';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device disconnected. Trying to reconnect…'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      connectedDevice = null;
      _currentData = null;
      statusMessage = 'Connection lost. Reconnecting…';
    }

    _scheduleReconnect(immediate: true);
  }

  void _scheduleReconnect({required bool immediate}) {
    if (!_autoReconnectEnabled) return;
    if (_isDisconnecting || _isConnecting) return;
    if (connectedDevice != null) return;

    _reconnectTimer?.cancel();

    final delay = immediate ? Duration.zero : _reconnectDelayForAttempt(_reconnectAttempt);
    _reconnectTimer = Timer(delay, () {
      if (!_autoReconnectEnabled) return;
      if (_isDisconnecting || _isConnecting) return;
      if (connectedDevice != null) return;

      _reconnectAttempt++;
      unawaited(_connectToDevice(widget.device, isReconnect: true));
    });
  }

  Duration _reconnectDelayForAttempt(int attempt) {
    // Exponential-ish backoff: 1s, 2s, 4s, 8s, 16s, 30s...
    final seconds = (1 << attempt).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  @override
  void dispose() {
    widget.activeTabIndex?.removeListener(_handleActiveTabChanged);
    _connectionStateSubscription?.cancel();
    _reconnectTimer?.cancel();
    _recPulseController?.dispose();
    _dataUpdateTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _recordingTimer?.cancel();
    _geigerTimer?.cancel();

    try {
      unawaited(_radiaCodeService?.disconnect());
    } catch (_) {
      // ignore
    }
    try {
      unawaited(connectedDevice?.disconnect());
    } catch (_) {
      // ignore
    }

    super.dispose();
  }

  int _sampleGeigerIntervalMs(double ticksPerSecond) {
    var u = _geigerRng.nextDouble();
    if (u <= 0) u = 1e-12;
    final seconds = -math.log(u) / ticksPerSecond;
    final ms = (seconds * 1000.0).round();
    if (ms < _geigerMinIntervalMs) return _geigerMinIntervalMs;
    if (ms > _geigerMaxIntervalMs) return _geigerMaxIntervalMs;
    return ms;
  }

  void _stopGeigerTicks() {
    _geigerTimer?.cancel();
    _geigerTimer = null;
    _geigerTicksPerSecond = 0.0;
  }

  void _scheduleNextGeigerTick({bool restart = false}) {
    if (restart) {
      _geigerTimer?.cancel();
      _geigerTimer = null;
    } else {
      if (_geigerTimer != null) return;
    }

    if (connectedDevice == null || _radiaCodeService == null || _geigerMuted) {
      _stopGeigerTicks();
      return;
    }

    final tps = _geigerTicksPerSecond;
    if (!tps.isFinite || tps <= 0.0) {
      _stopGeigerTicks();
      return;
    }

    final delayMs = _sampleGeigerIntervalMs(tps);
    _geigerTimer = Timer(
      Duration(milliseconds: delayMs),
      () {
        _geigerTimer = null;
        if (connectedDevice == null || _radiaCodeService == null || _geigerMuted) {
          _stopGeigerTicks();
          return;
        }
        SystemSound.play(SystemSoundType.click);
        _scheduleNextGeigerTick();
      },
    );
  }

  Future<void> _refreshTrackingAuth({bool force = false}) async {
    if (_trackingAuthCheckInFlight) return;
    _trackingAuthCheckInFlight = true;

    try {
      final token = await _apiService.getToken();
      if (!force && token == _lastAuthTokenForTracking) return;
      _lastAuthTokenForTracking = token;

      if (token == null || token.isEmpty) {
        if (mounted && _isLoggedInForTracking) {
          setState(() => _isLoggedInForTracking = false);
        } else {
          _isLoggedInForTracking = false;
        }
        return;
      }

      final userId = await _apiService.getCurrentUserId();
      final ok = userId != null;
      if (mounted && ok != _isLoggedInForTracking) {
        setState(() => _isLoggedInForTracking = ok);
      } else {
        _isLoggedInForTracking = ok;
      }
    } finally {
      _trackingAuthCheckInFlight = false;
    }
  }

  void _setRecPulseActive(bool active) {
    final controller = _recPulseController;
    if (controller == null) return;

    if (active) {
      if (!controller.isAnimating) {
        controller.repeat(reverse: true);
      }
      return;
    }

    if (controller.isAnimating) {
      controller.stop();
    }
    controller.value = 0.0;
  }

  Future<void> _confirmAndDiscardStoppedRecording() async {
    if (_isRecording) return;
    if (_recordedPoints.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard track?'),
          content: const Text('This will delete the recorded points from this session.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _discardStoppedRecording();
    }
  }

  void _updateGeigerTickRate(double cps) {
    if (connectedDevice == null || _radiaCodeService == null || _geigerMuted) {
      _stopGeigerTicks();
      return;
    }

    final now = DateTime.now();
    double effectiveCps = cps;

    if (effectiveCps.isFinite && effectiveCps > 0) {
      _geigerLastPositiveCps = effectiveCps;
      _geigerLastPositiveCpsAt = now;
    } else {
      final lastAt = _geigerLastPositiveCpsAt;
      final shouldHold =
          lastAt != null && now.difference(lastAt) <= _geigerHoldLastCpsFor;
      if (shouldHold && _geigerLastPositiveCps.isFinite && _geigerLastPositiveCps > 0) {
        effectiveCps = _geigerLastPositiveCps;
      } else {
        _stopGeigerTicks();
        return;
      }
    }

    final ticksPerSecond =
        (effectiveCps / 2.0).clamp(0.0, _geigerMaxTicksPerSecond);
    if (ticksPerSecond < 0.2) {
      _stopGeigerTicks();
      return;
    }

    final previous = _geigerTicksPerSecond;
    _geigerTicksPerSecond = ticksPerSecond;

    final shouldRestart = _geigerTimer == null ||
        previous <= 0.0 ||
        (previous - ticksPerSecond).abs() / previous > 0.25;
    _scheduleNextGeigerTick(restart: shouldRestart);
  }

  Future<bool> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.deviceDisconnectDialogTitle),
          content: Text(l10n.deviceDisconnectDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.deviceDisconnect),
            ),
          ],
        );
      },
    );

    return ok ?? false;
  }

  Future<bool> _ensureHighAccuracyLocationReady() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> _startLocationUpdates() async {
    if (_positionSubscription != null) return;

    final ok = await _ensureHighAccuracyLocationReady();
    if (!ok) return;

    final settings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _positionSubscription =
        geo.Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      _currentPosition = pos;

      _deviceMapInitialCenter ??=
          Point(coordinates: Position(pos.longitude, pos.latitude));

      if (_deviceMap != null && connectedDevice != null && _deviceMapFollowUser) {
        unawaited(_followDeviceMapTo(pos));
      }

      if (_isRecording && !_isPaused && !_gpsIsPreciseEnough()) {
        _autoPauseDueToGps();
      }

      if (_isRecording && _isPaused && _autoPausedDueToGps && _gpsIsPreciseEnough()) {
        _resumeRecording();
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  void _autoPauseDueToGps() {
    if (_autoPausedDueToGps) return;
    _autoPausedDueToGps = true;
    _pauseRecording();

    if (!mounted) return;
    final acc = _currentPosition?.accuracy;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Auto-paused: GPS accuracy ${acc == null ? '--' : acc.toStringAsFixed(1)} m (need ≤ ${_requiredGpsAccuracyMeters.toStringAsFixed(0)} m)',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _followDeviceMapTo(geo.Position pos) async {
    final map = _deviceMap;
    if (map == null) return;

    unawaited(
      map.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          pitch: _deviceMapNavPitch,
        ),
      ),
    );
  }

  Future<void> _enableDeviceMapUserLocation() async {
    final map = _deviceMap;
    if (map == null) return;

    try {
      await map.attribution.updateSettings(AttributionSettings(enabled: false));
      await map.logo.updateSettings(LogoSettings(enabled: false));
      await map.compass.updateSettings(CompassSettings(enabled: false));
      await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));

      await map.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: true,
        ),
      );

      await map.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
        ),
      );
    } catch (e) {
      debugPrint('Failed to enable location puck: $e');
    }
  }

  Future<void> _centerDeviceMapOnCurrentPosition() async {
    final map = _deviceMap;
    final pos = _currentPosition;
    if (map == null || pos == null) return;

    try {
      final cameraState = await map.getCameraState();
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: cameraState.zoom,
          bearing: cameraState.bearing,
          pitch: cameraState.pitch,
        ),
        MapAnimationOptions(duration: 600),
      );
    } catch (_) {
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: _deviceMapDefaultZoom,
        ),
        MapAnimationOptions(duration: 600),
      );
    }
  }

  Future<void> _addDeviceBreadcrumbPoint(
    geo.Position pos, {
    double? doseMicroSvPerHour,
  }) async {
    final map = _deviceMap;
    if (map == null) return;

    _deviceTrackPointManager ??= await map.annotations.createCircleAnnotationManager();

    await _deviceTrackPointManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(pos.longitude, pos.latitude)),
        circleRadius: 4.0,
        circleColor: doseRateToArgb(doseMicroSvPerHour),
        circleOpacity: 0.9,
      ),
    );
  }

  bool _gpsIsPreciseEnough() {
    final acc = _currentPosition?.accuracy;
    if (acc == null) return false;
    return acc > 0 && acc <= _requiredGpsAccuracyMeters;
  }

  Future<void> _startRecordingForegroundService() async {
    if (!Platform.isAndroid) return;

    try {
      final NotificationPermission notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Grabando',
          notificationText: 'Seguimiento GPS activo',
        );
        return;
      }

      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Grabando',
        notificationText: 'Seguimiento GPS activo',
        callback: recordingForegroundStartCallback,
      );
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
    }
  }

  Future<void> _stopRecordingForegroundService() async {
    if (!Platform.isAndroid) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('Failed to stop foreground service: $e');
    }
  }

  Future<void> _startRecording() async {
    final isLoggedIn = await _apiService.isLoggedIn();
    if (!mounted) return;
    if (!isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Necesitas iniciar sesión para trackear.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final userId = await _apiService.getCurrentUserId();
    if (!mounted) return;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener tu usuario. Intenta iniciar sesión de nuevo.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_gpsIsPreciseEnough()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPS not precise enough. Need ≤ ${_requiredGpsAccuracyMeters.toStringAsFixed(0)} m.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No GPS fix yet.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _deviceMapFollowUser = true;
    unawaited(_startLocationUpdates());

    _recordedPoints.clear();
    _isRecording = true;
    _isPaused = false;
    _autoPausedDueToGps = false;
    _recordingStartedAt = DateTime.now();

    _setRecPulseActive(true);

    unawaited(_deviceTrackPointManager?.deleteAll());

    _startRecordingTimer();
    unawaited(_startRecordingForegroundService());

    if (mounted) setState(() {});
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final pos = _currentPosition;
      if (pos == null) return;

      final data = _currentData;

      final cpm = data?.cpm;
      final cpmRelErr = data?.cpmErr;
      final dose = data?.doseMicroSvPerHour;
      final doseRelErr = data?.doseMicroSvPerHourErr;

      _recordedPoints.add(
        RadiationTrackPoint(
          timestamp: DateTime.now(),
          latitude: pos.latitude,
          longitude: pos.longitude,
          altitude: pos.altitude,
          accuracyMeters: pos.accuracy,
          cpm: cpm,
          cpmRelErr: cpmRelErr,
          doseMicroSvPerHour: dose,
          doseMicroSvPerHourRelErr: doseRelErr,
        ),
      );

      unawaited(_addDeviceBreadcrumbPoint(pos, doseMicroSvPerHour: dose));

      if (mounted) {
        setState(() {});
      }
    });
  }

  void _pauseRecording() {
    if (!_isRecording || _isPaused) return;
    _isPaused = true;
    _setRecPulseActive(false);
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (mounted) setState(() {});
  }

  void _resumeRecording() {
    if (!_isRecording || !_isPaused) return;

    if (!_gpsIsPreciseEnough()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPS not precise enough. Need ≤ ${_requiredGpsAccuracyMeters.toStringAsFixed(0)} m.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _isPaused = false;
    _autoPausedDueToGps = false;
    _setRecPulseActive(true);
    _startRecordingTimer();
    if (mounted) setState(() {});
  }

  void _stopRecording() {
    if (!_isRecording) return;
    _isRecording = false;
    _isPaused = false;
    _autoPausedDueToGps = false;
    _setRecPulseActive(false);
    _recordingTimer?.cancel();
    _recordingTimer = null;

    unawaited(_stopRecordingForegroundService());
    if (mounted) setState(() {});
  }

  Future<void> _discardStoppedRecording() async {
    if (_isRecording) return;
    if (_recordedPoints.isEmpty) return;

    _recordedPoints.clear();
    _recordingStartedAt = null;
    _setRecPulseActive(false);

    try {
      await _deviceTrackPointManager?.deleteAll();
    } catch (_) {
      // ignore
    }

    if (mounted) setState(() {});
  }

  Future<void> _promptAndSaveRecording() async {
    if (_isRecording) return;
    if (_recordedPoints.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No points recorded.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final meta = await _askTrackMeta();
    if (meta == null) return;

    final saved = await _saveRecordingToJson(
      trackName: meta.name,
      description: meta.description,
    );
    if (!saved) {
      if (mounted) setState(() {});
      return;
    }

    await _discardStoppedRecording();
  }

  Future<_TrackSaveMeta?> _askTrackMeta() async {
    final result = await showDialog<_TrackSaveMeta>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _TrackNameDialog();
      },
    );
    return result;
  }

  String _sanitizeFilenamePart(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'track';

    final safe = trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (safe.isEmpty) return 'track';
    return safe.length > 48 ? safe.substring(0, 48) : safe;
  }

  Future<bool> _saveRecordingToJson({
    required String trackName,
    required String description,
  }) async {
    if (_recordedPoints.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No points recorded.'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    try {
      final isLoggedIn = await _apiService.isLoggedIn();
      if (!isLoggedIn) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login required to save tracks.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      final userId = await _apiService.getCurrentUserId();
      if (userId == null) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to fetch user profile. Try logging in again.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      final dir = await getApplicationDocumentsDirectory();
      final tracksDir = Directory('${dir.path}/tracks/$userId');
      if (!await tracksDir.exists()) {
        await tracksDir.create(recursive: true);
      }

      final startedAt = _recordingStartedAt ?? _recordedPoints.first.timestamp;
      final endedAt = _recordedPoints.last.timestamp;

      final safeName = startedAt.toUtc().toIso8601String().replaceAll(':', '-');
      final safeTrackName = _sanitizeFilenamePart(trackName);
      final file = File('${tracksDir.path}/track_${safeName}_$safeTrackName.json');

      final payload = {
        'trackType': 'radiation',
        'name': trackName,
        'description': description,
        'synced': false,
        'syncedAt': null,
        'cloudTrackId': null,
        'device': {
          'name': connectedDevice?.platformName,
          'id': connectedDevice?.remoteId.toString(),
        },
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'requiredGpsAccuracyMeters': _requiredGpsAccuracyMeters,
        'points': _recordedPoints.map((p) => p.toJson()).toList(),
      };

      await file.writeAsString(jsonEncode(payload));

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved track: ${file.path.split('/').last}'),
          backgroundColor: Colors.green,
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save track: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _checkBluetoothState() async {
    if (await FlutterBluePlus.isSupported == false) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'Bluetooth not supported by this device';
      });
      return;
    }

    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        statusMessage = state == BluetoothAdapterState.on
            ? 'Bluetooth is ON'
            : 'Please turn on Bluetooth';
      });
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device, {bool isReconnect = false}) async {
    if (_isConnecting) return;
    try {
      if (!mounted) return;
      setState(() {
        _isConnecting = true;
        statusMessage = isReconnect
            ? 'Reconnecting to ${device.platformName}...'
            : 'Connecting to ${device.platformName}...';
      });

      _dataUpdateTimer?.cancel();
      _dataUpdateTimer = null;

      try {
        await _radiaCodeService?.disconnect();
      } catch (_) {
        // ignore
      }

      _radiaCodeService = RadiaCodeService();
      final connected = await _radiaCodeService!.connect(device);

      if (connected) {
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        if (!mounted) return;
        setState(() {
          connectedDevice = device;
          statusMessage = 'Connected to ${device.platformName}';
        });

        _startDataReading();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).deviceSnackConnectedReady),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (!mounted) return;
        setState(() {
          statusMessage = 'Failed to initialize RadiaCode protocol';
        });

        // Keep trying in the background.
        _scheduleReconnect(immediate: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'Connection error: $e';
      });

      _scheduleReconnect(immediate: false);
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _startDataReading() {
    _dataUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isReadingData || _radiaCodeService == null) return;

      _isReadingData = true;
      try {
        final data = await _radiaCodeService!.readData();

        final now = DateTime.now();
        final last = _lastDoseDebugPrint;
        if (last == null || now.difference(last).inSeconds >= 10) {
          _lastDoseDebugPrint = now;
          // ignore: avoid_print
          print(
            '[DoseDebug] rawDose=${data.doseRate} rawUnit=${data.rawDoseUnit} unitsFlag=${data.measurementUnits.name} -> microSvPerHour=${data.doseMicroSvPerHour} ±${data.doseMicroSvPerHourErr} cps=${data.cps} ±${data.cpsErr}',
          );
        }

        if (mounted) {
          _updateGeigerTickRate(data.cps ?? 0.0);

          setState(() {
            _currentData = data;

            final cps = data.cps;
            if (cps != null && cps.isFinite) {
              _cpsHistory.add(cps);
              if (_cpsHistory.length > _historyMaxPoints) {
                _cpsHistory.removeRange(0, _cpsHistory.length - _historyMaxPoints);
              }
            }

            final dose = data.doseMicroSvPerHour;
            if (dose != null && dose.isFinite) {
              _doseHistory.add(dose);
              if (_doseHistory.length > _historyMaxPoints) {
                _doseHistory.removeRange(0, _doseHistory.length - _historyMaxPoints);
              }
            }
          });
        }
      } catch (e) {
        // ignore: avoid_print
        print('Error reading RadiaCode data: $e');
      } finally {
        _isReadingData = false;
      }
    });
  }

  Future<void> _disconnectDevice() async {
    if (_isDisconnecting) return;
    if (!mounted) return;
    setState(() {
      _isDisconnecting = true;
    });

    _dataUpdateTimer?.cancel();
    _dataUpdateTimer = null;

    _geigerTimer?.cancel();
    _geigerTimer = null;

    try {
      if (_radiaCodeService != null) {
        await _radiaCodeService!.disconnect();
        _radiaCodeService = null;
      }

      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
      }

      if (!mounted) return;
      setState(() {
        connectedDevice = null;
        _currentData = null;
        statusMessage = 'Disconnected';
      });

      deviceSession.clear();
    } finally {
      if (mounted) {
        setState(() {
          _isDisconnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isConnected = connectedDevice != null;

    Widget buildSparkline(List<double> values, Color color) {
      return SizedBox(
        height: 34,
        child: CustomPaint(
          painter: _SparklinePainter(values: values, color: color),
        ),
      );
    }

    Widget buildMetricTile({
      required String label,
      required String unit,
      required double value,
      double? error,
      bool errorIsPercent = false,
      double errorScale = 1.0,
      int? errorFractionDigits,
      required double min,
      required double max,
      required Color accent,
      required List<double> history,
      int fractionDigits = 0,
    }) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final textTheme = theme.textTheme;

      final safeMin = min;
      final safeMax = max;
      final safeValue = value.isFinite ? value : safeMin;
      final safeError = (error != null && error.isFinite && error >= 0) ? error : null;
      final effectiveErrorDigits = errorFractionDigits ?? (errorIsPercent ? 1 : fractionDigits);
      final clampedValue = safeValue.clamp(safeMin, safeMax).toDouble();
      final range = (safeMax - safeMin).abs();
      final fraction =
          range <= 0 ? 0.0 : ((clampedValue - safeMin) / range).clamp(0.0, 1.0);

      const double minVisibleFraction = 0.10;
      final visualFraction = (fraction > 0.0 && fraction < minVisibleFraction)
          ? minVisibleFraction
          : fraction;
      final visualValue = range <= 0 ? clampedValue : (safeMin + (visualFraction * range));

      const double gaugeStrokeWidth = 10;

      final cardBg = theme.cardColor;
      final borderColor = colorScheme.outlineVariant;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: SfRadialGauge(
                  axes: [
                    RadialAxis(
                      minimum: min,
                      maximum: max,
                      startAngle: 135,
                      endAngle: 45,
                      canScaleToFit: true,
                      centerX: 0.5,
                      centerY: 0.72,
                      radiusFactor: 1.0,
                      showLabels: false,
                      showTicks: false,
                      axisLineStyle: const AxisLineStyle(
                        thickness: 0,
                        thicknessUnit: GaugeSizeUnit.logicalPixel,
                        color: Colors.transparent,
                        cornerStyle: CornerStyle.bothFlat,
                      ),
                      pointers: [
                        RangePointer(
                          value: max,
                          width: gaugeStrokeWidth,
                          sizeUnit: GaugeSizeUnit.logicalPixel,
                          color: borderColor,
                          cornerStyle: CornerStyle.bothCurve,
                        ),
                        RangePointer(
                          value: visualValue,
                          width: gaugeStrokeWidth,
                          sizeUnit: GaugeSizeUnit.logicalPixel,
                          color: accent.withOpacity(0.9),
                          cornerStyle: CornerStyle.bothCurve,
                        ),
                      ],
                      annotations: [
                        GaugeAnnotation(
                          angle: 90,
                          positionFactor: 0.12,
                          widget: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                safeValue.toStringAsFixed(fractionDigits),
                                style: textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              if (safeError != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  errorIsPercent
                                      ? '±${(safeError * errorScale).toStringAsFixed(effectiveErrorDigits)}%'
                                      : '±${safeError.toStringAsFixed(effectiveErrorDigits)}',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                unit,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            buildSparkline(history, accent),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle),
            Text(
              isConnected
                  ? (connectedDevice!.platformName.isNotEmpty
                      ? connectedDevice!.platformName
                      : connectedDevice!.remoteId.toString())
                  : (_isConnecting ? l10n.deviceConnecting : l10n.deviceDisconnected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: isConnected
            ? [
                IconButton(
                  tooltip: _geigerMuted ? l10n.deviceUnmuteGeiger : l10n.deviceMuteGeiger,
                  onPressed: () {
                    setState(() {
                      _geigerMuted = !_geigerMuted;
                    });
                    _updateGeigerTickRate(_currentData?.cps ?? 0.0);
                  },
                  icon: Icon(
                    _geigerMuted ? Icons.volume_off : Icons.volume_up,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ElevatedButton.icon(
                    onPressed: _isDisconnecting
                        ? null
                        : () async {
                            final ok = await _confirmDisconnect();
                            if (!ok) return;
                            await _disconnectDevice();
                          },
                    icon: _isDisconnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.bluetooth_disabled),
                    label: Text(
                      _isDisconnecting ? l10n.deviceDisconnecting : l10n.deviceDisconnect,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: isConnected
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 210,
                        child: Row(
                          children: [
                            Expanded(
                              child: buildMetricTile(
                                label: l10n.deviceMetricCps,
                                unit: 'cps',
                                value: _currentData?.cps ?? 0.0,
                                error: _currentData?.cpsErr,
                                errorIsPercent: true,
                                errorScale: 100.0,
                                errorFractionDigits: 1,
                                min: 0,
                                max: 50,
                                accent: Colors.lightBlueAccent,
                                history: _cpsHistory,
                                fractionDigits: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: buildMetricTile(
                                label: l10n.deviceMetricDoseRate,
                                unit: 'µSv/h',
                                value: _currentData?.doseMicroSvPerHour ?? 0.0,
                                error: _currentData?.doseMicroSvPerHourErr,
                                errorIsPercent: true,
                                errorScale: 100.0,
                                errorFractionDigits: 1,
                                min: 0,
                                max: 2.0,
                                accent: Colors.orangeAccent,
                                history: _doseHistory,
                                fractionDigits: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.deviceGpsAccuracy(
                                _currentPosition == null
                                    ? '--'
                                    : _currentPosition!.accuracy.toStringAsFixed(1),
                              ),
                              style: TextStyle(
                                color: _gpsIsPreciseEnough()
                                    ? Colors.green.shade800
                                    : Colors.orange.shade800,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              !_isLoggedInForTracking
                                  ? l10n.trackingNeedLogin
                                  : (_gpsIsPreciseEnough()
                                      ? l10n.trackingHighPrecisionOk
                                      : l10n.trackingNeedAccuracyToRecord(
                                          _requiredGpsAccuracyMeters.toStringAsFixed(0),
                                        )),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Builder(
                              builder: (context) {
                                final hasStoppedSession =
                                    !_isRecording && _recordedPoints.isNotEmpty;
                                final isActivelyRecording = _isRecording && !_isPaused;

                                if (hasStoppedSession) {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _confirmAndDiscardStoppedRecording,
                                          icon: const Icon(Icons.delete_outline),
                                          label: Text(l10n.discard),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _promptAndSaveRecording,
                                          icon: const Icon(Icons.save),
                                          label: Text(l10n.save),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                if (_isRecording) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AnimatedBuilder(
                                        animation: _recPulse,
                                        builder: (context, _) {
                                          final dotScale = isActivelyRecording
                                              ? (1.0 + (_recPulse.value * 0.25))
                                              : 1.0;
                                          final dotOpacity = isActivelyRecording
                                              ? (0.6 + (_recPulse.value * 0.4))
                                              : 0.35;

                                          return Row(
                                            children: [
                                              Transform.scale(
                                                scale: dotScale,
                                                child: Opacity(
                                                  opacity: dotOpacity,
                                                  child: Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration: BoxDecoration(
                                                      color: Colors.redAccent,
                                                      borderRadius: BorderRadius.circular(99),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                isActivelyRecording
                                                    ? l10n.trackingStatusRecording
                                                    : l10n.trackingStatusPaused,
                                                style: TextStyle(
                                                  color: isActivelyRecording
                                                      ? Theme.of(context).colorScheme.onSurface
                                                      : Colors.orange.shade700,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _isPaused
                                                  ? _resumeRecording
                                                  : _pauseRecording,
                                              icon: Icon(
                                                _isPaused ? Icons.play_arrow : Icons.pause,
                                              ),
                                              label: Text(
                                                _isPaused ? l10n.resume : l10n.pause,
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _isPaused
                                                    ? Colors.orangeAccent
                                                    : Colors.orange.shade700,
                                                foregroundColor: Colors.black,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _stopRecording,
                                              icon: const Icon(Icons.stop),
                                              label: Text(l10n.stop),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.redAccent,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                }

                                return SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoggedInForTracking
                                        ? () => unawaited(_startRecording())
                                        : null,
                                    icon: const Icon(Icons.fiber_manual_record),
                                    label: Text(
                                      l10n.trackingTrack,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _currentPosition == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.deviceGettingHighAccuracyGpsFix,
                                  ),
                                ],
                              ),
                            )
                          : Stack(
                              children: [
                                if (widget.activeTabIndex != null && widget.tabIndex != null)
                                  ValueListenableBuilder<int>(
                                    valueListenable: widget.activeTabIndex!,
                                    builder: (context, idx, _) {
                                      if (idx != widget.tabIndex) {
                                        return const SizedBox.expand();
                                      }

                                      final styleUri = Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? MapboxStyles.DARK
                                          : MapboxStyles.LIGHT;

                                      return MapWidget(
                                            key: ValueKey('device_map_$styleUri'),
                                        cameraOptions: CameraOptions(
                                          center: _deviceMapInitialCenter ??
                                              Point(
                                                coordinates: Position(
                                                  _currentPosition!.longitude,
                                                  _currentPosition!.latitude,
                                                ),
                                              ),
                                          zoom: _deviceMapDefaultZoom,
                                        ),
                                        styleUri: styleUri,
                                        gestureRecognizers: {
                                          Factory<OneSequenceGestureRecognizer>(
                                            () => EagerGestureRecognizer(),
                                          ),
                                        },
                                        onScrollListener: (_) {
                                          _deviceMapFollowUser = false;
                                        },
                                        onMapCreated: (mapboxMap) {
                                          _deviceMap = mapboxMap;
                                          unawaited(_enableDeviceMapUserLocation());
                                          unawaited(_centerDeviceMapOnCurrentPosition());
                                        },
                                      );
                                    },
                                  )
                                else
                                  Builder(
                                    builder: (context) {
                                      final styleUri = Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? MapboxStyles.DARK
                                          : MapboxStyles.LIGHT;

                                      return MapWidget(
                                        key: ValueKey('device_map_$styleUri'),
                                        cameraOptions: CameraOptions(
                                          center: _deviceMapInitialCenter ??
                                              Point(
                                                coordinates: Position(
                                                  _currentPosition!.longitude,
                                                  _currentPosition!.latitude,
                                                ),
                                              ),
                                          zoom: _deviceMapDefaultZoom,
                                        ),
                                        styleUri: styleUri,
                                        gestureRecognizers: {
                                          Factory<OneSequenceGestureRecognizer>(
                                            () => EagerGestureRecognizer(),
                                          ),
                                        },
                                        onScrollListener: (_) {
                                          _deviceMapFollowUser = false;
                                        },
                                        onMapCreated: (mapboxMap) {
                                          _deviceMap = mapboxMap;
                                          unawaited(_enableDeviceMapUserLocation());
                                          unawaited(_centerDeviceMapOnCurrentPosition());
                                        },
                                      );
                                    },
                                  ),
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: FloatingActionButton(
                                    heroTag: 'device_map_center_btn',
                                    backgroundColor: Colors.green.shade400,
                                    foregroundColor: Colors.black,
                                    onPressed: () {
                                      _deviceMapFollowUser = true;
                                      _centerDeviceMapOnCurrentPosition();
                                    },
                                    child: const Icon(Icons.my_location),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({
    required this.values,
    required this.color,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (values.length < 2) return;

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs();
    final safeRange = range < 1e-9 ? 1.0 : range;

    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final t = (values[i] - minVal) / safeRange;
      final x = dx * i;
      final y = size.height - (t * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true
      ..color = color.withOpacity(0.9);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _TrackNameDialog extends StatefulWidget {
  const _TrackNameDialog();

  @override
  State<_TrackNameDialog> createState() => _TrackNameDialogState();
}

class _TrackSaveMeta {
  final String name;
  final String description;

  const _TrackSaveMeta({
    required this.name,
    required this.description,
  });
}

class _TrackNameDialogState extends State<_TrackNameDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save track'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Track name',
                hintText: 'e.g. City center walk',
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Please enter a name';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional notes…',
              ),
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(
              _TrackSaveMeta(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
