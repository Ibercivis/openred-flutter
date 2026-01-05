import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/device_definition.dart';
import '../../features/device/radiacode_device_page.dart';

class RadiacodeDeviceDefinition extends DeviceDefinition {
  const RadiacodeDeviceDefinition({this.enabled = true});

  static const String _primaryServiceUuid =
      'e63215e5-7003-49d8-96b0-b024798fb901';

  @override
  final bool enabled;

  @override
  String get id => 'radiacode';

  @override
  String get displayName => 'RadiaCode';

  @override
  bool matches(ScanResult result) {
    final name = result.device.platformName;
    if (name.isNotEmpty && name.contains('RadiaCode')) return true;

    final serviceUuids = result.advertisementData.serviceUuids
      .map((u) => u.toString().toLowerCase())
        .toSet();
    return serviceUuids.contains(_primaryServiceUuid);
  }

  @override
  RadiacodeDevicePage createDevicePage({
    required BluetoothDevice device,
    ValueListenable<int>? activeTabIndex,
    int? tabIndex,
  }) {
    return RadiacodeDevicePage(
      device: device,
      activeTabIndex: activeTabIndex,
      tabIndex: tabIndex,
    );
  }
}
