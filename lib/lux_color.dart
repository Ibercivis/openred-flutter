import 'package:flutter/material.dart';

Color luxToColor(double? lux) {
  final v = lux;
  if (v == null || !v.isFinite || v < 0) return Colors.grey;

  // Night-themed palette used for light-pollution visualization.
  // Expected range: 0..20 lux, saturates at 20.
  final x = v.clamp(0.0, 20.0);

  if (x <= 10.0) {
    final t = x / 10.0;
    return Color.lerp(Colors.blue, Colors.purple, t) ?? Colors.purple;
  }

  final t = (x - 10.0) / 10.0;
  return Color.lerp(Colors.purple, Colors.red, t) ?? Colors.red;
}

int luxToArgb(double? lux) {
  return luxToColor(lux).toARGB32();
}
