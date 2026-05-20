import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../api_service.dart';
import '../../devices/core/device_session.dart';
import '../../devices/opple/opple_lm3_service.dart';
import '../../l10n/app_localizations.dart';
import '../../lux_color.dart';
import '../../marna_layer.dart';
import '../../models/recorded_track_point.dart';
import '../../recording_foreground_task.dart';

class OppleLm3DevicePage extends StatefulWidget {
  const OppleLm3DevicePage({
    super.key,
    required this.device,
    this.activeTabIndex,
    this.tabIndex,
  });

  final BluetoothDevice device;
  final ValueListenable<int>? activeTabIndex;
  final int? tabIndex;

  @override
  State<OppleLm3DevicePage> createState() => _OppleLm3DevicePageState();
}

class _OppleLm3DevicePageState extends State<OppleLm3DevicePage>
  with SingleTickerProviderStateMixin {
  final OppleLm3Service _service = OppleLm3Service();
  final ApiService _apiService = ApiService();

  static const double _requiredGpsAccuracyMeters = 10.0;
  static const double _deviceMapDefaultZoom = 14.0;
  static const double _deviceMapNavPitch = 45.0;

  StreamSubscription<OppleLm3Measurement>? _sub;
  OppleLm3Measurement? _latest;

  geo.Position? _currentPosition;
  StreamSubscription<geo.Position>? _positionSubscription;

  MapboxMap? _deviceMap;
  Point? _deviceMapInitialCenter;
  CircleAnnotationManager? _deviceTrackPointManager;
  bool _deviceMapFollowUser = true;

  bool _marnaEnabled = false;

  bool _isRecording = false;
  bool _isPaused = false;
  bool _autoPausedDueToGps = false;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;
  final List<LightTrackPoint> _recordedPoints = <LightTrackPoint>[];

  AnimationController? _recPulseController;
  Animation<double> _recPulse = const AlwaysStoppedAnimation<double>(0.0);

  String? _lastAuthTokenForTracking;
  bool _isLoggedInForTracking = false;
  bool _trackingAuthCheckInFlight = false;

  bool _isConnecting = true;
  String _status = 'Connecting...';

  bool get _isActiveTab {
    final active = widget.activeTabIndex;
    final tab = widget.tabIndex;
    if (active == null || tab == null) return true;
    return active.value == tab;
  }

  void _handleActiveTabChanged() {
    if (!_isActiveTab) return;
    unawaited(_refreshTrackingAuth());
  }

  @override
  void initState() {
    super.initState();
    _recPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _recPulse = CurvedAnimation(
      parent: _recPulseController!,
      curve: Curves.easeInOut,
    );

    widget.activeTabIndex?.addListener(_handleActiveTabChanged);
    unawaited(_startLocationUpdates());
    unawaited(_refreshTrackingAuth(force: true));
    _connectAndStart();
  }

  @override
  void dispose() {
    widget.activeTabIndex?.removeListener(_handleActiveTabChanged);

    _recordingTimer?.cancel();
    _recordingTimer = null;

    _positionSubscription?.cancel();
    _positionSubscription = null;

    _recPulseController?.dispose();

    _deviceMap = null;
    _deviceTrackPointManager = null;

    unawaited(_stopRecordingForegroundService());

    _sub?.cancel();
    _service.disconnect();
    super.dispose();
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

  Future<bool> _ensureHighAccuracyLocationReady({bool requireBackground = false}) async {
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

    if (requireBackground && Platform.isAndroid) {
      if (permission == geo.LocationPermission.whileInUse) {
        final requested = await geo.Geolocator.requestPermission();
        permission = requested;
      }

      if (permission != geo.LocationPermission.always) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Activa "Permitir siempre" en ubicación para trackear en segundo plano.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await geo.Geolocator.openAppSettings();
        return false;
      }
    }

    return true;
  }

  Future<void> _startLocationUpdates({bool skipPermissionCheck = false}) async {
    if (_positionSubscription != null) return;

    if (!skipPermissionCheck) {
      final ok = await _ensureHighAccuracyLocationReady();
      if (!ok) return;
    }

    // Configuración específica para Android que evita que el GPS se suspenda
    final settings = Platform.isAndroid
        ? geo.AndroidSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            forceLocationManager: true, // Evita suspensión en modo Doze
            intervalDuration: const Duration(seconds: 5), // Fuerza actualizaciones cada 5s
            // CRÍTICO: ForegroundNotificationConfig mantiene servicio GPS activo
            foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
              notificationText: 'Tracking GPS activo',
              notificationTitle: 'Open-red GPS',
              enableWakeLock: true,
            ),
          )
        : geo.LocationSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          );

    _positionSubscription =
        geo.Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      _currentPosition = pos;

      _deviceMapInitialCenter ??=
          Point(coordinates: Position(pos.longitude, pos.latitude));

      if (_deviceMap != null && _deviceMapFollowUser) {
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
    double? lux,
  }) async {
    final map = _deviceMap;
    if (map == null) return;

    _deviceTrackPointManager ??= await map.annotations.createCircleAnnotationManager();

    await _deviceTrackPointManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(pos.longitude, pos.latitude)),
        circleRadius: 4.0,
        circleColor: luxToArgb(lux),
        circleOpacity: 0.9,
      ),
    );
  }

  Future<void> _repopulateMapTrackPoints() async {
    final map = _deviceMap;
    if (map == null || _recordedPoints.isEmpty) return;

    // Resetear el manager
    _deviceTrackPointManager = null;
    _deviceTrackPointManager = await map.annotations.createCircleAnnotationManager();

    // Repoblar todos los puntos guardados
    for (final point in _recordedPoints) {
      await _deviceTrackPointManager!.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(point.longitude, point.latitude)),
          circleRadius: 4.0,
          circleColor: luxToArgb(point.lux),
          circleOpacity: 0.9,
        ),
      );
    }
  }

  bool _gpsIsPreciseEnough() {
    final acc = _currentPosition?.accuracy;
    if (acc == null) return false;
    return acc > 0 && acc <= _requiredGpsAccuracyMeters;
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
    debugPrint('Starting recording - isLoggedIn: $isLoggedIn');
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
    debugPrint('Got userId: $userId');
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

    final backgroundReady = await _ensureHighAccuracyLocationReady(requireBackground: true);
    if (!backgroundReady) return;

    unawaited(_startLocationUpdates(skipPermissionCheck: true));

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

    _recordedPoints.clear();
    _isRecording = true;
    _isPaused = false;
    _autoPausedDueToGps = false;
    _recordingStartedAt = DateTime.now();

    _deviceMapFollowUser = true;
    _setRecPulseActive(true);
    unawaited(_deviceTrackPointManager?.deleteAll());

    _startRecordingTimer();
    unawaited(_startRecordingForegroundService());
    
    // Mantener CPU activo para que el stream de GPS continue funcionando
    if (Platform.isAndroid) {
      WakelockPlus.enable();
    }

    if (mounted) setState(() {});
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final pos = _currentPosition;
      if (pos == null) return;

      final m = _latest;

      if (m == null) return;

        _recordedPoints.add(
          LightTrackPoint(
          timestamp: DateTime.now(),
          latitude: pos.latitude,
          longitude: pos.longitude,
          altitude: pos.altitude,
          accuracyMeters: pos.accuracy,
          lux: m.lux,
          cct: m.cct,
          cieX: m.cieX,
          cieY: m.cieY,
          cieU: m.cieU,
          cieV: m.cieV,
          duv: m.duv,
          tint: m.tint,
          mode: m.mode,
          channels: m.correctedChannels,
          temperature: m.temperature,
          batteryMv: m.batteryMv,
        ),
      );

      unawaited(_addDeviceBreadcrumbPoint(pos, lux: m.lux));

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
    
    // Liberar wake lock
    if (Platform.isAndroid) {
      WakelockPlus.disable();
    }
    
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

  Future<_Lm3TrackSaveMeta?> _askTrackMeta() async {
    final result = await showDialog<_Lm3TrackSaveMeta>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _Lm3TrackNameDialog();
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

      final deviceName = widget.device.platformName;
      final payload = {
        'trackType': 'light',
        'name': trackName,
        'description': description,
        'synced': false,
        'syncedAt': null,
        'cloudTrackId': null,
        'device': {
          'name': (deviceName.isNotEmpty) ? deviceName : 'Unknown Device',
          'id': widget.device.remoteId.toString(),
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

  Future<void> _connectAndStart() async {
    setState(() {
      _isConnecting = true;
      _status = 'Connecting...';
    });

    if (kDebugMode) {
      debugPrint('OppleLM3 Page: Starting connection to ${widget.device.platformName}');
    }

    final ok = await _service.connect(widget.device);
    if (!mounted) return;

    if (!ok) {
      if (kDebugMode) {
        debugPrint('OppleLM3 Page: Connection failed');
      }
      setState(() {
        _isConnecting = false;
        _status = 'Failed to connect/initialize LM3 (service/characteristics/calibration)';
      });
      return;
    }

    if (kDebugMode) {
      debugPrint('OppleLM3 Page: Connection successful, starting measurements');
    }

    _sub?.cancel();
    _sub = _service.measurements.listen((m) {
      if (!mounted) return;
      setState(() {
        _latest = m;
      });
    });

    _service.startMeasuring();

    setState(() {
      _isConnecting = false;
      _status = 'Measuring...';
    });
  }

  Future<void> _disconnect(BuildContext context) async {
    await _service.disconnect();
    deviceSession.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gpsOk = _gpsIsPreciseEnough();
    final hasStoppedSession = !_isRecording && _recordedPoints.isNotEmpty;
    final isActivelyRecording = _isRecording && !_isPaused;

    final m = _latest;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle),
            Text(
              widget.device.platformName.isNotEmpty
                  ? widget.device.platformName
                  : widget.device.remoteId.toString(),
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => _disconnect(context),
              icon: const Icon(Icons.bluetooth_disabled, size: 18),
              label: Text(l10n.deviceDisconnect),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            color: gpsOk
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          !_isLoggedInForTracking
                              ? l10n.trackingNeedLogin
                              : (gpsOk
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
                        if (m != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'LUX',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        Text(
                                          m.lux.toStringAsFixed(1),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CCT',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        Text(
                                          '${m.cct.toStringAsFixed(0)} K',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DefaultTextStyle(
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'x,y: ${m.cieX.toStringAsFixed(4)}, ${m.cieY.toStringAsFixed(4)}',
                                    ),
                                    Text(
                                      'u,v: ${m.cieU.toStringAsFixed(4)}, ${m.cieV.toStringAsFixed(4)}',
                                    ),
                                    Text('Duv: ${m.duv.toStringAsFixed(5)}'),
                                    Text('Tint: ${m.tint.toStringAsFixed(1)}'),
                                    Text('Mode: ${m.mode}'),
                                    Text(
                                      'Channels V/B/G/Y/O/R: ${m.correctedChannels.map((v) => v.toStringAsFixed(1)).join(" / ")}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text('Temp: ${m.temperature}'),
                                    Text('Battery: ${m.batteryMv} mV'),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            _status,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
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
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
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
                                            _isPaused
                                                ? Icons.play_arrow
                                                : Icons.pause,
                                          ),
                                          label: Text(
                                            _isPaused
                                                ? l10n.resume
                                                : l10n.pause,
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
                                            backgroundColor:
                                                Colors.redAccent,
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
                                icon:
                                    const Icon(Icons.fiber_manual_record),
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
                              Text(l10n.deviceGettingHighAccuracyGpsFix),
                            ],
                          ),
                        )
                      : Stack(
                          children: [
                            if (widget.activeTabIndex != null &&
                                widget.tabIndex != null)
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
                                    key: ValueKey('lm3_device_map_$styleUri'),
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
                                      unawaited(
                                          _enableDeviceMapUserLocation());
                                      unawaited(
                                          _centerDeviceMapOnCurrentPosition());
                                      unawaited(MarnaLayer.ensureAdded(mapboxMap).then((_) {
                                        if (_marnaEnabled) MarnaLayer.setVisible(mapboxMap, visible: true);
                                      }));
                                      // Repoblar puntos si estamos trackeando
                                      if (_isRecording) {
                                        unawaited(_repopulateMapTrackPoints());
                                      }
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
                                    key: ValueKey('lm3_device_map_$styleUri'),
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
                                      unawaited(
                                          _centerDeviceMapOnCurrentPosition());
                                      unawaited(MarnaLayer.ensureAdded(mapboxMap).then((_) {
                                        if (_marnaEnabled) MarnaLayer.setVisible(mapboxMap, visible: true);
                                      }));
                                      // Repoblar puntos si estamos trackeando
                                      if (_isRecording) {
                                        unawaited(_repopulateMapTrackPoints());
                                      }
                                    },
                                  );
                                },
                              ),
                            Positioned(
                              right: 12,
                              bottom: 72,
                              child: MarnaLayerToggle(
                                enabled: _marnaEnabled,
                                onToggle: () {
                                  setState(() => _marnaEnabled = !_marnaEnabled);
                                  final map = _deviceMap;
                                  if (map != null) {
                                    unawaited(MarnaLayer.setVisible(map, visible: _marnaEnabled));
                                  }
                                },
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: FloatingActionButton(
                                heroTag: 'lm3_device_map_center_btn',
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
        ),
      ),
    );
  }
}

class _Lm3TrackSaveMeta {
  final String name;
  final String description;

  const _Lm3TrackSaveMeta({
    required this.name,
    required this.description,
  });
}

class _Lm3TrackNameDialog extends StatefulWidget {
  const _Lm3TrackNameDialog();

  @override
  State<_Lm3TrackNameDialog> createState() => _Lm3TrackNameDialogState();
}

class _Lm3TrackNameDialogState extends State<_Lm3TrackNameDialog> {
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
              _Lm3TrackSaveMeta(
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
