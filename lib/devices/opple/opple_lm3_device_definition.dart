import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/device_definition.dart';
import '../../features/device/opple_lm3_device_page.dart';

class OppleLm3DeviceDefinition extends DeviceDefinition {
  const OppleLm3DeviceDefinition({required this.enabled});

  static String _normalizeNameForMatch(String raw) {
    // Remove control characters, whitespace, punctuation, underscores, etc.
    // This helps when the device name contains zero-width characters that render
    // invisibly but break simple substring checks.
    final cleaned = raw.replaceAll('\u0000', '').trim().toLowerCase();
    return cleaned.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  @override
  final bool enabled;

  @override
  String get id => 'opple_lm3';

  @override
  String get displayName => 'Opple LM3';

  @override
  bool matches(ScanResult result) {
    // Observed advertising name: LMaster_xxxx
    // Note: on Android, FlutterBluePlus often reports the scan name via
    // advertisementData.advName/localName, while device.platformName may be empty.
    final candidates = <String>[
      result.device.platformName,
      result.advertisementData.advName,
      result.advertisementData.localName,
    ];

    if (kDebugMode) {
      debugPrint('OppleLM3 DeviceDefinition: Checking device match');
      debugPrint('  platformName: "${result.device.platformName}"');
      debugPrint('  advName: "${result.advertisementData.advName}"');
      debugPrint('  localName: "${result.advertisementData.localName}"');
    }

    for (final raw in candidates) {
      final normalized = _normalizeNameForMatch(raw);
      if (kDebugMode) {
        debugPrint('  Normalized "$raw" -> "$normalized"');
      }
      if (normalized.isEmpty) continue;
      if (normalized.contains('lmaster')) {
        if (kDebugMode) {
          debugPrint('  MATCH! Contains "lmaster"');
        }
        return true;
      }
    }

    if (kDebugMode) {
      debugPrint('  NO MATCH');
    }
    return false;
  }

  @override
  Widget createDevicePage({
    required BluetoothDevice device,
    ValueListenable<int>? activeTabIndex,
    int? tabIndex,
  }) {
    return OppleLm3DevicePage(device: device);
  }
}
