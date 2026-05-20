import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

/// Helpers for adding / toggling the MARNA background-radiation tile overlay
/// on any Mapbox map.
///
/// Tile URL template: https://map.open-red.es/marna_tiles/{z}/{x}/{y}.png
///
/// Usage:
///   - Call [ensureAdded] once in onMapCreated (adds source+layer hidden).
///   - Call [setVisible] to show/hide — only changes the visibility property,
///     so Mapbox repaints immediately without needing a camera move.
class MarnaLayer {
  MarnaLayer._();

  static const String sourceId = 'marna-tiles-source';
  static const String layerId = 'marna-tiles-layer';

  /// Add the MARNA raster source + layer (initially hidden) to [mapboxMap].
  /// Safe to call multiple times — skips if already present.
  static Future<void> ensureAdded(mapbox.MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

    final sourceExists = await style.styleSourceExists(sourceId);
    if (!sourceExists) {
      await style.addSource(
        mapbox.RasterSource(
          id: sourceId,
          tiles: ['https://map.open-red.es/marna_tiles/{z}/{x}/{y}.png'],
          tileSize: 256,
          scheme: mapbox.Scheme.TMS,
        ),
      );
    }

    final layerExists = await style.styleLayerExists(layerId);
    if (!layerExists) {
      await style.addLayer(
        mapbox.RasterLayer(
          id: layerId,
          sourceId: sourceId,
          rasterOpacity: 0.6,
          visibility: mapbox.Visibility.NONE,
        ),
      );
    }
  }

  /// Show or hide the MARNA layer by toggling its visibility property.
  /// The source+layer must have been added first via [ensureAdded].
  static Future<void> setVisible(mapbox.MapboxMap mapboxMap, {required bool visible}) async {
    final style = mapboxMap.style;

    final layerExists = await style.styleLayerExists(layerId);
    if (!layerExists) return;

    await style.updateLayer(
      mapbox.RasterLayer(
        id: layerId,
        sourceId: sourceId,
        visibility: visible ? mapbox.Visibility.VISIBLE : mapbox.Visibility.NONE,
      ),
    );
  }
}

/// A small FAB / icon button to toggle the MARNA overlay.
/// Place inside a [Stack] on top of the map.
class MarnaLayerToggle extends StatelessWidget {
  const MarnaLayerToggle({
    super.key,
    required this.enabled,
    required this.onToggle,
  });

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'marna_toggle_${identityHashCode(this)}',
      backgroundColor: enabled
          ? Colors.amber.shade700
          : Colors.grey.shade800.withValues(alpha: 0.7),
      foregroundColor: enabled ? Colors.black : Colors.white70,
      onPressed: onToggle,
      tooltip: 'MARNA',
      child: const Icon(Icons.map_outlined, size: 20),
    );
  }
}
