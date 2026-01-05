import 'dart:io';

import '../../models/recorded_track_point.dart';

class LocalTrackFile {
  final File file;
  final Map<String, dynamic> rawJson;
  final String trackType;
  final String name;
  final String description;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool synced;
  final DateTime? syncedAt;
  final int? cloudTrackId;
  final int? missionId;
  final String? missionName;
  final int? campaignId;
  final String? campaignName;
  final int? projectId;
  final List<TrackPointBase> points;

  LocalTrackFile({
    required this.file,
    required this.rawJson,
    required this.trackType,
    required this.name,
    required this.description,
    required this.startedAt,
    required this.endedAt,
    required this.synced,
    required this.syncedAt,
    required this.cloudTrackId,
    required this.missionId,
    required this.missionName,
    required this.campaignId,
    required this.campaignName,
    required this.projectId,
    required this.points,
  });

  static LocalTrackFile fromJson({required File file, required Map<String, dynamic> json}) {
    final trackTypeRaw = json['trackType'];
    final trackType = (trackTypeRaw == null)
        ? ''
        : trackTypeRaw.toString().trim().toLowerCase();
    if (trackType != 'light' && trackType != 'radiation') {
      throw Exception('Invalid or missing trackType in local track JSON');
    }

    final name = (json['name']?.toString().trim().isNotEmpty == true)
        ? json['name'].toString()
        : file.path.split('/').last;

    final description = (json['description']?.toString().trim().isNotEmpty == true)
        ? json['description'].toString().trim()
        : '';

    DateTime parseDateFromKeys(List<String> keys) {
      dynamic v;
      for (final k in keys) {
        if (json.containsKey(k) && json[k] != null) {
          v = json[k];
          break;
        }
      }
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    final startedAt = parseDateFromKeys(const ['startedAt', 'started_at', 'start_time', 'startTime']);
    final endedAt = parseDateFromKeys(const ['endedAt', 'ended_at', 'end_time', 'endTime']);
    final synced = json['synced'] == true;

    final syncedAtRaw = json['syncedAt'] ?? json['synced_at'];
    final syncedAt = (syncedAtRaw == null) ? null : _tryParseOptionalDate(syncedAtRaw);

    int? parseInt(dynamic v) => v == null ? null : int.tryParse(v.toString());
    final cloudTrackId = parseInt(json['cloudTrackId'] ?? json['cloud_track_id']);
    final missionId = parseInt(json['missionId']);
    final missionName = json['missionName']?.toString();
    final campaignId = parseInt(json['campaignId']);
    final campaignName = json['campaignName']?.toString();
    final projectId = parseInt(json['projectId']);

    final pointsRaw = json['points'];
    final points = <TrackPointBase>[];
    if (pointsRaw is! List) {
      throw Exception('Invalid points in local track JSON');
    }

    int? tryInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse(v.toString()));
    double? tryDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

    for (final p in pointsRaw) {
      if (p is! Map) continue;
      final m = Map<String, dynamic>.from(p);
      final ts = DateTime.parse(m['timestamp'].toString());
      final lat = (m['latitude'] as num).toDouble();
      final lon = (m['longitude'] as num).toDouble();
      final alt = (m['altitude'] as num?)?.toDouble() ?? 0;
      final acc = (m['accuracyMeters'] as num?)?.toDouble() ?? 0;

      if (trackType == 'light') {
        final lux = tryDouble(m['lux']);
        if (lux == null) {
          throw Exception('Missing lux in light track point');
        }

        List<double>? channels;
        final rawChannels = m['channels'];
        if (rawChannels is List) {
          final tmp = <double>[];
          for (final v in rawChannels) {
            if (v is num) tmp.add(v.toDouble());
          }
          if (tmp.isNotEmpty) channels = tmp;
        }

        points.add(
          LightTrackPoint(
            timestamp: ts,
            latitude: lat,
            longitude: lon,
            altitude: alt,
            accuracyMeters: acc,
            lux: lux,
            cct: tryDouble(m['cct']),
            cieX: tryDouble(m['cieX']),
            cieY: tryDouble(m['cieY']),
            cieU: tryDouble(m['cieU']),
            cieV: tryDouble(m['cieV']),
            duv: tryDouble(m['duv']),
            tint: tryDouble(m['tint']),
            mode: tryInt(m['mode']),
            channels: channels,
            temperature: tryInt(m['temperature']),
            batteryMv: tryInt(m['batteryMv']),
          ),
        );
      } else {
        points.add(
          RadiationTrackPoint(
            timestamp: ts,
            latitude: lat,
            longitude: lon,
            altitude: alt,
            accuracyMeters: acc,
            cpm: tryDouble(m['cpm']),
            cpmRelErr: tryDouble(m['cpmRelErr']),
            doseMicroSvPerHour: tryDouble(m['doseMicroSvPerHour']),
            doseMicroSvPerHourRelErr: tryDouble(m['doseMicroSvPerHourRelErr']),
          ),
        );
      }
    }

    return LocalTrackFile(
      file: file,
      rawJson: json,
      trackType: trackType,
      name: name,
      description: description,
      startedAt: startedAt,
      endedAt: endedAt,
      synced: synced,
      syncedAt: syncedAt,
      cloudTrackId: cloudTrackId,
      missionId: missionId,
      missionName: missionName,
      campaignId: campaignId,
      campaignName: campaignName,
      projectId: projectId,
      points: points,
    );
  }
}

DateTime? _tryParseOptionalDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}
