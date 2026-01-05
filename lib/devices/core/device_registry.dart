import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_definition.dart';

class DeviceRegistry {
  const DeviceRegistry(this._definitions);

  final List<DeviceDefinition> _definitions;

  List<DeviceDefinition> get enabledDefinitions =>
      _definitions.where((d) => d.enabled).toList(growable: false);

  DeviceMatch? match(ScanResult result) {
    for (final def in enabledDefinitions) {
      if (def.matches(result)) {
        return DeviceMatch(definition: def, scanResult: result);
      }
    }
    return null;
  }

  List<DeviceMatch> filterMatches(List<ScanResult> results) {
    final matches = <DeviceMatch>[];
    for (final r in results) {
      final m = match(r);
      if (m != null) matches.add(m);
    }
    return matches;
  }
}
