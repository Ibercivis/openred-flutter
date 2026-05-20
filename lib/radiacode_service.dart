import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class RadiaCodeService {
  // UUIDs del protocolo RadiaCode
  static const String serviceUuid = 'e63215e5-7003-49d8-96b0-b024798fb901';
  static const String writeCharUuid = 'e63215e6-7003-49d8-96b0-b024798fb901';
  static const String notifyCharUuid = 'e63215e7-7003-49d8-96b0-b024798fb901';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription? _notifySubscription;

  int _seq = 0;
  List<int> _responseBuffer = [];
  int _expectedSize = 0;
  Completer<List<int>>? _responseCompleter;

  // Comandos del protocolo RadiaCode
  static const int cmdSetExchange = 0x0007;
  static const int cmdReadVirtString = 0x0826;
  static const int cmdWriteVirtSfr = 0x0825;
  static const int cmdReadVirtSfrBatch = 0x082A;
  
  // Virtual Strings
  static const int vsDataBuf = 0x100;
  static const int vsSpectrum = 0x200;
  
  // Virtual SFRs
  static const int vsfrDoseReset = 0x8007;
  static const int vsfrDoseUnits = 0x8004; // VSFR::DS_UNITS
  static const int vsfrCountRateUnits = 0x8013; // VSFR::CR_UNITS

  // Unit state (queried from device)
  MeasurementUnits _doseUnits = MeasurementUnits.roentgen;
  CountRateUnits _countRateUnits = CountRateUnits.cps;

  DateTime? _lastParseDebugPrint;

  Future<bool> connect(BluetoothDevice device) async {
    try {
      _device = device;
      
      // Conectar al dispositivo (mtu: null para evitar negociación automática)
      await device.connect(timeout: const Duration(seconds: 15), mtu: null);
      print('Connected to device');
      
      // Esperar un momento después de conectar
      await Future.delayed(const Duration(milliseconds: 500));
      
      print('SKIPPING MTU REQUEST (Arduino compatibility)');
      
      // Esperar un poco más
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Descubrir servicios
      print('Discovering services...');
      List<BluetoothService> services = await device.discoverServices();
      print('Found ${services.length} services');
      
      // Esperar después de descubrir servicios
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Buscar el servicio RadiaCode
      for (var service in services) {
        print('Service: ${service.uuid}');
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          print('Found RadiaCode service!');
          // Encontrar características
          for (var char in service.characteristics) {
            print('  Characteristic: ${char.uuid}');
            if (char.uuid.toString().toLowerCase() == writeCharUuid.toLowerCase()) {
              _writeChar = char;
              print('  -> Write characteristic found');
            } else if (char.uuid.toString().toLowerCase() == notifyCharUuid.toLowerCase()) {
              _notifyChar = char;
              print('  -> Notify characteristic found');
            }
          }
        }
      }
      
      if (_writeChar == null || _notifyChar == null) {
        print('RadiaCode characteristics not found');
        return false;
      }
      
      // Verificar propiedades de la característica de escritura
      print('Write characteristic properties:');
      print('  canWrite: ${_writeChar!.properties.write}');
      print('  canWriteWithoutResponse: ${_writeChar!.properties.writeWithoutResponse}');
      
      // Pequeño delay antes de habilitar notificaciones
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 1. Configurar el listener PRIMERO
      print('Setting up notification listener...');
      _notifySubscription = _notifyChar!.onValueReceived.listen((data) {
        print('Received notification: ${data.length} bytes');
        _handleNotification(data);
      });
      device.cancelWhenDisconnected(_notifySubscription!);

      // 2. Habilitar notificaciones (escribe en descriptor 0x2902)
      print('Enabling notifications...');
      await _notifyChar!.setNotifyValue(true);
      
      // 3. Esperar a que el descriptor se asiente
      print('Waiting for descriptor to be configured...');
      await Future.delayed(const Duration(seconds: 2));
      
      // Inicializar el dispositivo
      print('Initializing RadiaCode protocol...');
      await _initialize();

      // Leer unidades desde el dispositivo
      await _refreshUnits();
      
      print('RadiaCode ready!');
      return true;
    } catch (e) {
      print('Error connecting to RadiaCode: $e');
      return false;
    }
  }

  Future<void> _initialize() async {
    // Enviar comando de inicialización SET_EXCHANGE
    final initData = [0x01, 0xFF, 0x12, 0xFF];
    
    try {
      await _execute(cmdSetExchange, initData);
      print('RadiaCode initialized successfully');
    } catch (e) {
      print('Failed to initialize RadiaCode: $e');
      rethrow;
    }
  }

  ({int retcode, int flen, List<int> payload}) _parseRetcodeLenPayload(List<int> response) {
    if (response.length < 8) {
      throw Exception('Invalid response (too short): ${response.length} bytes');
    }

    final retcode = _bytesToUint32(response.sublist(0, 4));
    final flen = _bytesToUint32(response.sublist(4, 8));
    final remaining = response.sublist(8);

    // Workaround del driver Arduino: si hay un byte extra 0x00 al final, truncarlo.
    if (remaining.length == flen + 1 && remaining.isNotEmpty && remaining.last == 0x00) {
      return (retcode: retcode, flen: flen, payload: remaining.sublist(0, flen));
    }

    if (remaining.length < flen) {
      throw Exception('Invalid response payload: expected $flen bytes, got ${remaining.length}');
    }

    return (retcode: retcode, flen: flen, payload: remaining.sublist(0, flen));
  }

  Future<void> _refreshUnits() async {
    // RD_VIRT_SFR_BATCH payload:
    // [count_u32][vsfr_id_u32...]
    final args = <int>[
      ..._uint32ToBytes(2),
      ..._uint32ToBytes(vsfrDoseUnits),
      ..._uint32ToBytes(vsfrCountRateUnits),
    ];

    // IMPORTANTE: RD_VIRT_SFR_BATCH NO devuelve (retcode + flen).
    // En el driver Arduino se interpreta directamente como:
    // [valid_flags_u32][value1_u32][value2_u32]...
    final response = await _execute(cmdReadVirtSfrBatch, args);

    if (response.length < 12) {
      throw Exception('Invalid VSFR batch response length: ${response.length}');
    }

    final validFlags = _bytesToUint32(response.sublist(0, 4));
    final doseUnitsRaw = _bytesToUint32(response.sublist(4, 8));
    final countUnitsRaw = _bytesToUint32(response.sublist(8, 12));

    // Arduino trata DS_UNITS y CR_UNITS como boolean (LSB)
    // MeasurementUnits: 0=ROENTGEN, 1=SIEVERT
    // CountRateUnits: 0=CPS, 1=CPM
    if ((validFlags & 0x01) != 0) {
      _doseUnits = (doseUnitsRaw & 0x01) == 1 ? MeasurementUnits.sievert : MeasurementUnits.roentgen;
    }
    if ((validFlags & 0x02) != 0) {
      _countRateUnits = (countUnitsRaw & 0x01) == 1 ? CountRateUnits.cpm : CountRateUnits.cps;
    }

    print('Units: dose=${_doseUnits.name}, count=${_countRateUnits.name} (validFlags=0x${validFlags.toRadixString(16)})');
  }

  void _handleNotification(List<int> data) {
    if (_responseCompleter == null || _responseCompleter!.isCompleted) {
      return;
    }

    if (_expectedSize == 0 && data.length >= 4) {
      // Primer paquete: contiene el tamaño total
      _expectedSize = _bytesToUint32(data.sublist(0, 4));
      _responseBuffer = List<int>.from(data);
    } else {
      // Paquetes siguientes: agregar datos
      _responseBuffer.addAll(data);
    }

    // Verificar si recibimos todos los datos (Header 4 bytes + Payload _expectedSize)
    if (_responseBuffer.length >= _expectedSize + 4) {
      _responseCompleter?.complete(List<int>.from(_responseBuffer));
      _responseBuffer = [];
      _expectedSize = 0;
    }
  }

  Future<List<int>> _execute(int command, [List<int>? args]) async {
    if (_writeChar == null) {
      throw Exception('Not connected to RadiaCode');
    }

    // Incrementar y obtener número de secuencia
    // Forzar 0 al inicio como en Arduino
    if (_seq == 0) {
      _seq = 0;
    }
    int seqNo = 0x80 + _seq;
    _seq = (_seq + 1) % 32;

    // Construir header del comando
    List<int> header = [
      command & 0xFF,
      (command >> 8) & 0xFF,
      0x00,
      seqNo,
    ];

    // Construir request (sin prefijo de longitud)
    List<int> request = [...header];
    if (args != null && args.isNotEmpty) {
      request.addAll(args);
    }

    // IMPORTANTE (como en Arduino): prefijo de 4 bytes con la longitud (little-endian)
    // El dispositivo espera: [len_u32][cmd_header(4)][args...]
    final fullRequest = <int>[..._uint32ToBytes(request.length), ...request];

    print(
      'Sending command 0x${command.toRadixString(16)} (payload ${request.length} bytes, total ${fullRequest.length} bytes)',
    );

    // Preparar para recibir respuesta
    _responseCompleter = Completer<List<int>>();
    _responseBuffer = [];
    _expectedSize = 0;

    // IMPORTANTE: Enviar en chunks de 18 bytes como hace el código Arduino
    // Esto evita problemas con el MTU y el stack BLE
    const int chunkSize = 18;
    int retries = 3;
    bool allSent = false;
    
    while (retries > 0 && !allSent) {
      try {
        // Esperar un poco antes de cada intento
        if (retries < 3) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        
        // Enviar en chunks
        for (int pos = 0; pos < fullRequest.length; pos += chunkSize) {
          int remaining = fullRequest.length - pos;
          int toSend = (remaining > chunkSize) ? chunkSize : remaining;
          
          List<int> chunk = fullRequest.sublist(pos, pos + toSend);
          
          // FORZAR withoutResponse: true
          // writeWithResponse causa error 133 fatal.
          // Usamos withoutResponse y aumentamos delays para asegurar recepción.
          bool withoutResponse = true;
          
          String hexChunk = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          print('  Sending chunk: $hexChunk (withoutResponse: $withoutResponse)');
          
          await _writeChar!.write(chunk, withoutResponse: withoutResponse);
          
          // Delay aumentado entre chunks (50ms) para dar tiempo al dispositivo
          if (pos + toSend < request.length) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
        
        allSent = true;
        print('Command sent successfully in ${(fullRequest.length / chunkSize).ceil()} chunk(s)');
        
        // Delay después de enviar todo
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        retries--;
        print('Write failed (retries left: $retries): $e');
        if (retries <= 0) {
          _responseCompleter = null;
          rethrow;
        }
      }
    }

    // Esperar respuesta (timeout 10 segundos)
    try {
      final rawResponseWithSize = await _responseCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _responseCompleter = null;
          throw TimeoutException('RadiaCode response timeout');
        },
      );

      // El flujo notify incluye un prefijo de tamaño de 4 bytes.
      // Arduino BluetoothTransport lo descarta antes de devolver el buffer.
      if (rawResponseWithSize.length < 8) {
        throw Exception('Invalid RadiaCode response (too short): ${rawResponseWithSize.length} bytes');
      }

      final responseNoSize = rawResponseWithSize.sublist(4);

      // Arduino RadiaCode::execute consume el header de 4 bytes (cmd/seq) antes de
      // devolver el buffer al nivel superior. Hacemos lo mismo aquí.
      if (responseNoSize.length < 4) {
        throw Exception('Invalid RadiaCode response (missing header)');
      }

      final respHeader = responseNoSize.sublist(0, 4);
      final expectedHeader = header;
      final headerMatches =
          respHeader.length == expectedHeader.length &&
          List.generate(respHeader.length, (i) => respHeader[i] == expectedHeader[i]).every((v) => v);

      if (!headerMatches) {
        final expHex = expectedHeader.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        final gotHex = respHeader.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        print('Warning: response header mismatch. expected=$expHex got=$gotHex');
      }

      final responseNoSizeNoHeader = responseNoSize.sublist(4);

      print(
        'Received response: raw=${rawResponseWithSize.length} bytes, noSize=${responseNoSize.length} bytes, noHeader=${responseNoSizeNoHeader.length} bytes',
      );
      return responseNoSizeNoHeader;
    } catch (e) {
      print('Error waiting for response: $e');
      _responseCompleter = null;
      rethrow;
    }
  }

  Future<List<int>> _readVirtualString(int vsId) async {
    // Construir argumentos: ID del virtual string (4 bytes)
    List<int> args = _uint32ToBytes(vsId);
    
    // Ejecutar comando
    final response = await _execute(cmdReadVirtString, args);
    final parsed = _parseRetcodeLenPayload(response);

    if (parsed.retcode != 1) {
      print('Warning: RD_VIRT_STRING retcode=${parsed.retcode} (vsId=0x${vsId.toRadixString(16)})');
    }

    return parsed.payload;
  }

  Future<RadiaCodeData> readData() async {
    try {
      // Leer DATA_BUF que contiene las mediciones en tiempo real
      List<int> data = await _readVirtualString(vsDataBuf);
      
      // Parsear el buffer de datos
      return _parseDataBuf(data);
    } catch (e) {
      print('Error reading RadiaCode data: $e');
      rethrow;
    }
  }

  RadiaCodeData _parseDataBuf(List<int> data) {
    double? countRate;
    double? countRateErr;
    double? doseRate;
    double? doseRateErr;

    int? chosenEid;
    int? chosenGid;
    String? chosenGroup;
    
    int pos = 0;
    
    // Parsear los paquetes del DATA_BUF
    while (pos + 7 <= data.length) {
      // int seq = data[pos];
      int eid = data[pos + 1];
      int gid = data[pos + 2];
      // int tsOffset = _bytesToInt32(data.sublist(pos + 3, pos + 7));
      
      pos += 7;
      
      // GRP_RealTimeData (eid=0, gid=0)
      if (eid == 0 && gid == 0) {
        // Layout (según Decoders.cpp):
        // float count_rate (4) + float dose_rate (4) + u16 + u16 + u16 + u8 = 15 bytes
        if (pos + 15 <= data.length) {
          countRate = _bytesToFloat(data.sublist(pos, pos + 4));
          doseRate = _bytesToFloat(data.sublist(pos + 4, pos + 8));
          // Errors are uint16 and must be scaled by /10.0 (see Arduino Decoders.cpp)
          final rawCountRateErr = _bytesToUint16(data.sublist(pos + 8, pos + 10));
          final rawDoseRateErr = _bytesToUint16(data.sublist(pos + 10, pos + 12));
          countRateErr = rawCountRateErr / 10.0;
          doseRateErr = rawDoseRateErr / 10.0;

          chosenEid = eid;
          chosenGid = gid;
          chosenGroup = 'RealTimeData';
          pos += 15;
          break; // Tomamos el primer RealTimeData
        }
      }
      // GRP_RawData (eid=0, gid=1)
      else if (eid == 0 && gid == 1) {
        if (pos + 8 <= data.length) {
          countRate = _bytesToFloat(data.sublist(pos, pos + 4));
          doseRate = _bytesToFloat(data.sublist(pos + 4, pos + 8));

          chosenEid = eid;
          chosenGid = gid;
          chosenGroup = 'RawData';
          pos += 8;
          break;
        }
      }
      // GRP_DoseRateDB (eid=0, gid=2)
      else if (eid == 0 && gid == 2) {
        if (pos + 16 <= data.length) {
          // Omitir count (4 bytes)
          countRate = _bytesToFloat(data.sublist(pos + 4, pos + 8));
          doseRate = _bytesToFloat(data.sublist(pos + 8, pos + 12));
          final rawDoseRateErr = _bytesToUint16(data.sublist(pos + 12, pos + 14));
          doseRateErr = rawDoseRateErr / 10.0;

          chosenEid = eid;
          chosenGid = gid;
          chosenGroup = 'DoseRateDB';
          pos += 16;
          break;
        }
      }
      // GRP_RawDoseRate (eid=0, gid=9)
      else if (eid == 0 && gid == 9) {
        // Layout (según Decoders.cpp): float dose_rate (4) + u16 flags (2)
        if (pos + 6 <= data.length) {
          doseRate = _bytesToFloat(data.sublist(pos, pos + 4));
          countRate ??= 0.0;

          chosenEid = eid;
          chosenGid = gid;
          chosenGroup = 'RawDoseRate';
          pos += 6;
          break;
        }
      }
      else {
        // Tipo desconocido, saltar este paquete
        // Intentar avanzar al siguiente
        break;
      }
    }

    final now = DateTime.now();
    final last = _lastParseDebugPrint;
    if (last == null || now.difference(last).inSeconds >= 5) {
      _lastParseDebugPrint = now;
      // ignore: avoid_print
      print(
        '[RadiaCodeParse] bytes=${data.length} chosen=${chosenGroup ?? 'none'} eid=${chosenEid ?? -1} gid=${chosenGid ?? -1} '
        'countRate=$countRate countRateErr=$countRateErr doseRate=$doseRate doseRateErr=$doseRateErr '
        'units count=${_countRateUnits.name} dose=${_doseUnits.name}',
      );
    }
    
    return RadiaCodeData(
      countRate: countRate,
      countRateErr: countRateErr,
      doseRate: doseRate,
      doseRateErr: doseRateErr,
      countRateUnits: _countRateUnits,
      measurementUnits: _doseUnits,
    );
  }

  Future<void> resetDose() async {
    // Escribir VSFR para resetear dosis
    List<int> args = [
      ..._uint32ToBytes(vsfrDoseReset),
      ..._uint32ToBytes(1), // valor = 1 para reset
    ];
    await _execute(cmdWriteVirtSfr, args);
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    
    if (_device != null) {
      await _device!.disconnect();
      _device = null;
    }
    
    _writeChar = null;
    _notifyChar = null;
    _responseCompleter = null;
  }

  // Utilidades para conversión de bytes
  
  int _bytesToUint32(List<int> bytes) {
    return bytes[0] | 
           (bytes[1] << 8) | 
           (bytes[2] << 16) | 
           (bytes[3] << 24);
  }
  
  int _bytesToInt32(List<int> bytes) {
    int value = _bytesToUint32(bytes);
    // Convertir a signed
    if (value & 0x80000000 != 0) {
      return value - 0x100000000;
    }
    return value;
  }
  
  double _bytesToFloat(List<int> bytes) {
    ByteData byteData = ByteData(4);
    for (int i = 0; i < 4; i++) {
      byteData.setUint8(i, bytes[i]);
    }
    return byteData.getFloat32(0, Endian.little);
  }

  int _bytesToUint16(List<int> bytes) {
    return bytes[0] | (bytes[1] << 8);
  }
  
  List<int> _uint32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }
}

class RadiaCodeData {
  final double? countRate; // Valor raw según unidad configurada
  // Device-reported relative error for count rate (percent units after parsing).
  // Example: 5.0 means ±5%.
  final double? countRateErr;
  final double? doseRate;  // Valor raw según unidad configurada
  // Device-reported relative error for dose rate (percent units after parsing).
  // Example: 3.2 means ±3.2%.
  final double? doseRateErr;
  final CountRateUnits countRateUnits;
  final MeasurementUnits measurementUnits;
  
  RadiaCodeData({
    this.countRate,
    this.countRateErr,
    this.doseRate,
    this.doseRateErr,
    required this.countRateUnits,
    required this.measurementUnits,
  });
  
  // Valor normalizado a CPS
  // Device always reports in CPS, so no conversion needed.
  double? get cps {
    if (countRate == null) return null;
    // return countRateUnits == CountRateUnits.cpm ? (countRate! / 60.0) : countRate;
    return countRate;
  }

  double? get cpsErr {
    // Expose as fraction (0..1) to be rendered as percent in UI.
    if (countRateErr == null) return null;
    return countRateErr! / 100.0;
  }

  // Valor normalizado a CPM
  double? get cpm {
    if (countRate == null) return null;
    return countRateUnits == CountRateUnits.cpm ? countRate : (countRate! * 60.0);
  }

  double? get cpmErr {
    // Expose as fraction (0..1) to be rendered as percent in UI.
    if (countRateErr == null) return null;
    return countRateErr! / 100.0;
  }

  // Conversión a µSv/h
  // El stream entrega el valor raw en unidades base:
  // - ROENTGEN: R/h  -> µSv/h = × 1e4
  // - SIEVERT:  Sv/h -> µSv/h = × 1e6
  double? get doseMicroSvPerHour {
    if (doseRate == null) return null;

    return _doseToMicroSvPerHour(doseRate!, cps);
  }

  double? get doseMicroSvPerHourErr {
    // Expose as fraction (0..1) to be rendered as percent in UI.
    if (doseRateErr == null) return null;
    return doseRateErr! / 100.0;
  }

  double _doseToMicroSvPerHour(double v, double? cpsNow) {
    // El raw del DATA_BUF siempre viene en la misma unidad base (R/h),
    // independientemente del flag measurementUnits (que solo afecta la
    // pantalla del dispositivo). Conversión idéntica a Arduino Basic.ino:
    //   doseRate * 10000.0f  →  µSv/h
    return v * 1e4;
  }

  String get rawDoseUnit {
    return measurementUnits == MeasurementUnits.sievert ? 'Sv/h' : 'R/h';
  }
}

enum MeasurementUnits {
  roentgen,
  sievert,
}

enum CountRateUnits {
  cps,
  cpm,
}
