import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../api_service.dart';
import '../../config.dart';
import '../../dose_color.dart';
import '../../l10n/app_localizations.dart';
import '../../devices/core/device_session.dart';

enum _MapLayer {
  radiation,
  light,
}

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.activeTabIndex,
    required this.tabIndex,
    this.projectId = 1,
    this.measurementType = 'radiation',
  });

  final ValueListenable<int> activeTabIndex;
  final int tabIndex;

  /// Backend project id for H3 aggregation.
  final int projectId;

  /// Measurement type for the aggregation endpoint (e.g. "radiation", "light_pollution").
  final String measurementType;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapboxMap? _mapboxMap;
  PolygonAnnotationManager? _hexPolygonManager;
  Cancelable? _hexTapCancelable;
  final ApiService _apiService = ApiService();

  late _MapLayer _layer;
  bool _layerPinnedByUser = false;

  final Map<String, _HexFeature> _hexByAnnotationId = {};
  _HexFeature? _selectedHex;
  Offset? _hexPopupAnchor;

  _LatLonBounds? _cachedFetchBounds;
  int? _cachedResolution;
  _MapLayer? _cachedLayer;
  bool _isFetching = false;
  int _fetchSeq = 0;

  bool get _isActive => widget.activeTabIndex.value == widget.tabIndex;

  @override
  void initState() {
    super.initState();
    _layer = _defaultLayerFromDevice();
    widget.activeTabIndex.addListener(_handleActiveTabChanged);
    deviceSession.addListener(_handleDeviceSessionChanged);
  }

  _MapLayer _defaultLayerFromDevice() {
    if (deviceSession.isConnected) {
      final id = deviceSession.definition?.id;
      if (id == 'opple_lm3') return _MapLayer.light;
      if (id == 'radiacode') return _MapLayer.radiation;
    }
    return _MapLayer.radiation;
  }

  void _handleDeviceSessionChanged() {
    if (_layerPinnedByUser) return;
    final next = _defaultLayerFromDevice();
    if (next == _layer) return;
    if (!mounted) return;
    setState(() => _layer = next);
    unawaited(_resetAndRefetch(reason: 'device changed'));
  }

  void _handleActiveTabChanged() {
    if (!_isActive) {
      _mapboxMap = null;
      _hexPolygonManager = null;
      _hexTapCancelable?.cancel();
      _hexTapCancelable = null;
      _hexByAnnotationId.clear();
      _selectedHex = null;
      _hexPopupAnchor = null;
      _cachedFetchBounds = null;
      _cachedResolution = null;
      _isFetching = false;
    }
  }

  @override
  void dispose() {
    widget.activeTabIndex.removeListener(_handleActiveTabChanged);
    deviceSession.removeListener(_handleDeviceSessionChanged);
    _hexTapCancelable?.cancel();
    super.dispose();
  }

  int get _projectIdForLayer {
    switch (_layer) {
      case _MapLayer.radiation:
        return Config.radiationProjectId;
      case _MapLayer.light:
        return Config.lightProjectId;
    }
  }

  H3AggregationSource get _h3SourceForLayer {
    switch (_layer) {
      case _MapLayer.radiation:
        return H3AggregationSource.radiation;
      case _MapLayer.light:
        return H3AggregationSource.lightPollution;
    }
  }

  String get _layerLabel {
    switch (_layer) {
      case _MapLayer.radiation:
        return 'Radiation';
      case _MapLayer.light:
        return 'Light pollution';
    }
  }

  Future<void> _resetAndRefetch({required String reason}) async {
    _cachedFetchBounds = null;
    _cachedResolution = null;
    _cachedLayer = null;
    _clearHexPopup();

    final manager = _hexPolygonManager;
    if (manager != null) {
      await manager.deleteAll();
      _hexByAnnotationId.clear();
    }

    await _maybeRefetchHexes(reason: reason);
  }

  void _setLayer(_MapLayer next, {required bool fromUser}) {
    if (next == _layer) return;
    if (!mounted) return;
    setState(() {
      _layer = next;
      if (fromUser) _layerPinnedByUser = true;
    });
    unawaited(_resetAndRefetch(reason: fromUser ? 'layer changed' : 'layer changed (auto)'));
  }

  void _clearHexPopup() {
    if (!mounted) return;
    setState(() {
      _selectedHex = null;
      _hexPopupAnchor = null;
    });
  }

  int _luxPollutionToArgb(double? lux) {
    final v0 = lux;
    if (v0 == null || !v0.isFinite) return Colors.grey.toARGB32();

    // Tuned for light-pollution mapping where values are expected in lux.
    // Range: 0..20, saturates at 20.
    final v = v0.clamp(0.0, 20.0);

    // Night-themed palette:
    // low pollution (dark) -> blue
    // medium -> purple
    // high -> red
    if (v <= 10.0) {
      final t = v / 10.0;
      return (Color.lerp(Colors.blue, Colors.purple, t) ?? Colors.purple).toARGB32();
    }

    final t = (v - 10.0) / 10.0;
    return (Color.lerp(Colors.purple, Colors.red, t) ?? Colors.red).toARGB32();
  }

  int _fillColorForValue(double value) {
    if (_layer == _MapLayer.radiation) return doseRateToArgb(value);
    return _luxPollutionToArgb(value);
  }

  String _formatAvgValue(double value) {
    if (_layer == _MapLayer.radiation) {
      return '${value.toStringAsFixed(3)} µSv/h';
    }
    // Light pollution (assumed lux)
    return '${value.toStringAsFixed(2)} lux';
  }

  _LonLat _centroidForRing(List<_LonLat> ring) {
    if (ring.isEmpty) return const _LonLat(lng: 0, lat: 0);
    var sumLat = 0.0;
    var sumLon = 0.0;
    for (final p in ring) {
      sumLat += p.lat;
      sumLon += p.lng;
    }
    return _LonLat(lng: sumLon / ring.length, lat: sumLat / ring.length);
  }

  Future<void> _handleHexTap(PolygonAnnotation annotation) async {
    final hex = _hexByAnnotationId[annotation.id];
    final map = _mapboxMap;
    if (hex == null || map == null) return;

    final center = _centroidForRing(hex.outerRing);
    final sc = await map.pixelForCoordinate(
      Point(coordinates: Position(center.lng, center.lat)),
    );

    if (!mounted) return;
    setState(() {
      _selectedHex = hex;
      _hexPopupAnchor = Offset(sc.x, sc.y);
    });
  }

  Future<void> _centerOnMyLocation() async {
    final map = _mapboxMap;
    if (map == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map not ready yet')),
      );
      return;
    }

    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
        return;
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
        ),
      );

      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: 14.0,
        ),
        MapAnimationOptions(duration: 700),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
    }
  }

  int _resolutionForZoom(double zoom) {
    final res = (zoom / 1.3).round();
    return res.clamp(1, 15);
  }

  Future<_LatLonBounds?> _getVisibleBounds() async {
    final map = _mapboxMap;
    if (map == null) return null;

    final state = await map.getCameraState();
    final camera = CameraOptions(
      center: state.center,
      zoom: state.zoom,
      bearing: state.bearing,
      pitch: state.pitch,
      padding: state.padding,
    );

    final bounds = await map.coordinateBoundsForCameraUnwrapped(camera);
    return _LatLonBounds.fromCoordinateBounds(bounds);
  }

  Future<void> _maybeRefetchHexes({required String reason}) async {
    if (!_isActive) return;

    final map = _mapboxMap;
    final manager = _hexPolygonManager;
    if (map == null || manager == null) return;

    if (_isFetching) return;

    final visible = await _getVisibleBounds();
    if (visible == null) return;

    final cameraState = await map.getCameraState();
    final resolution = _resolutionForZoom(cameraState.zoom);

    final needsRefetch = _cachedFetchBounds == null ||
        _cachedResolution != resolution ||
      _cachedLayer != _layer ||
        !_cachedFetchBounds!.containsBounds(visible);

    if (!needsRefetch) return;

    final fetchBounds = visible.expandedArea(factor: 2.0);

    _cachedFetchBounds = fetchBounds;
    _cachedResolution = resolution;
    _cachedLayer = _layer;

    final requestId = ++_fetchSeq;
    setState(() => _isFetching = true);
    try {
      final result = await _apiService.getH3Aggregation(
        source: _h3SourceForLayer,
        resolution: resolution,
        projectId: _projectIdForLayer,
        measurementType: _layer == _MapLayer.radiation ? widget.measurementType : null,
        north: fetchBounds.north,
        south: fetchBounds.south,
        east: fetchBounds.east,
        west: fetchBounds.west,
      );

      if (!_isActive) return;
      if (requestId != _fetchSeq) return;

      if (result['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? 'Failed to load hexagons')),
        );
        return;
      }

      final hexes = _parseHexFeatures(result['data']);

      await manager.deleteAll();
      _hexByAnnotationId.clear();
      for (final h in hexes) {
        if (h.outerRing.isEmpty) continue;

        final ringPoints = h.outerRing
            .map((pos) => Point(coordinates: Position(pos.lng, pos.lat)))
            .toList(growable: true);

        if (ringPoints.length >= 3) {
          final first = ringPoints.first.coordinates;
          final last = ringPoints.last.coordinates;
          if (first.lng != last.lng || first.lat != last.lat) {
            ringPoints.add(Point(coordinates: Position(first.lng, first.lat)));
          }
        }

        if (ringPoints.length < 4) continue;

        final poly = Polygon.fromPoints(points: [ringPoints]);
        final annotation = await manager.create(
          PolygonAnnotationOptions(
            geometry: poly,
            fillColor: _fillColorForValue(h.value),
            fillOpacity: 0.55,
            fillOutlineColor: 0x66FFFFFF,
          ),
        );

        _hexByAnnotationId[annotation.id] = h;
      }

      _hexTapCancelable?.cancel();
      _hexTapCancelable = manager.tapEvents(onTap: _handleHexTap);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load hexagons: $e')),
      );
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  List<_HexFeature> _parseHexFeatures(dynamic data) {
    final out = <_HexFeature>[];

    if (data is Map && data['hexagons'] is List) {
      for (final it in (data['hexagons'] as List)) {
        if (it is! Map) continue;

        final valueRaw = it['avg_value'] ?? it['value'] ?? it['avg'];
        final value = (valueRaw is num)
            ? valueRaw.toDouble()
            : double.tryParse(valueRaw?.toString() ?? '');
        if (value == null) continue;

        final vertices = it['vertices'];
        if (vertices is! List) continue;

        final ring = <_LonLat>[];
        for (final v in vertices) {
          if (v is! List || v.length < 2) continue;
          final lat = (v[0] is num) ? (v[0] as num).toDouble() : double.tryParse(v[0].toString());
          final lon = (v[1] is num) ? (v[1] as num).toDouble() : double.tryParse(v[1].toString());
          if (lat == null || lon == null) continue;
          ring.add(_LonLat(lng: lon, lat: lat));
        }

        if (ring.length < 3) continue;

        final h3Index = it['h3_index']?.toString();
        final measurementCountRaw = it['measurement_count'];
        final measurementCount = (measurementCountRaw is int)
            ? measurementCountRaw
            : int.tryParse(measurementCountRaw?.toString() ?? '');

        final minValueRaw = it['min_value'];
        final minValue = (minValueRaw is num)
            ? minValueRaw.toDouble()
            : double.tryParse(minValueRaw?.toString() ?? '');

        final maxValueRaw = it['max_value'];
        final maxValue = (maxValueRaw is num)
            ? maxValueRaw.toDouble()
            : double.tryParse(maxValueRaw?.toString() ?? '');

        final stdValueRaw = it['std_value'];
        final stdValue = (stdValueRaw is num)
            ? stdValueRaw.toDouble()
            : double.tryParse(stdValueRaw?.toString() ?? '');

        out.add(
          _HexFeature(
            outerRing: ring,
            value: value,
            h3Index: h3Index,
            measurementCount: measurementCount,
            minValue: minValue,
            maxValue: maxValue,
            stdValue: stdValue,
          ),
        );
      }
      return out;
    }

    dynamic items = data;
    if (items is Map && items['results'] is List) {
      items = items['results'];
    }

    if (items is Map && items['features'] is List) {
      for (final f in (items['features'] as List)) {
        if (f is! Map) continue;
        final geom = f['geometry'];
        final props = f['properties'];

        final value = _extractNumeric(props, keys: const [
          'value',
          'dose',
          'dose_rate',
          'doseRate',
          'avg',
          'mean',
        ]);
        if (value == null) continue;

        final polys = _extractPolygonsFromGeometry(geom);
        for (final ring in polys) {
          out.add(_HexFeature(outerRing: ring, value: value));
        }
      }
      return out;
    }

    if (items is List) {
      for (final it in items) {
        if (it is! Map) continue;

        final value = _extractNumeric(it, keys: const [
          'value',
          'dose',
          'dose_rate',
          'doseRate',
          'avg',
          'mean',
        ]);
        if (value == null) continue;

        final polys = <List<_LonLat>>[];
        if (it['geometry'] != null) {
          polys.addAll(_extractPolygonsFromGeometry(it['geometry']));
        } else if (it['polygon'] != null) {
          final ring = _extractRing(it['polygon']);
          if (ring.isNotEmpty) polys.add(ring);
        } else if (it['coordinates'] != null) {
          final ring = _extractRing(it['coordinates']);
          if (ring.isNotEmpty) polys.add(ring);
        }

        for (final ring in polys) {
          out.add(_HexFeature(outerRing: ring, value: value));
        }
      }
    }

    return out;
  }

  double? _extractNumeric(dynamic mapLike, {required List<String> keys}) {
    if (mapLike is! Map) return null;
    for (final k in keys) {
      final v = mapLike[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  List<List<_LonLat>> _extractPolygonsFromGeometry(dynamic geom) {
    if (geom is! Map) return const [];
    final type = geom['type']?.toString();
    final coords = geom['coordinates'];
    if (type == 'Polygon') {
      if (coords is List && coords.isNotEmpty) {
        final ring = _extractRing(coords.first);
        if (ring.isNotEmpty) return [ring];
      }
    }
    if (type == 'MultiPolygon') {
      final out = <List<_LonLat>>[];
      if (coords is List) {
        for (final poly in coords) {
          if (poly is List && poly.isNotEmpty) {
            final ring = _extractRing(poly.first);
            if (ring.isNotEmpty) out.add(ring);
          }
        }
      }
      return out;
    }
    return const [];
  }

  List<_LonLat> _extractRing(dynamic ringLike) {
    final ring = <_LonLat>[];
    if (ringLike is! List) return ring;
    for (final p in ringLike) {
      if (p is List && p.length >= 2) {
        final lon = (p[0] is num) ? (p[0] as num).toDouble() : double.tryParse(p[0].toString());
        final lat = (p[1] is num) ? (p[1] as num).toDouble() : double.tryParse(p[1].toString());
        if (lon != null && lat != null) ring.add(_LonLat(lng: lon, lat: lat));
        continue;
      }
      if (p is Map) {
        final lon = _extractNumeric(p, keys: const ['lng', 'lon', 'longitude', 'x']);
        final lat = _extractNumeric(p, keys: const ['lat', 'latitude', 'y']);
        if (lon != null && lat != null) ring.add(_LonLat(lng: lon, lat: lat));
      }
    }
    return ring;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Open-red'),
            Text(
              l10n.navMap,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_MapLayer>(
            tooltip: 'Select layer',
            initialValue: _layer,
            onSelected: (v) => _setLayer(v, fromUser: true),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: _MapLayer.radiation,
                checked: _layer == _MapLayer.radiation,
                child: const Text('Radiation'),
              ),
              CheckedPopupMenuItem(
                value: _MapLayer.light,
                checked: _layer == _MapLayer.light,
                child: const Text('Light pollution'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers),
                    const SizedBox(width: 6),
                    Text(_layerLabel),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _centerOnMyLocation,
            tooltip: 'Center on my location',
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: widget.activeTabIndex,
        builder: (context, idx, _) {
          if (idx != widget.tabIndex) {
            return const SizedBox.expand();
          }

          final styleUri = Theme.of(context).brightness == Brightness.dark
              ? MapboxStyles.DARK
              : MapboxStyles.LIGHT;

          return Stack(
            children: [
              MapWidget(
                key: ValueKey('map_tab_map_$styleUri'),
                cameraOptions: CameraOptions(
                  center: Point(coordinates: Position(0.0, 0.0)),
                  zoom: 2.0,
                ),
                styleUri: styleUri,
                onMapCreated: (MapboxMap mapboxMap) async {
                  _mapboxMap = mapboxMap;
                  _hexPolygonManager =
                      await mapboxMap.annotations.createPolygonAnnotationManager();
                  unawaited(_maybeRefetchHexes(reason: 'created'));
                },
                onMapIdleListener: (_) {
                  unawaited(_maybeRefetchHexes(reason: 'idle'));
                },
                onTapListener: (_) {
                  _clearHexPopup();
                },
              ),
              if (_selectedHex != null && _hexPopupAnchor != null)
                Positioned(
                  left: _hexPopupAnchor!.dx,
                  top: _hexPopupAnchor!.dy,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -1.2),
                    child: GestureDetector(
                      onTap: _clearHexPopup,
                      child: Card(
                        color: Colors.black.withValues(alpha: 0.85),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: DefaultTextStyle(
                            style: const TextStyle(color: Colors.white),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedHex!.h3Index ?? 'Hex',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Avg: ${_formatAvgValue(_selectedHex!.value)}',
                                ),
                                if (_selectedHex!.measurementCount != null)
                                  Text('N: ${_selectedHex!.measurementCount}'),
                                if (_selectedHex!.minValue != null &&
                                    _selectedHex!.maxValue != null)
                                  Text(
                                    _layer == _MapLayer.radiation
                                        ? 'Min/Max: ${_selectedHex!.minValue!.toStringAsFixed(3)} / ${_selectedHex!.maxValue!.toStringAsFixed(3)}'
                                        : 'Min/Max: ${_selectedHex!.minValue!.toStringAsFixed(2)} / ${_selectedHex!.maxValue!.toStringAsFixed(2)}',
                                  ),
                                if (_selectedHex!.stdValue != null)
                                  Text(
                                    _layer == _MapLayer.radiation
                                        ? 'Std: ${_selectedHex!.stdValue!.toStringAsFixed(3)}'
                                        : 'Std: ${_selectedHex!.stdValue!.toStringAsFixed(2)}',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LonLat {
  const _LonLat({required this.lng, required this.lat});
  final double lng;
  final double lat;
}

class _HexFeature {
  const _HexFeature({
    required this.outerRing,
    required this.value,
    this.h3Index,
    this.measurementCount,
    this.minValue,
    this.maxValue,
    this.stdValue,
  });
  final List<_LonLat> outerRing;
  final double value;
  final String? h3Index;
  final int? measurementCount;
  final double? minValue;
  final double? maxValue;
  final double? stdValue;
}

class _LatLonBounds {
  const _LatLonBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;

  factory _LatLonBounds.fromCoordinateBounds(CoordinateBounds b) {
    final sw = b.southwest.coordinates;
    final ne = b.northeast.coordinates;

    final west = sw.lng.toDouble();
    final south = sw.lat.toDouble();
    final east = ne.lng.toDouble();
    final north = ne.lat.toDouble();

    return _LatLonBounds(north: north, south: south, east: east, west: west);
  }

  bool containsBounds(_LatLonBounds other) {
    return other.west >= west &&
        other.east <= east &&
        other.south >= south &&
        other.north <= north;
  }

  _LatLonBounds expandedArea({required double factor}) {
    final scale = math.sqrt(factor);

    final centerLat = (north + south) / 2.0;
    final centerLon = (east + west) / 2.0;

    final halfLat = (north - south) / 2.0;
    final halfLon = (east - west) / 2.0;

    var newNorth = centerLat + halfLat * scale;
    var newSouth = centerLat - halfLat * scale;
    var newEast = centerLon + halfLon * scale;
    var newWest = centerLon - halfLon * scale;

    newNorth = newNorth.clamp(-85.0, 85.0);
    newSouth = newSouth.clamp(-85.0, 85.0);

    return _LatLonBounds(north: newNorth, south: newSouth, east: newEast, west: newWest);
  }
}
