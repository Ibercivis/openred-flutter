import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../devices/core/device_definition.dart';
import '../../devices/core/device_registry.dart';
import '../../devices/core/device_session.dart';
import '../../devices/opple/opple_lm3_device_definition.dart';
import '../../devices/radiacode/radiacode_device_definition.dart';
import '../../l10n/app_localizations.dart';

class BLEScannerPage extends StatefulWidget {
  const BLEScannerPage({
    super.key,
    required this.activeTabIndex,
    required this.tabIndex,
  });

  final ValueListenable<int> activeTabIndex;
  final int tabIndex;

  @override
  State<BLEScannerPage> createState() => _BLEScannerPageState();
}

class _BLEScannerPageState extends State<BLEScannerPage> {
  final DeviceRegistry _registry =
      const DeviceRegistry([
        RadiacodeDeviceDefinition(enabled: true),
        OppleLm3DeviceDefinition(enabled: true),
      ]);

  List<ScanResult> _scanResults = const [];
  bool _isScanning = false;
  String _statusMessage = 'Ready to scan';

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  bool _isConnecting = false;
  String? _connectingDeviceId;

  bool get _isActive => widget.activeTabIndex.value == widget.tabIndex;

  @override
  void initState() {
    super.initState();
    widget.activeTabIndex.addListener(_handleActiveTabChanged);
    unawaited(_checkBluetoothState());
  }

  @override
  void dispose() {
    widget.activeTabIndex.removeListener(_handleActiveTabChanged);
    unawaited(_stopScan());
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }

  void _handleActiveTabChanged() {
    if (_isActive) return;
    unawaited(_stopScan());
  }

  Future<void> _checkBluetoothState() async {
    if (await FlutterBluePlus.isSupported == false) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Bluetooth not supported by this device';
      });
      return;
    }

    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            state == BluetoothAdapterState.on ? 'Bluetooth is ON' : 'Please turn on Bluetooth';
      });
    });
  }

  Future<void> _requestPermissions() async {
    // permission_handler handles API level internally:
    // - Android 12+ (API 31+): bluetoothScan/bluetoothConnect are runtime permissions → shows dialog.
    // - Android 11 and below: bluetoothScan/bluetoothConnect are install-time → auto-granted.
    //   ACCESS_FINE_LOCATION is required for BLE scanning on Android ≤ 11 → shows dialog.
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions are required for BLE scanning')),
      );
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    await _requestPermissions();

    if (!mounted) return;
    setState(() {
      _scanResults = const [];
      _isScanning = true;
      _statusMessage = 'Scanning...';
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          _scanResults = results;
        });
      });

      await Future.delayed(const Duration(seconds: 15));
      await _stopScan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error scanning: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // ignore
    }

    if (!mounted) return;

    // For now the only enabled device is Radiacode, so keep the existing UX copy.
    final radiaCodeCount = _scanResults.where((r) {
      final name = r.device.platformName;
      return name.isNotEmpty && name.contains('RadiaCode');
    }).length;

    setState(() {
      _isScanning = false;
      _statusMessage = radiaCodeCount == 0
          ? 'No RadiaCode devices found'
          : 'Found $radiaCodeCount RadiaCode device(s)';
    });
  }

  Future<void> _openDevice(DeviceMatch match) async {
    if (_isConnecting) return;

    final device = match.scanResult.device;
    final deviceId = device.remoteId.toString();

    setState(() {
      _isConnecting = true;
      _connectingDeviceId = deviceId;
    });

    try {
      await _stopScan();
      deviceSession.connect(device: device, definition: match.definition);
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });
      } else {
        _isConnecting = false;
        _connectingDeviceId = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget body;
    final compatibleResults = _scanResults
        .where((r) => _registry.match(r) != null)
        .toList();

    if (compatibleResults.isNotEmpty) {
      body = ListView.builder(
        itemCount: compatibleResults.length,
        itemBuilder: (context, index) {
          final result = compatibleResults[index];
          final device = result.device;
          final deviceId = device.remoteId.toString();
          final serviceUuids = result.advertisementData.serviceUuids;

          final match = _registry.match(result);

            final advName = result.advertisementData.advName.trim();
            final localName = result.advertisementData.localName.trim();
            final title = device.platformName.isNotEmpty
              ? device.platformName
              : (advName.isNotEmpty
                ? advName
                : (localName.isNotEmpty ? localName : l10n.deviceUnknownDevice));

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: Icon(
                Icons.bluetooth_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.deviceListId(deviceId)),
                  Text(l10n.deviceListRssi(result.rssi)),
                  Text('Supported: ${match!.definition.displayName}'),
                  if (serviceUuids.isNotEmpty)
                    Text('UUIDs: ${serviceUuids.join(", ")}'),
                ],
              ),
              trailing: ElevatedButton(
                      onPressed:
                          _isConnecting ? null : () => _openDevice(match!),
                      child: Text(
                        (_isConnecting && _connectingDeviceId == deviceId)
                            ? l10n.deviceConnecting
                            : l10n.deviceConnect,
                      ),
                    ),
            ),
          );
        },
      );
    } else {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _isScanning
                  ? l10n.deviceSearchingRadiaCode
                  : l10n.deviceNoRadiaCodeDevicesFound,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _statusMessage,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navDevice),
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? _stopScan : _startScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search),
        label: Text(_isScanning ? l10n.deviceStopScan : l10n.deviceStartScan),
      ),
    );
  }
}
