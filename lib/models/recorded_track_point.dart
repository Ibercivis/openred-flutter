abstract class TrackPointBase {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracyMeters;

  const TrackPointBase({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracyMeters,
  });

  Map<String, dynamic> toJson();

  Map<String, dynamic> toJsonCommon() {
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracyMeters': accuracyMeters,
    };
  }
}

class RadiationTrackPoint extends TrackPointBase {
  final double? cpm;
  final double? cpmRelErr;
  final double? doseMicroSvPerHour;
  final double? doseMicroSvPerHourRelErr;

  const RadiationTrackPoint({
    required super.timestamp,
    required super.latitude,
    required super.longitude,
    required super.altitude,
    required super.accuracyMeters,
    required this.cpm,
    required this.cpmRelErr,
    required this.doseMicroSvPerHour,
    required this.doseMicroSvPerHourRelErr,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      ...toJsonCommon(),
      if (cpm != null) 'cpm': cpm,
      if (cpmRelErr != null) 'cpmRelErr': cpmRelErr,
      if (doseMicroSvPerHour != null) 'doseMicroSvPerHour': doseMicroSvPerHour,
      if (doseMicroSvPerHourRelErr != null) 'doseMicroSvPerHourRelErr': doseMicroSvPerHourRelErr,
    };
  }
}

class LightTrackPoint extends TrackPointBase {
  final double lux;
  final double? cct;
  final double? cieX;
  final double? cieY;
  final double? cieU;
  final double? cieV;
  final double? duv;
  final double? tint;
  final int? mode;
  final List<double>? channels;
  final int? temperature;
  final int? batteryMv;

  const LightTrackPoint({
    required super.timestamp,
    required super.latitude,
    required super.longitude,
    required super.altitude,
    required super.accuracyMeters,
    required this.lux,
    this.cct,
    this.cieX,
    this.cieY,
    this.cieU,
    this.cieV,
    this.duv,
    this.tint,
    this.mode,
    this.channels,
    this.temperature,
    this.batteryMv,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      ...toJsonCommon(),
      'lux': lux,
      if (cct != null) 'cct': cct,
      if (cieX != null) 'cieX': cieX,
      if (cieY != null) 'cieY': cieY,
      if (cieU != null) 'cieU': cieU,
      if (cieV != null) 'cieV': cieV,
      if (duv != null) 'duv': duv,
      if (tint != null) 'tint': tint,
      if (mode != null) 'mode': mode,
      if (channels != null) 'channels': channels,
      if (temperature != null) 'temperature': temperature,
      if (batteryMv != null) 'batteryMv': batteryMv,
    };
  }
}
