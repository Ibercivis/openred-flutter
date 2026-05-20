import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../lux_color.dart';
import '../../../marna_layer.dart';
import '../../../models/recorded_track_point.dart';

class LightTrackMap extends StatefulWidget {
  final List<LightTrackPoint> points;
  final VoidCallback? onDelete;

  const LightTrackMap({
    super.key,
    required this.points,
    this.onDelete,
  });

  @override
  State<LightTrackMap> createState() => _LightTrackMapState();
}

class _LightTrackMapState extends State<LightTrackMap> {
  MapboxMap? _mapController;

  Cancelable? _circleTapCancelable;
  final Map<String, int> _annotationIndex = {};
  int? _selectedPointIndex;
  Offset? _popupAnchor;
  bool _ignoreNextMapTap = false;

  bool _marnaEnabled = false;

  List<LightTrackPoint>? _lastValidMapPoints;

  @override
  void dispose() {
    _circleTapCancelable?.cancel();
    super.dispose();
  }

  void _clearPopup() {
    if (_selectedPointIndex == null && _popupAnchor == null) return;
    setState(() {
      _selectedPointIndex = null;
      _popupAnchor = null;
    });
  }

  bool _isValidLatLon(double lat, double lon) {
    if (!lat.isFinite || !lon.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lon < -180 || lon > 180) return false;
    return true;
  }

  double _haversineMeters({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180.0;
    final p2 = lat2 * math.pi / 180.0;
    final dp = (lat2 - lat1) * math.pi / 180.0;
    final dl = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _initialZoomForBounds({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
  }) {
    final span = _haversineMeters(lat1: minLat, lon1: minLon, lat2: maxLat, lon2: maxLon);
    if (!span.isFinite || span <= 0) return 16.0;
    if (span < 60) return 18.0;
    if (span < 150) return 17.0;
    if (span < 350) return 16.0;
    if (span < 900) return 15.0;
    if (span < 2500) return 14.0;
    return 13.0;
  }

  String _formatDateTime(DateTime dt) {
    final d = dt;
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }

  String _fmtDouble(double? v, {int digits = 3}) {
    if (v == null || !v.isFinite) return 'N/A';
    return v.toStringAsFixed(digits);
  }

  Widget _buildPointPopup(LightTrackPoint p, int index) {
    final luxColor = luxToColor(p.lux);
    return GestureDetector(
      onTap: _clearPopup,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Card(
            elevation: 8,
            color: Colors.grey.shade900,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: luxColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Point #${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Time: ${_formatDateTime(p.timestamp)}'),
                    Text('Lux: ${_fmtDouble(p.lux, digits: 1)} lx'),
                    Text('CCT: ${_fmtDouble(p.cct, digits: 0)} K'),
                    Text('Duv: ${_fmtDouble(p.duv, digits: 5)}'),
                    Text('Tint: ${_fmtDouble(p.tint, digits: 1)}'),
                    Text('x,y: ${_fmtDouble(p.cieX, digits: 4)}, ${_fmtDouble(p.cieY, digits: 4)}'),
                    Text('u,v: ${_fmtDouble(p.cieU, digits: 4)}, ${_fmtDouble(p.cieV, digits: 4)}'),
                    if (p.mode != null) Text('Mode: ${p.mode}'),
                    if (p.temperature != null) Text('Temp: ${p.temperature}'),
                    if (p.batteryMv != null) Text('Battery: ${p.batteryMv} mV'),
                    const SizedBox(height: 6),
                    Text('Altitude: ${p.altitude.toStringAsFixed(1)} m'),
                    if (p.accuracyMeters.isFinite && p.accuracyMeters > 0)
                      Text('GPS acc: ${p.accuracyMeters.toStringAsFixed(1)} m'),
                    const SizedBox(height: 6),
                    Text(
                      'Lat/Lon: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: Colors.grey.shade300, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleMapTap(MapContentGestureContext context) {
    if (_ignoreNextMapTap) {
      _ignoreNextMapTap = false;
      return;
    }

    final map = _mapController;
    if (map == null) {
      _clearPopup();
      return;
    }

    final p = context.point;
    final tapLon = p.coordinates.lng.toDouble();
    final tapLat = p.coordinates.lat.toDouble();

    () async {
      final camera = await map.getCameraState();
      final zoom = camera.zoom;

      // Approx threshold similar to RadiationTrackMap, without pulling in helpers.
      final metersPerPixel = 156543.03392 * math.cos(tapLat * math.pi / 180.0) / math.pow(2.0, zoom);
      final thresholdMeters = (metersPerPixel * 28.0).clamp(6.0, 120.0);

      final validPoints = _lastValidMapPoints;
      if (validPoints == null || validPoints.isEmpty) {
        _clearPopup();
        return;
      }

      var bestIdx = -1;
      var bestDist = double.infinity;
      for (var i = 0; i < validPoints.length; i++) {
        final vp = validPoints[i];
        final d = _haversineMeters(
          lat1: tapLat,
          lon1: tapLon,
          lat2: vp.latitude,
          lon2: vp.longitude,
        );
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }

      if (bestIdx >= 0 && bestDist <= thresholdMeters) {
        final sc = await map.pixelForCoordinate(
          Point(coordinates: Position(validPoints[bestIdx].longitude, validPoints[bestIdx].latitude)),
        );
        if (!mounted) return;
        setState(() {
          if (_selectedPointIndex == bestIdx) {
            _selectedPointIndex = null;
            _popupAnchor = null;
          } else {
            _selectedPointIndex = bestIdx;
            _popupAnchor = Offset(sc.x, sc.y);
          }
        });
        return;
      }

      _clearPopup();
    }();
  }

  @override
  Widget build(BuildContext context) {
    final validPoints = widget.points
        .where((p) => _isValidLatLon(p.latitude, p.longitude))
        .toList(growable: false);

    _lastValidMapPoints = validPoints;

    if (validPoints.isEmpty) {
      return const Center(
        child: Text(
          'No valid GPS points to show on the map.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLon = double.infinity;
    double maxLon = double.negativeInfinity;

    for (final p in validPoints) {
      final lat = p.latitude;
      final lon = p.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final initialZoom = _initialZoomForBounds(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon);

    final styleUri = Theme.of(context).brightness == Brightness.dark
      ? MapboxStyles.DARK
      : MapboxStyles.LIGHT;

    return Stack(
      children: [
        MapWidget(
          key: ValueKey('light_track_map_$styleUri'),
          cameraOptions: CameraOptions(
            center: Point(coordinates: Position(centerLon, centerLat)),
            zoom: initialZoom,
          ),
          styleUri: styleUri,
          onTapListener: _handleMapTap,
          onMapCreated: (mapController) async {
            _mapController = mapController;
            await mapController.location.updateSettings(
              LocationComponentSettings(enabled: false),
            );
            unawaited(MarnaLayer.ensureAdded(mapController).then((_) {
              if (_marnaEnabled) MarnaLayer.setVisible(mapController, visible: true);
            }));

            final circleManager = await mapController.annotations.createCircleAnnotationManager();

            _annotationIndex.clear();
            _circleTapCancelable?.cancel();

            final circleRadius = (validPoints.length >= 120) ? 9.0 : 13.0;

            for (var i = 0; i < validPoints.length; i++) {
              final p = validPoints[i];
              final annotation = await circleManager.create(
                CircleAnnotationOptions(
                  geometry: Point(coordinates: Position(p.longitude, p.latitude)),
                  circleRadius: circleRadius,
                  circleColor: luxToArgb(p.lux),
                  circleOpacity: 0.9,
                  circleStrokeWidth: 1.5,
                  circleStrokeColor: 0xFFFFFFFF,
                  circleStrokeOpacity: 0.8,
                ),
              );
              _annotationIndex[annotation.id] = i;
            }

            _circleTapCancelable = circleManager.tapEvents(
              onTap: (annotation) async {
                final map = _mapController;
                if (map == null) return;

                final idx = _annotationIndex[annotation.id];
                if (idx == null || idx < 0 || idx >= validPoints.length) return;

                _ignoreNextMapTap = true;
                final sc = await map.pixelForCoordinate(annotation.geometry);

                if (!mounted) return;
                setState(() {
                  _selectedPointIndex = idx;
                  _popupAnchor = Offset(sc.x, sc.y);
                });
              },
            );
          },
        ),
        if (_selectedPointIndex != null && _popupAnchor != null)
          Positioned(
            left: _popupAnchor!.dx,
            top: _popupAnchor!.dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -1.2),
              child: _buildPointPopup(validPoints[_selectedPointIndex!], _selectedPointIndex!),
            ),
          ),
        if (widget.onDelete != null)
          Positioned(
            right: 12,
            top: 12,
            child: FloatingActionButton.small(
              heroTag: 'light_delete',
              tooltip: 'Delete track',
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              onPressed: widget.onDelete,
              child: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 12,
          child: MarnaLayerToggle(
            enabled: _marnaEnabled,
            onToggle: () {
              setState(() => _marnaEnabled = !_marnaEnabled);
              final map = _mapController;
              if (map != null) {
                unawaited(MarnaLayer.setVisible(map, visible: _marnaEnabled));
              }
            },
          ),
        ),
      ],
    );
  }
}
