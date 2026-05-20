import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class OppleLm3Measurement {
  const OppleLm3Measurement({
    required this.lux,
    required this.cct,
    required this.cieX,
    required this.cieY,
    required this.cieU,
    required this.cieV,
    required this.duv,
    required this.tint,
    required this.temperature,
    required this.batteryMv,
    required this.rawChannels,
    required this.correctedChannels,
    required this.mode,
  });

  final double lux;
  final double cct;

  final double cieX;
  final double cieY;
  final double cieU;
  final double cieV;

  final double duv;
  final double tint;
  final int temperature;
  final int batteryMv;

  /// Raw (uncorrected) channels: V, B, G, Y, O, R
  final List<int> rawChannels;

  /// Corrected channels: V, B, G, Y, O, R
  final List<double> correctedChannels;

  /// 1=monochromatic, 2=incandescent, 3=general
  final int mode;
}

class OppleLm3Service {
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String rxCharacteristicUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String txCharacteristicUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  // Protocol opcodes (from TS reference)
  static const int _reqMeas = 2560;
  static const int _resMeas = 2561;
  static const int _reqReadM3 = 2564;
  static const int _resReadM3 = 2565;

  // Fragment types
  static const int _msgSingle = 0x00;
  static const int _msgFfrag = 0x80;
  static const int _msgMfrag = 0xA0;
  static const int _msgLfrag = 0xC0;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  StreamSubscription<List<int>>? _notifySubscription;
  Timer? _measTimer;

  final _measurements = StreamController<OppleLm3Measurement>.broadcast();
  Stream<OppleLm3Measurement> get measurements => _measurements.stream;

  bool _inflight = false;
  int _seqNo = 0;

  Uint8List? _rxBuffer;
  int _rxBufferLen = 0;

  List<double> _kSensor = const [];

  // Low-pass filter state (mirrors TS behavior)
  final List<double> _prevMeas = List<double>.filled(6, 0);
  double _coeffA = 0;

  final _pending = <int, Completer<Uint8List>>{};

  Future<bool> connect(BluetoothDevice device) async {
    _device = device;

    // Retry logic for error 133 (common Android BLE issue)
    const maxRetries = 3;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (kDebugMode) {
          debugPrint('OppleLM3: Connection attempt $attempt/$maxRetries to device: ${device.platformName}');
        }
        
        // Clear GATT cache BEFORE connecting - helps with error 133
        try {
          if (kDebugMode) {
            debugPrint('OppleLM3: Clearing GATT cache before connection...');
          }
          await device.clearGattCache();
          if (kDebugMode) {
            debugPrint('OppleLM3: GATT cache cleared');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('OppleLM3: Failed to clear GATT cache: $e');
          }
        }
        
        // Add delay before connection attempt (helps with error 133)
        if (attempt > 1) {
          final delayMs = attempt * 500;
          if (kDebugMode) {
            debugPrint('OppleLM3: Waiting ${delayMs}ms before retry...');
          }
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        
        await device.connect(
          timeout: const Duration(seconds: 30),
          mtu: null,
          autoConnect: false, // Direct connection, more reliable with clearGattCache
        );
        
        if (kDebugMode) {
          debugPrint('OppleLM3: Connection successful!');
        }
        
        // Short delay after connection
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (kDebugMode) {
          debugPrint('OppleLM3: Discovering services...');
        }

      final services = await device.discoverServices();
      if (kDebugMode) {
        debugPrint('OppleLM3: Discovered ${services.length} services');
        for (final s in services) {
          debugPrint('OppleLM3:   Service: ${s.uuid.toString()}');
          for (final c in s.characteristics) {
            debugPrint('OppleLM3:     Char: ${c.uuid.toString()} (write: ${c.properties.write}, writeNoResp: ${c.properties.writeWithoutResponse}, notify: ${c.properties.notify}, read: ${c.properties.read})');
          }
        }
      }
      
      BluetoothService? lm3;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == serviceUuid) {
          lm3 = s;
          break;
        }
      }
      if (lm3 == null) {
        if (kDebugMode) {
          debugPrint('OppleLM3: ERROR - Service UUID not found: $serviceUuid');
          debugPrint('OppleLM3: HINT - Available service UUIDs:');
          for (final s in services) {
            debugPrint('OppleLM3:        ${s.uuid.toString()}');
          }
        }
        return false;
      }
      if (kDebugMode) {
        debugPrint('OppleLM3: Found target service');
      }

      BluetoothCharacteristic? rx;
      BluetoothCharacteristic? tx;
      
      if (kDebugMode) {
        debugPrint('OppleLM3: Found ${lm3.characteristics.length} characteristics');
      }
      
      for (final c in lm3.characteristics) {
        final id = c.uuid.toString().toLowerCase();
        if (kDebugMode) {
          debugPrint('OppleLM3:   Char: $id (write: ${c.properties.write}, writeNoResp: ${c.properties.writeWithoutResponse}, notify: ${c.properties.notify})');
        }
        if (id == rxCharacteristicUuid) rx = c;
        if (id == txCharacteristicUuid) tx = c;
      }

      // Typical UART is write->RX notify->TX, but TS reference writes to TX.
      // We pick whichever is writable, preferring RX.
      _writeChar = _pickWritable(rx) ?? _pickWritable(tx);
      _notifyChar = tx;

      if (kDebugMode) {
        debugPrint('OppleLM3: Write char: ${_writeChar?.uuid.toString() ?? "NULL"}');
        debugPrint('OppleLM3: Notify char: ${_notifyChar?.uuid.toString() ?? "NULL"}');
      }

      if (_writeChar == null || _notifyChar == null) {
        if (kDebugMode) {
          debugPrint('OppleLM3: ERROR - Missing write or notify characteristic');
        }
        return false;
      }

      _notifySubscription?.cancel();
      _notifySubscription = _notifyChar!.onValueReceived.listen(_onNotification);
      device.cancelWhenDisconnected(_notifySubscription!);
      await _notifyChar!.setNotifyValue(true);

      if (kDebugMode) {
        debugPrint('OppleLM3: Notifications enabled, requesting calibration...');
      }

      // Read calibration matrix (kSensor) first.
      // LM4 may take longer to respond, so use longer timeout
      final calMsg = await _sendCommandAwaitResponse(
        _reqReadM3, 
        expectedResponse: _resReadM3,
        timeout: const Duration(seconds: 10),
      );
      _parseCalibration(calMsg);

      if (kDebugMode) {
        debugPrint('OppleLM3: Calibration matrix length: ${_kSensor.length}');
        if (_kSensor.length == 7) {
          debugPrint('OppleLM3: Calibration values: ${_kSensor.map((v) => v.toStringAsFixed(6)).join(", ")}');
        }
      }

      return _kSensor.length == 7;
      
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('OppleLM3: ERROR during connect attempt $attempt: $e');
        debugPrint('OppleLM3: Stack trace: $st');
      }
      
      // Disconnect before retry
      try {
        await device.disconnect();
      } catch (_) {}
      
      // If this was the last attempt, return false
      if (attempt == maxRetries) {
        return false;
      }
      // Otherwise, continue to next retry
    }
  }
  
  return false; // All retries exhausted
}

  void startMeasuring({Duration interval = const Duration(milliseconds: 500), double avgPeriodSeconds = 2.0}) {
    stopMeasuring();
    _coeffA = _lpfGetA(avgPeriodSeconds, interval.inMilliseconds / 1000.0);

    _measTimer = Timer.periodic(interval, (_) async {
      if (_inflight) return;
      if (_device == null) return;

      _inflight = true;
      try {
        final msg = await _sendCommandAwaitResponse(_reqMeas, expectedResponse: _resMeas);
        final measurement = _parseMeasurement(msg);
        if (measurement != null) {
          _measurements.add(measurement);
        }
      } finally {
        _inflight = false;
      }
    });
  }

  void stopMeasuring() {
    _measTimer?.cancel();
    _measTimer = null;
  }

  Future<void> disconnect() async {
    stopMeasuring();
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    try {
      await _notifyChar?.setNotifyValue(false);
    } catch (_) {
      // ignore
    }

    final d = _device;
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _pending.clear();

    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {
        // ignore
      }
    }
  }

  BluetoothCharacteristic? _pickWritable(BluetoothCharacteristic? c) {
    if (c == null) return null;
    if (c.properties.write || c.properties.writeWithoutResponse) return c;
    return null;
  }

  Future<Uint8List> _sendCommandAwaitResponse(
    int opCode, {
    required int expectedResponse,
    List<int>? body,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final completer = Completer<Uint8List>();
    _pending[expectedResponse] = completer;

    try {
      await _sendCommand(opCode, body: body);
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(expectedResponse);
    }
  }

  Future<void> _sendCommand(int opCode, {List<int>? body}) async {
    final ch = _writeChar;
    if (ch == null) throw StateError('Not connected');

    _seqNo = (_seqNo + 1) & 0xFF;

    final payloadLen = body?.length ?? 0;

    final header = <int>[
      0x00,
      0x13,
      0x00,
      0x00,
      _seqNo,
      0x00,
      payloadLen,
      0x00,
      0x00,
      (opCode & 0xFF00) >> 8,
      opCode & 0xFF,
    ];

    final data = <int>[...header, if (body != null) ...body];
    final frames = _encapsulateData(data);

    for (final frame in frames) {
      // writeValue expects Uint8List
      await ch.write(Uint8List.fromList(frame), withoutResponse: ch.properties.writeWithoutResponse);
    }
  }

  List<List<int>> _encapsulateData(List<int> data) {
    final nFragments = data.length < 17 ? 1 : ((data.length - 17) / 19.0).ceil() + 1;
    final frames = <List<int>>[];

    for (var c = 0; c < nFragments; c++) {
      List<int> head;
      List<int> chunk;

      if (c == 0) {
        final totalLen = data.length + nFragments + 2;
        head = [
          nFragments > 1 ? _msgFfrag : _msgSingle,
          (totalLen & 0xFF00) >> 8,
          totalLen & 0xFF,
        ];
        chunk = nFragments > 1 ? data.sublist(0, 17) : data;
      } else {
        final start = 17 + 19 * (c - 1);
        final endExclusive = math.min(17 + 19 * c, data.length);

        if (c != nFragments - 1) {
          head = [_msgMfrag | c];
          chunk = data.sublist(start, endExclusive);
        } else {
          head = [_msgLfrag | c];
          chunk = data.sublist(start);
        }
      }

      frames.add([...head, ...chunk]);
    }

    return frames;
  }

  void _onNotification(List<int> data) {
    if (data.isEmpty) return;

    if (kDebugMode) {
      debugPrint('OppleLM3: Received notification (${data.length} bytes): ${data.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    }

    final msgType = data[0] & 0xE0;

    try {
      if (msgType == _msgSingle) {
        if (data.length < 4) return;
        final payload = Uint8List.fromList(data.sublist(3));
        _parseMsg(payload);
        return;
      }

      if (msgType == _msgFfrag) {
        if (data.length < 4) return;
        final totalLen = (data[1] << 8) | data[2];
        _rxBuffer = Uint8List(totalLen);
        final payload = data.sublist(3);
        _rxBuffer!.setRange(0, payload.length, payload);
        _rxBufferLen = payload.length;
        return;
      }

      if (msgType == _msgMfrag || msgType == _msgLfrag) {
        final buf = _rxBuffer;
        if (buf == null) return;
        final payload = data.sublist(1);
        buf.setRange(_rxBufferLen, _rxBufferLen + payload.length, payload);
        _rxBufferLen += payload.length;

        if (msgType == _msgLfrag) {
          final assembled = Uint8List.sublistView(buf, 0, _rxBufferLen);
          _parseMsg(assembled);
          _rxBuffer = null;
          _rxBufferLen = 0;
        }
      }
    } catch (_) {
      // ignore
    }
  }

  void _parseMsg(Uint8List msg) {
    if (kDebugMode) {
      debugPrint('OppleLM3: Parsing message (${msg.length} bytes): ${msg.sublist(0, math.min(20, msg.length)).map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    }
    
    if (msg.length < 11) {
      if (kDebugMode) {
        debugPrint('OppleLM3: Message too short');
      }
      return;
    }
    final code = (msg[9] << 8) | msg[10];
    
    if (kDebugMode) {
      debugPrint('OppleLM3: Response code: $code (0x${code.toRadixString(16)})');
    }

    final completer = _pending[code];
    if (completer != null && !completer.isCompleted) {
      if (kDebugMode) {
        debugPrint('OppleLM3: Completing pending request for code $code');
      }
      completer.complete(msg);
    } else {
      if (kDebugMode) {
        debugPrint('OppleLM3: No pending request for code $code (completer: ${completer != null}, completed: ${completer?.isCompleted})');
      }
    }
  }

  void _parseCalibration(Uint8List msg) {
    // Mirrors TS:
    // code at [9..10], then (usually) a status byte at [11], then floats start at [12]
    if (kDebugMode) {
      debugPrint('OppleLM3: Parsing calibration message (${msg.length} bytes)');
      debugPrint('OppleLM3: First bytes: ${msg.sublist(0, math.min(20, msg.length)).map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    }
    
    if (msg.length < 42) {
      if (kDebugMode) {
        debugPrint('OppleLM3: ERROR - Calibration message too short (${msg.length} < 42)');
      }
      _kSensor = const [];
      return;
    }

    final floats = <double>[];
    for (var i = 0; i < 7; i++) {
      final start = 12 + 4 * i;
      final bd = ByteData.sublistView(msg, start, start + 4);
      floats.add(bd.getFloat32(0, Endian.little));
    }

    _kSensor = floats;
  }

  OppleLm3Measurement? _parseMeasurement(Uint8List msg) {
    if (_kSensor.length != 7) {
      if (kDebugMode) {
        debugPrint('OppleLM3: Cannot parse measurement - invalid calibration (length: ${_kSensor.length})');
      }
      return null;
    }

    // TS does: parseMeasurementData(data.subarray(11), ...)
    if (msg.length < 11 + 16) {
      if (kDebugMode) {
        debugPrint('OppleLM3: Cannot parse measurement - message too short (${msg.length} bytes)');
      }
      return null;
    }
    final data = Uint8List.sublistView(msg, 11);

    // data[0] appears to be a status/flag byte; channels begin at data[1]
    final v0 = (data[1] << 8) | data[2];
    final b0 = (data[3] << 8) | data[4];
    final g0 = (data[5] << 8) | data[6];
    final y0 = (data[7] << 8) | data[8];
    final o0 = (data[9] << 8) | data[10];
    final r0 = (data[11] << 8) | data[12];
    final battery = (data[13] << 8) | data[14];
    final temperature = data[15];

    final channelsRaw = <int>[v0, b0, g0, y0, o0, r0];

    final v1 = _lpfNext(_coeffA, _prevMeas[0], v0 * _kSensor[0]);
    final b1 = _lpfNext(_coeffA, _prevMeas[1], b0 * _kSensor[1]);
    final g1 = _lpfNext(_coeffA, _prevMeas[2], g0 * _kSensor[2]);
    final y1 = _lpfNext(_coeffA, _prevMeas[3], y0 * _kSensor[3]);
    final o1 = _lpfNext(_coeffA, _prevMeas[4], o0 * _kSensor[4]);
    final r1 = _lpfNext(_coeffA, _prevMeas[5], r0 * _kSensor[5]);
    final c1 = _kSensor[6];

    _prevMeas[0] = v1;
    _prevMeas[1] = b1;
    _prevMeas[2] = g1;
    _prevMeas[3] = y1;
    _prevMeas[4] = o1;
    _prevMeas[5] = r1;

    final sum = v1 + b1 + g1 + y1 + o1 + r1;
    final mode = _lightMode(v1, b1, g1, y1, o1, r1, sum);

    final m = _tristimulusMatrix(mode);
    final x = m[0][0] * v1 + m[0][1] * b1 + m[0][2] * g1 + m[0][3] * y1 + m[0][4] * o1 + m[0][5] * r1 + m[0][6] * c1;
    final y = m[1][0] * v1 + m[1][1] * b1 + m[1][2] * g1 + m[1][3] * y1 + m[1][4] * o1 + m[1][5] * r1 + m[1][6] * c1;
    final z = m[2][0] * v1 + m[2][1] * b1 + m[2][2] * g1 + m[2][3] * y1 + m[2][4] * o1 + m[2][5] * r1 + m[2][6] * c1;

    final denom = x + y + z;
    double cx = 0;
    double cy = 0;
    if (denom > 0) {
      cx = x / denom;
      cy = y / denom;
    }

    final (cu, cv) = _xy2uv(cx, cy);
    final duv = _calcDuv(cu, cv);
    final tint = _calcTint(cx, cy);

    final lux = y.isFinite && y > 0 ? y : 0.0;
    final cct = _calcCctTsMcCamy(cx, cy);

    return OppleLm3Measurement(
      lux: lux,
      cct: cct,
      cieX: cx,
      cieY: cy,
      cieU: cu,
      cieV: cv,
      duv: duv,
      tint: tint,
      temperature: temperature,
      batteryMv: battery,
      rawChannels: channelsRaw,
      correctedChannels: [v1, b1, g1, y1, o1, r1],
      mode: mode,
    );
  }

  double _lpfGetA(double avgPeriodSeconds, double sampleIntervalSeconds) {
    if (avgPeriodSeconds <= 0) return 0;
    return math.exp(-(sampleIntervalSeconds / avgPeriodSeconds));
  }

  double _lpfNext(double a, double prev, double sample) {
    // Same as TS: prev * a + sample * (1-a)
    return a * prev + (1.0 - a) * sample;
  }

  int _lightMode(double v, double b, double g, double y, double o, double r, double sum) {
    if (sum <= 0) return 3;
    final a = (o + r) / sum;
    final bb = (r - y) / sum;

    final mx = math.max(v, math.max(b, math.max(g, math.max(y, math.max(o, r)))));
    if (mx / sum >= 0.45) return 1;
    if (a >= 0.5 && a <= 0.55 && bb >= 0 && bb <= 0.05) return 2;
    return 3;
  }

  List<List<double>> _tristimulusMatrix(int mode) {
    // These are copied from the TS reference (tristimulusM)
    switch (mode) {
      case 1:
        return const [
          [0.06023, 0.00106, 0.02108, 0.03673, 0.1683, 0.02001, 0],
          [0.00652, 0.04478, 0.16998, -0.03268, 0.07425, 0.00739, 0],
          [0.33092, 0.12936, -0.15809, 0.19889, -0.0156, 0.00296, 0],
        ];
      case 2:
        return const [
          [-0.43786, 0.53102, -0.1453, 0.2316, 0.36758, -0.09047, 0],
          [-0.23226, 0.69225, -0.39786, 0.22539, 0.47947, -0.17614, 0],
          [-0.11002, 1.21259, -0.56003, 0.14487, 0.35074, -0.30248, 0],
        ];
      default:
        return const [
          [-0.05825, -0.0896, 0.25859, 0.19518, 0.10893, 0.06724, 0],
          [-0.19865, 0.01337, 0.40651, 0.29702, -0.06287, 0.03282, 0],
          [0.58258, 0.11548, 0.21823, -0.00136, -0.10732, -0.00915, 0],
        ];
    }
  }

  double _calcCctTsMcCamy(double x, double y) {
    // Replicates lib-opple/cct.ts exactly.
    // McCamy’s (CCT) formula:
    // n = (x - 0.332) / (0.1858 - y)
    final n = (x - 0.332) / (0.1858 - y);
    final cct = 449 * n * n * n + 3525 * n * n + 6823.3 * n + 5520.33;
    return cct;
  }

  (double, double) _xy2uv(double x, double y) {
    // Mirrors lib-opple/CIEConv.ts (xy2uv)
    final nj = -2 * x + 12 * y + 3;
    if (nj == 0) return (double.nan, double.nan);
    final u = (4 * x) / nj;
    final v = (6 * y) / nj;
    return (u, v);
  }

  double _calcDuv(double u, double v) {
    // Mirrors lib-opple/duv.ts (ANSI C78.377-2011)
    const k = [-0.471106, 1.925865, -2.4243787, 1.5317403, -0.5179722, 0.0893944, -0.00616793];
    final lfp = math.sqrt(math.pow(u - 0.292, 2) + math.pow(v - 0.24, 2));
    if (lfp == 0) return 0;
    final a = math.acos((u - 0.292) / lfp);
    final lbb =
        k[6] * math.pow(a, 6) +
        k[5] * math.pow(a, 5) +
        k[4] * math.pow(a, 4) +
        k[3] * math.pow(a, 3) +
        k[2] * math.pow(a, 2) +
        k[1] * a +
        k[0];
    return lfp - lbb;
  }

  double _calcTint(double x, double y) {
    // Ported from lib-opple/tint.ts; we only return the tint component.
    const kTintScale = -3000.0;

    // Flattened table rows [r,u,v,t] for r = {0,10,...,600}
    const kTempTable = <double>[
      0, 0.18006, 0.26352, -0.24341,
      10, 0.18066, 0.26589, -0.25479,
      20, 0.18133, 0.26846, -0.26876,
      30, 0.18208, 0.27119, -0.28539,
      40, 0.18293, 0.27407, -0.3047,
      50, 0.18388, 0.27709, -0.32675,
      60, 0.18494, 0.28021, -0.35156,
      70, 0.18611, 0.28342, -0.37915,
      80, 0.1874, 0.28668, -0.40955,
      90, 0.1888, 0.28997, -0.44278,
      100, 0.19032, 0.29326, -0.47888,
      125, 0.19462, 0.30141, -0.58204,
      150, 0.19962, 0.30921, -0.70471,
      175, 0.20525, 0.31647, -0.84901,
      200, 0.21142, 0.32312, -1.0182,
      225, 0.21807, 0.32909, -1.2168,
      250, 0.22511, 0.33439, -1.4512,
      275, 0.23247, 0.33904, -1.7298,
      300, 0.2401, 0.34308, -2.0637,
      325, 0.24702, 0.34655, -2.4681,
      350, 0.25591, 0.34951, -2.9641,
      375, 0.264, 0.352, -3.5814,
      400, 0.27218, 0.35407, -4.3633,
      425, 0.28039, 0.35577, -5.3762,
      450, 0.28863, 0.35714, -6.7262,
      475, 0.29685, 0.35823, -8.5955,
      500, 0.30505, 0.35907, -11.324,
      525, 0.3132, 0.35968, -15.628,
      550, 0.32129, 0.36011, -23.325,
      575, 0.32931, 0.36038, -40.77,
      600, 0.33724, 0.36051, -116.45,
    ];

    final denom = (1.5 - x + 6.0 * y);
    if (denom == 0) return 0;
    final u = (2.0 * x) / denom;
    final v = (3.0 * y) / denom;

    var lastDt = 0.0;
    var lastDv = 0.0;
    var lastDu = 0.0;

    for (var i = 1; i <= 30; i++) {
      var du = 1.0;
      var dv = kTempTable[i * 4 + 3];
      var len = math.sqrt(1.0 + dv * dv);
      du /= len;
      dv /= len;

      var uu = u - kTempTable[i * 4 + 1];
      var vv = v - kTempTable[i * 4 + 2];

      var dt = -uu * dv + vv * du;
      if (dt <= 0.0 || i == 30) {
        if (dt > 0.0) dt = 0.0;
        dt = -dt;

        final f = i == 1 ? 0.0 : dt / (lastDt + dt);

        // recompute uu/vv for interpolated blackbody point
        uu = u - (kTempTable[(i - 1) * 4 + 1] * f + kTempTable[i * 4 + 1] * (1.0 - f));
        vv = v - (kTempTable[(i - 1) * 4 + 2] * f + kTempTable[i * 4 + 2] * (1.0 - f));

        du = du * (1.0 - f) + lastDu * f;
        dv = dv * (1.0 - f) + lastDv * f;
        len = math.sqrt(du * du + dv * dv);
        du /= len;
        dv /= len;

        final fTint = (uu * du + vv * dv) * kTintScale;
        return fTint;
      }

      lastDt = dt;
      lastDu = du;
      lastDv = dv;
    }

    return 0;
  }
}
