import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract class DeviceDefinition {
  const DeviceDefinition();

  String get id;
  String get displayName;
  bool get enabled;

  bool matches(ScanResult result);

  Widget createDevicePage({
    required BluetoothDevice device,
    ValueListenable<int>? activeTabIndex,
    int? tabIndex,
  });
}

class DeviceMatch {
  const DeviceMatch({required this.definition, required this.scanResult});

  final DeviceDefinition definition;
  final ScanResult scanResult;
}
