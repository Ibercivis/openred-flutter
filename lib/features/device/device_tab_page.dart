import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../devices/core/device_session.dart';
import '../scanner/ble_scanner_page.dart';

class DeviceTabPage extends StatelessWidget {
  const DeviceTabPage({
    super.key,
    required this.activeTabIndex,
    required this.tabIndex,
  });

  final ValueListenable<int> activeTabIndex;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: activeTabIndex,
      builder: (context, activeIdx, _) {
        return AnimatedBuilder(
          animation: deviceSession,
          builder: (context, _) {
            if (deviceSession.isConnected) {
              final device = deviceSession.device;
              final definition = deviceSession.definition;
              if (device == null || definition == null) {
                deviceSession.clear();
                return const SizedBox.shrink();
              }

              // Keep the connected device page alive even when switching tabs.
              return definition.createDevicePage(
                device: device,
                activeTabIndex: activeTabIndex,
                tabIndex: tabIndex,
              );
            }

            // Not connected: only build the scanner UI when this tab is active.
            if (activeIdx != tabIndex) return const SizedBox.shrink();
            return BLEScannerPage(activeTabIndex: activeTabIndex, tabIndex: tabIndex);
          },
        );
      },
    );
  }
}
