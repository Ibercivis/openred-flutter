import 'dart:math' as math;

import 'package:flutter/material.dart';

Color doseRateToColor(double? doseMicroSvPerHour) {
  final v = doseMicroSvPerHour;
  if (v == null || !v.isFinite || v < 0) return Colors.grey;

  // Piecewise mapping using existing Material colors.
  // Typical background levels are ~0.05–0.2 µSv/h.
  if (v <= 0.10) return Colors.green;
  if (v <= 0.30) {
    final t = (v - 0.10) / (0.30 - 0.10);
    return Color.lerp(Colors.green, Colors.yellow, t) ?? Colors.yellow;
  }
  if (v <= 1.0) return Colors.yellow;
  if (v <= 3.0) {
    final t = (v - 1.0) / (3.0 - 1.0);
    return Color.lerp(Colors.yellow, Colors.orange, t) ?? Colors.orange;
  }
  if (v <= 10.0) {
    final t = (v - 3.0) / (10.0 - 3.0);
    return Color.lerp(Colors.orange, Colors.red, t) ?? Colors.red;
  }
  return Colors.red;
}

int doseRateToArgb(double? doseMicroSvPerHour) {
  return doseRateToColor(doseMicroSvPerHour).toARGB32();
}

double metersPerPixelAtLatitude({required double latitude, required double zoom}) {
  // Web Mercator ground resolution (meters/pixel) for 256px tiles.
  return 156543.03392 * math.cos(latitude * math.pi / 180.0) / math.pow(2.0, zoom);
}
