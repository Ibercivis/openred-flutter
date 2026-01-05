import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_definition.dart';

class DeviceSession extends ChangeNotifier {
  BluetoothDevice? _device;
  DeviceDefinition? _definition;

  bool get isConnected => _device != null && _definition != null;
  BluetoothDevice? get device => _device;
  DeviceDefinition? get definition => _definition;

  void connect({required BluetoothDevice device, required DeviceDefinition definition}) {
    _device = device;
    _definition = definition;
    notifyListeners();
  }

  void clear() {
    if (_device == null && _definition == null) return;
    _device = null;
    _definition = null;
    notifyListeners();
  }
}

final deviceSession = DeviceSession();
