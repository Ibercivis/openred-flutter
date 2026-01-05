import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api_service.dart';
import '../../l10n/app_localizations.dart';
import 'maps/radiation_track_map.dart';
import 'models.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({
    super.key,
    required this.activeTabIndex,
    required this.tabIndex,
    required this.onRequestTab,
  });

  final ValueListenable<int> activeTabIndex;
  final int tabIndex;
  final ValueChanged<int> onRequestTab;

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  final ApiService _apiService = ApiService();

  bool get _isActive => widget.activeTabIndex.value == widget.tabIndex;
  bool _isLoggedIn = false;
  bool _isLoading = true;
  bool _isLoadingLocal = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  List<dynamic> _tracks = const [];
  List<LocalTrackFile> _localTracks = const [];

  final Set<String> _expandedKeys = <String>{};
  final Set<String> _syncingLocalPaths = <String>{};
  final Set<int> _downloadingCloudTrackIds = <int>{};
  final Map<int, String> _cloudDownloadErrors = <int, String>{};
  final Set<int> _deletingCloudTrackIds = <int>{};

  bool _prefetchingCloud = false;

  bool _isExpanded(String key) => _expandedKeys.contains(key);

  void _toggleExpanded(String key) {
    setState(() {
      if (_expandedKeys.contains(key)) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
    });
  }

  String _formatDurationHm(Duration d) {
    final totalMinutes = d.inMinutes;
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h <= 0) return '${m}m';
    return '${h}h ${m}m';
  }

  String _formatDistanceKm(double meters) {
    if (!meters.isFinite || meters < 0) return '—';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
  }

  String _formatRelativeDateTime(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 14) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    widget.activeTabIndex.addListener(_handleActiveTabChanged);
    unawaited(_refreshAll());
  }

  void _handleActiveTabChanged() {
    if (!_isActive) return;
    unawaited(_refreshIfAuthChanged());
    unawaited(_prefetchCloudTracks());
  }

  Future<void> _refreshAll() async {
    final loggedIn = await _apiService.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
      });
    }
    await _loadLocalTracks();
    if (loggedIn) {
      await _loadTracks();
    } else {
      if (mounted) {
        setState(() {
          _tracks = const [];
          _isLoading = false;
          _errorMessage = null;
        });
      }
    }
  }

  Future<void> _refreshIfAuthChanged() async {
    final loggedIn = await _apiService.isLoggedIn();
    if (loggedIn != _isLoggedIn) {
      if (mounted) {
        setState(() {
          _isLoggedIn = loggedIn;
          _isLoading = true;
        });
      }
      await _refreshAll();
    }
  }

  Future<void> _loadTracks() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final result = await _apiService.getTracks();
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _tracks = (result['tracks'] is List) ? List<dynamic>.from(result['tracks']) : const [];
        _isLoading = false;
        _errorMessage = null;
      });

      // Eagerly download cloud tracks so list actions (map/buttons) are available immediately.
      unawaited(_prefetchCloudTracks());
    } else {
      setState(() {
        _tracks = const [];
        _isLoading = false;
        _errorMessage = (result['message'] ?? 'Failed to load tracks').toString();
      });
    }
  }

  Future<void> _prefetchCloudTracks() async {
    if (!_isActive) return;
    if (_prefetchingCloud) return;
    if (!_isLoggedIn) return;

    final tracks = _tracks;
    if (tracks.isEmpty) return;

    final localCloudIds = _localTracks
        .map((t) => t.cloudTrackId)
        .whereType<int>()
        .toSet();

    final cloudTracks = tracks
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);

    _prefetchingCloud = true;
    try {
      for (final cloudTrack in cloudTracks) {
        if (!mounted) return;

        final cloudId = _parseCloudId(cloudTrack);
        if (cloudId == null) continue;
        if (localCloudIds.contains(cloudId)) continue;
        if (_downloadingCloudTrackIds.contains(cloudId)) continue;

        setState(() {
          _downloadingCloudTrackIds.add(cloudId);
          _cloudDownloadErrors.remove(cloudId);
        });

        try {
          await _downloadCloudTrackToLocal(cloudTrack);
          localCloudIds.add(cloudId);
          await _loadLocalTracks();
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _cloudDownloadErrors[cloudId] = e.toString();
          });
        } finally {
          if (!mounted) return;
          setState(() {
            _downloadingCloudTrackIds.remove(cloudId);
          });
        }
      }
    } finally {
      _prefetchingCloud = false;
    }
  }

  Future<void> _loadLocalTracks() async {
    if (mounted) {
      setState(() {
        _isLoadingLocal = true;
      });
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tracksDir = Directory('${dir.path}/tracks');
      if (!await tracksDir.exists()) {
        if (!mounted) return;
        setState(() {
          _localTracks = const [];
          _isLoadingLocal = false;
        });
        return;
      }

      final files = tracksDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .toList(growable: false);

      final parsed = <LocalTrackFile>[];
      for (final f in files) {
        try {
          final raw = await f.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is! Map) continue;
          parsed.add(LocalTrackFile.fromJson(file: f, json: Map<String, dynamic>.from(decoded)));
        } catch (_) {
          // ignore bad local track
        }
      }

      if (!mounted) return;
      setState(() {
        _localTracks = parsed;
        _isLoadingLocal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localTracks = const [];
        _isLoadingLocal = false;
      });
    }
  }

  int? _parseCloudId(Map<String, dynamic> track) {
    final raw = track['id'] ?? track['track_id'];
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  DateTime? _tryParseDateTime(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String? _cloudStatus(Map<String, dynamic> track) {
    final raw = track['status'];
    if (raw == null) return null;
    final s = raw.toString().trim().toLowerCase();
    return s.isEmpty ? null : s;
  }

  String _cloudTrackDescription(Map<String, dynamic> track) {
    final raw = track['description'];
    if (raw == null) return '';
    return raw.toString();
  }

  List<Offset> _localTrackPreviewPoints(LocalTrackFile local) {
    return local.points.map((p) => Offset(p.longitude, p.latitude)).toList(growable: false);
  }

  List<Offset> _cloudTrackPreviewPoints(Map<String, dynamic> cloud) {
    final pts = <Offset>[];
    final raw = cloud['points'] ?? cloud['measurements'] ?? cloud['coordinates'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final lat = m['latitude'] ?? m['lat'];
          final lon = m['longitude'] ?? m['lng'] ?? m['lon'];
          final latD = (lat is num) ? lat.toDouble() : double.tryParse(lat?.toString() ?? '');
          final lonD = (lon is num) ? lon.toDouble() : double.tryParse(lon?.toString() ?? '');
          if (latD != null && lonD != null) {
            pts.add(Offset(lonD, latD));
          }
        }
      }
    }
    return pts;
  }

  double _localTrackDistanceMeters(LocalTrackFile local) {
    if (local.points.length < 2) return 0;
    double sum = 0;
    for (var i = 1; i < local.points.length; i++) {
      final a = local.points[i - 1];
      final b = local.points[i];
      sum += geo.Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
    }
    return sum;
  }

  void _showSnackBarSafe(SnackBar snackBar) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  Future<void> _syncLocalTrack(LocalTrackFile track) async {
    if (!mounted) return;
    setState(() {
      _syncingLocalPaths.add(track.file.path);
    });

    try {
      final uploadMeta = await _askUploadMeta(track);
      if (uploadMeta == null) {
        return;
      }

      final rawDevice = track.rawJson['device'];
      Map<String, dynamic>? device;
      if (rawDevice is Map) {
        final d = Map<String, dynamic>.from(rawDevice);
        final name = d['name']?.toString();
        final id = d['id']?.toString();
        if (name != null && name.isNotEmpty && id != null && id.isNotEmpty) {
          device = {
            'name': name,
            'id': id,
          };
        }
      }

      final requiredGpsAccuracyMeters =
          (track.rawJson['requiredGpsAccuracyMeters'] as num?)?.toDouble() ?? 10.0;

      final uploadJson = <String, dynamic>{
        'name': track.name,
        'description': track.description,
        if (device != null) 'device': device,
        'project': uploadMeta.projectId,
        'mission': uploadMeta.missionId,
        'campaign': uploadMeta.campaignId,
        if (uploadMeta.campaignPassword != null && uploadMeta.campaignPassword!.trim().isNotEmpty)
          'campaign_password': uploadMeta.campaignPassword!.trim(),
        // Send timezone-safe timestamps (server may run in a different TZ).
        // UTC ISO8601 will include the trailing 'Z'.
        'startedAt': track.startedAt.toUtc().toIso8601String(),
        'endedAt': track.endedAt.toUtc().toIso8601String(),
        'requiredGpsAccuracyMeters': requiredGpsAccuracyMeters,
        'points': track.points.map((p) => p.toJson()).toList(growable: false),
      };

      final uploadResult = await _apiService.uploadTrackJson(trackJson: uploadJson);
      if (uploadResult['success'] != true) {
        if (!mounted) return;
        final msg = (uploadResult['message']?.toString().trim().isNotEmpty == true)
            ? uploadResult['message'].toString()
            : 'Failed to upload track JSON';
        _showSnackBarSafe(
          SnackBar(
            content: Text('Sync failed: $msg'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final uploaded = uploadResult['track'];
      if (uploaded is! Map) {
        throw Exception('Upload succeeded but unexpected response shape.');
      }
      final uploadedMap = Map<String, dynamic>.from(uploaded);
      final cloudId = int.tryParse((uploadedMap['id'] ?? uploadedMap['track_id'] ?? '').toString());
      final cloudStatus = uploadedMap['status']?.toString();
      if (cloudId == null) {
        throw Exception('Upload succeeded but no id was returned.');
      }

      // Mark local file as uploaded/linked to cloud. Once cloudTrackId exists,
      // we never allow re-upload from the same local file.
      final updatedJson = {
        ...track.rawJson,
        'missionId': uploadMeta.missionId,
        'missionName': uploadMeta.missionName,
        'campaignId': uploadMeta.campaignId,
        'campaignName': uploadMeta.campaignName,
        'projectId': uploadMeta.projectId,
        'synced': true,
        'syncedAt': DateTime.now().toUtc().toIso8601String(),
        'cloudTrackId': cloudId,
      };
      await track.file.writeAsString(jsonEncode(updatedJson));

      if (!mounted) return;
      _showSnackBarSafe(
        SnackBar(
          content: Text(
            cloudStatus == null
                ? 'Uploaded "${track.name}" (id $cloudId).'
                : 'Uploaded "${track.name}" (id $cloudId, status $cloudStatus).',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await _loadLocalTracks();
      await _loadTracks();
    } catch (e) {
      if (mounted) {
        _showSnackBarSafe(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingLocalPaths.remove(track.file.path);
        });
      }
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _sanitizeFileName(String input) {
    var s = input.trim();
    if (s.isEmpty) return 'track';
    s = s.replaceAll(RegExp(r'[\\/]+'), '_');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'track' : s;
  }

  Future<Directory> _userTracksDir() async {
    final loggedIn = await _apiService.isLoggedIn();
    if (!loggedIn) {
      throw Exception('Not authenticated');
    }
    final userId = await _apiService.getCurrentUserId();
    if (userId == null) {
      throw Exception('Failed to fetch user id');
    }
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/tracks/$userId');
  }

  Future<void> _downloadCloudTrackToLocal(Map<String, dynamic> cloudTrack) async {
    final cloudId = _parseCloudId(cloudTrack);
    if (cloudId == null) {
      throw Exception('Track has no id');
    }

    final result = await _apiService.getTrackMeasurements(cloudId);
    if (result['success'] != true) {
      throw Exception(result['message'] ?? 'Failed to fetch measurements');
    }

    final measurements = (result['measurements'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);

    measurements.sort((a, b) {
      final da = a['dateTime'] ?? a['datetime'] ?? a['timestamp'];
      final db = b['dateTime'] ?? b['datetime'] ?? b['timestamp'];
      DateTime ta;
      DateTime tb;
      if (da is num) {
        ta = DateTime.fromMillisecondsSinceEpoch(da.toInt() * 1000, isUtc: true);
      } else {
        ta = _tryParseDateTime(da) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      if (db is num) {
        tb = DateTime.fromMillisecondsSinceEpoch(db.toInt() * 1000, isUtc: true);
      } else {
        tb = _tryParseDateTime(db) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return ta.compareTo(tb);
    });

    final points = <Map<String, dynamic>>[];
    for (final m in measurements) {
      final lat = _toDouble(m['latitude'] ?? m['lat']);
      final lon = _toDouble(m['longitude'] ?? m['lon'] ?? m['lng']);
      if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) continue;

      DateTime ts;
      final dtRaw = m['dateTime'] ?? m['datetime'];
      if (dtRaw != null) {
        ts = _tryParseDateTime(dtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        final epoch = m['timestamp'];
        ts = (epoch is num)
            ? DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(0);
      }

      points.add({
        'timestamp': ts.toUtc().toIso8601String(),
        'latitude': lat,
        'longitude': lon,
        'altitude': _toDouble(m['altitude']) ?? 0.0,
        'accuracyMeters': _toDouble(m['accuracy']) ?? 0.0,
        'cpm': _toDouble(m['cpm']),
        'cpmRelErr': _toDouble(m['cpm_error'] ?? m['cpmRelErr']),
        'doseMicroSvPerHour': _toDouble(m['dose_rate'] ?? m['doseMicroSvPerHour']),
        'doseMicroSvPerHourRelErr': _toDouble(m['dose_rate_error'] ?? m['doseMicroSvPerHourRelErr']),
      });
    }

    final name = (cloudTrack['name']?.toString().trim().isNotEmpty == true)
        ? cloudTrack['name'].toString().trim()
        : 'track_$cloudId.json';

    final startedAtRaw = cloudTrack['start_time'] ?? cloudTrack['startedAt'] ?? cloudTrack['started_at'];
    final endedAtRaw = cloudTrack['end_time'] ?? cloudTrack['endedAt'] ?? cloudTrack['ended_at'];
    var startedAt = _tryParseDateTime(startedAtRaw) ??
        (points.isNotEmpty
            ? DateTime.parse(points.first['timestamp'].toString())
            : DateTime.fromMillisecondsSinceEpoch(0));
    var endedAt = _tryParseDateTime(endedAtRaw) ??
        (points.isNotEmpty
            ? DateTime.parse(points.last['timestamp'].toString())
            : startedAt);

    final requiredAcc = _toDouble(
          cloudTrack['required_gps_accuracy_meters'] ?? cloudTrack['requiredGpsAccuracyMeters'],
        ) ??
        10.0;
    int? parseInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

    final localJson = <String, dynamic>{
      'name': name,
      'description': (cloudTrack['description'] ?? '').toString(),
      'synced': true,
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      'cloudTrackId': cloudId,
      'missionId': parseInt(cloudTrack['mission']),
      'missionName': cloudTrack['mission_name']?.toString(),
      'campaignId': parseInt(cloudTrack['campaign']),
      'campaignName': cloudTrack['campaign_name']?.toString(),
      'projectId': parseInt(cloudTrack['project']),
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'requiredGpsAccuracyMeters': requiredAcc,
      'points': points,
    };

    final tracksDir = await _userTracksDir();
    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }
    final base = _sanitizeFileName(name);
    final fileName = base.toLowerCase().endsWith('.json') ? base : '$base.json';
    final finalName = 'cloud_${cloudId}_$fileName';
    final file = File('${tracksDir.path}/$finalName');
    await file.writeAsString(jsonEncode(localJson));
  }

  Future<UploadMeta?> _askUploadMeta(LocalTrackFile track) async {
    int? selectedMissionId;
    String? selectedMissionName;
    int? selectedProjectId;

    int? selectedCampaignId;
    String? selectedCampaignName;
    bool selectedCampaignHasPassword = false;
    final campaignPasswordController = TextEditingController();

    String? selectionError;

    // Preselect from stored values if present
    final initialMissionId = track.missionId;
    final initialCampaignId = track.campaignId;

    // keep us from re-triggering side effects every build
    bool didInitCampaignsFuture = false;

    final missionsFuture = _apiService.getMissions();
    Future<Map<String, dynamic>>? campaignsFuture;

    final result = await showDialog<UploadMeta>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Upload to cloud'),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<Map<String, dynamic>>(
                        future: missionsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            );
                          }

                          final data = snapshot.data;
                          final ok = data != null && data['success'] == true;
                          final missions = ok ? (data['missions'] as List? ?? []) : const [];

                          if (!ok) {
                            return Text(
                              'Login required to load missions.',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            );
                          }

                          final missionItems = missions
                              .whereType<Map>()
                              .map((m) => Map<String, dynamic>.from(m))
                              .toList();

                          // Apply preselection (ids are stable across rebuilds)
                          if (selectedMissionId == null && initialMissionId != null) {
                            selectedMissionId = initialMissionId;
                          }

                          // Derive projectId + name from selectedMissionId and initialize campaigns fetch
                          if (selectedMissionId != null) {
                            final selectedMissionMap = missionItems.firstWhere(
                              (m) => int.tryParse(m['id']?.toString() ?? '') == selectedMissionId,
                              orElse: () => <String, dynamic>{},
                            );
                            if (selectedMissionMap.isNotEmpty) {
                              selectedMissionName ??= selectedMissionMap['name']?.toString();
                              selectedProjectId ??= int.tryParse(selectedMissionMap['project']?.toString() ?? '');
                              if (!didInitCampaignsFuture && campaignsFuture == null && selectedProjectId != null) {
                                didInitCampaignsFuture = true;
                                campaignsFuture = _apiService.getCampaigns(
                                  missionId: selectedMissionId!,
                                  projectId: selectedProjectId!,
                                );
                              }
                            }
                          }

                          return DropdownButtonFormField<int>(
                            value: selectedMissionId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Mission'),
                            items: missionItems
                                .map(
                                  (m) => DropdownMenuItem<int>(
                                    value: int.tryParse(m['id']?.toString() ?? ''),
                                    child: Text(
                                      m['name']?.toString() ?? 'Mission ${m['id']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedMissionId = value;
                                selectedMissionName = null;
                                selectedProjectId = null;

                                selectedCampaignId = null;
                                selectedCampaignName = null;
                                selectedCampaignHasPassword = false;
                                campaignPasswordController.clear();
                                selectionError = null;
                                campaignsFuture = null;
                                didInitCampaignsFuture = false;

                                final selectedMissionMap = missionItems.firstWhere(
                                  (m) => int.tryParse(m['id']?.toString() ?? '') == value,
                                  orElse: () => <String, dynamic>{},
                                );
                                final missionId = value;
                                final projectId = int.tryParse(selectedMissionMap['project']?.toString() ?? '');
                                selectedMissionName = selectedMissionMap['name']?.toString();
                                selectedProjectId = projectId;

                                if (missionId != null && projectId != null) {
                                  campaignsFuture = _apiService.getCampaigns(
                                    missionId: missionId,
                                    projectId: projectId,
                                  );
                                }
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      if (campaignsFuture == null)
                        const SizedBox.shrink()
                      else
                        FutureBuilder<Map<String, dynamic>>(
                          future: campaignsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: LinearProgressIndicator(),
                              );
                            }

                            final data = snapshot.data;
                            final ok = data != null && data['success'] == true;
                            final campaigns = ok ? (data['campaigns'] as List? ?? []) : const [];

                            if (!ok) {
                              return Text(
                                'Failed to load campaigns.',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                              );
                            }

                            final campaignItems = campaigns
                                .whereType<Map>()
                                .map((c) => Map<String, dynamic>.from(c))
                                .toList();

                            // Apply preselection once
                            if (selectedCampaignId == null && initialCampaignId != null) {
                              selectedCampaignId = initialCampaignId;
                            }

                            if (selectedCampaignId != null) {
                              final selectedCampaignMap = campaignItems.firstWhere(
                                (c) => int.tryParse(c['id']?.toString() ?? '') == selectedCampaignId,
                                orElse: () => <String, dynamic>{},
                              );
                              if (selectedCampaignMap.isNotEmpty) {
                                selectedCampaignName ??= selectedCampaignMap['name']?.toString();
                                final hpRaw = selectedCampaignMap['has_password'] ?? selectedCampaignMap['hasPassword'];
                                selectedCampaignHasPassword = hpRaw == true || hpRaw?.toString().toLowerCase() == 'true';
                              }
                            }

                            return DropdownButtonFormField<int>(
                              value: selectedCampaignId,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Campaign'),
                              items: campaignItems
                                  .map(
                                    (c) => DropdownMenuItem<int>(
                                      value: int.tryParse(c['id']?.toString() ?? ''),
                                      child: Text(
                                        c['name']?.toString() ?? 'Campaign ${c['id']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  selectedCampaignId = value;
                                  final selectedMap = campaignItems.firstWhere(
                                    (c) => int.tryParse(c['id']?.toString() ?? '') == value,
                                    orElse: () => <String, dynamic>{},
                                  );
                                  selectedCampaignName = selectedMap['name']?.toString();

                                  final hpRaw = selectedMap['has_password'] ?? selectedMap['hasPassword'];
                                  selectedCampaignHasPassword = hpRaw == true || hpRaw?.toString().toLowerCase() == 'true';
                                  if (!selectedCampaignHasPassword) {
                                    campaignPasswordController.clear();
                                  }
                                  selectionError = null;
                                });
                              },
                            );
                          },
                        ),
                      if (selectedCampaignHasPassword) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: campaignPasswordController,
                          decoration: const InputDecoration(
                            labelText: 'Campaign password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                        ),
                      ],
                      if (selectionError != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            selectionError!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final missionId = selectedMissionId;
                    final missionName = selectedMissionName;
                    final projectId = selectedProjectId;
                    final campaignId = selectedCampaignId;
                    final campaignName = selectedCampaignName;

                    if (missionId == null || projectId == null) {
                      setState(() {
                        selectionError = 'Please select a mission.';
                      });
                      return;
                    }
                    if (campaignId == null) {
                      setState(() {
                        selectionError = 'Please select a campaign.';
                      });
                      return;
                    }
                    if (selectedCampaignHasPassword && campaignPasswordController.text.trim().isEmpty) {
                      setState(() {
                        selectionError = 'This campaign requires a password.';
                      });
                      return;
                    }

                    Navigator.of(context).pop(
                      UploadMeta(
                        missionId: missionId,
                        missionName: missionName,
                        campaignId: campaignId,
                        campaignName: campaignName,
                        projectId: projectId,
                        campaignPassword: campaignPasswordController.text.trim().isEmpty
                            ? null
                            : campaignPasswordController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Upload'),
                ),
              ],
            );
          },
        );
      },
    );

    // Dispose safely after the dialog route has fully settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      campaignPasswordController.dispose();
    });
    return result;
  }

  Future<void> _confirmDeleteLocalTrack(LocalTrackFile track) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).tracksDeleteLocalTitle),
        content: Text(AppLocalizations.of(context).tracksDeleteLocalBody(track.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await track.file.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksSnackLocalDeleted),
          backgroundColor: Colors.green,
        ),
      );
      await _loadLocalTracks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksErrorDeleteFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportLocalTrackJson(LocalTrackFile track) async {
    try {
      final file = track.file;
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).tracksSnackFileNotFound),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Open-red local track: ${track.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksErrorExportFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportAllLocalTracksJson() async {
    if (_localTracks.isEmpty) return;

    try {
      final files = <XFile>[];
      for (final t in _localTracks) {
        final f = t.file;
        if (await f.exists()) {
          files.add(XFile(f.path, mimeType: 'application/json'));
        }
      }

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).tracksSnackNoLocalJsonToExport),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await Share.shareXFiles(
        files,
        subject: 'Open-red local tracks (${files.length})',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksErrorExportFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openLocalTrack(LocalTrackFile track, {bool showMap = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalTrackDetailPage(track: track, initialShowMap: showMap),
      ),
    );
  }

  Future<void> _openCloudTrackEnsuringLocal(Map<String, dynamic> cloudTrack) async {
    final id = _parseCloudId(cloudTrack);
    if (id == null) return;

    final status = _cloudStatus(cloudTrack);
    if (status == 'pending' || status == 'processing') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).tracksSnackCloudNoMeasurementsYet(status ?? ''),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final existing = _localTracks.where((t) => t.cloudTrackId == id).toList();
    if (existing.isNotEmpty) {
      _openLocalTrack(existing.first, showMap: true);
      return;
    }

    if (mounted) {
      setState(() {
        _downloadingCloudTrackIds.add(id);
        _cloudDownloadErrors.remove(id);
      });
    }

    try {
      await _downloadCloudTrackToLocal(cloudTrack);
      await _loadLocalTracks();
      final downloaded = _localTracks.where((t) => t.cloudTrackId == id).toList();
      if (downloaded.isEmpty) {
        throw Exception('Downloaded but local file not found');
      }
      if (!mounted) return;
      _openLocalTrack(downloaded.first, showMap: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksErrorDownloadFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingCloudTrackIds.remove(id);
        });
      }
    }
  }

  Future<void> _markLocalAsUnsynced(LocalTrackFile local) async {
    final updated = {
      ...local.rawJson,
      'synced': false,
      'syncedAt': null,
      'cloudTrackId': null,
    };
    await local.file.writeAsString(jsonEncode(updated));
  }

  Future<void> _confirmDeletePendingCloudTrack({
    required int cloudTrackId,
    required String title,
    LocalTrackFile? linkedLocal,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).tracksDeleteCloudTitle),
        content: Text(AppLocalizations.of(context).tracksDeleteCloudBody(title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (_deletingCloudTrackIds.contains(cloudTrackId)) return;

    if (mounted) {
      setState(() {
        _deletingCloudTrackIds.add(cloudTrackId);
      });
    }

    try {
      final result = await _apiService.deleteTrack(cloudTrackId);
      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Failed to delete cloud track');
      }

      // If we had a local file linked to this cloud id, clear the linkage so the
      // UI doesn't keep showing a fake "Synced" state.
      if (linkedLocal != null && linkedLocal.cloudTrackId == cloudTrackId) {
        await _markLocalAsUnsynced(linkedLocal);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksSnackCloudDeleted),
          backgroundColor: Colors.green,
        ),
      );

      await _loadLocalTracks();
      await _loadTracks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tracksErrorDeleteFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingCloudTrackIds.remove(cloudTrackId);
        });
      }
    }
  }

  @override
  void dispose() {
    widget.activeTabIndex.removeListener(_handleActiveTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Note: IndexedStack keeps pages alive; we rely on the activeTabIndex listener
    // to refresh/prefetch when returning to this tab.

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 40, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tracksNeedLoginToView,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      widget.onRequestTab(3);
                    },
                    child: Text(l10n.login),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final localByCloudId = <int, LocalTrackFile>{};
    final localOnly = <LocalTrackFile>[];
    for (final t in _localTracks) {
      final id = t.cloudTrackId;
      if (id == null) {
        localOnly.add(t);
      } else {
        localByCloudId[id] = t;
      }
    }

    final cloudById = <int, Map<String, dynamic>>{};
    for (final t in _tracks) {
      if (t is! Map) continue;
      final m = Map<String, dynamic>.from(t);
      final id = _parseCloudId(m);
      if (id == null) continue;
      cloudById[id] = m;
    }

    final merged = <Map<String, dynamic>>[];
    final ids = <int>{...localByCloudId.keys, ...cloudById.keys}.toList();
    for (final id in ids) {
      merged.add({
        'cloudId': id,
        'local': localByCloudId[id],
        'cloud': cloudById[id],
      });
    }
    for (final t in localOnly) {
      merged.add({
        'cloudId': null,
        'local': t,
        'cloud': null,
      });
    }

    // Use the exact same timestamp for both sorting and what's shown on the card.
    DateTime? itemStartedAt(Map<String, dynamic> item) {
      final local = item['local'] as LocalTrackFile?;
      final cloud = item['cloud'] as Map<String, dynamic>?;

      final dt = local?.startedAt ?? _tryParseDateTime(cloud?['start_time'] ?? cloud?['startTime']);
      return dt?.toLocal();
    }

    DateTime sortTime(Map<String, dynamic> item) {
      return itemStartedAt(item) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    merged.sort((a, b) => sortTime(b).compareTo(sortTime(a)));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle),
            Text(
              l10n.navTracks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _isLoadingLocal || _localTracks.isEmpty ? null : _exportAllLocalTracksJson,
            tooltip: l10n.tracksTooltipExportLocalJson,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadLocalTracks();
              _loadTracks();
            },
            tooltip: l10n.tracksTooltipRefresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (mounted) {
            setState(() {
              _isRefreshing = true;
            });
          }
          try {
            await _loadLocalTracks();
            await _loadTracks();
          } finally {
            if (mounted) {
              setState(() {
                _isRefreshing = false;
              });
            }
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (!_isLoggedIn)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.login, color: Colors.grey),
                  title: Text(l10n.tracksLoginToSync),
                  trailing: ElevatedButton(
                    onPressed: () {
                      widget.onRequestTab(3);
                    },
                    child: Text(l10n.login),
                  ),
                ),
              ),
            if (!_isRefreshing && (_isLoadingLocal || (_isLoggedIn && _isLoading)))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_isLoggedIn && _errorMessage != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(_errorMessage!),
                  trailing: ElevatedButton(
                    onPressed: _loadTracks,
                    child: Text(l10n.retry),
                  ),
                ),
              )
            else if (merged.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.route, color: Colors.grey),
                  title: Text(l10n.tracksNoTracksYet),
                  subtitle: Text(l10n.tracksNoTracksSubtitle),
                ),
              )
            else
              ...merged.map((item) {
                final local = item['local'] as LocalTrackFile?;
                final cloud = item['cloud'] as Map<String, dynamic>?;
                final cloudId = item['cloudId'] as int?;

                final key = cloudId != null ? 'unified:$cloudId' : 'local:${local!.file.path}';
                final expanded = _isExpanded(key);

                final title = local?.name ?? cloud?['name']?.toString() ?? l10n.tracksUnnamed;
                final description = (local != null)
                    ? local.description
                    : (cloud != null ? _cloudTrackDescription(cloud) : '');

                final previewPoints = local != null
                    ? _localTrackPreviewPoints(local)
                    : (cloud != null ? _cloudTrackPreviewPoints(cloud) : const <Offset>[]);

                final whenDt = itemStartedAt(item);
                final when = whenDt == null ? '—' : _formatRelativeDateTime(context, whenDt);

                final distanceText = () {
                  if (local != null) {
                    return _formatDistanceKm(_localTrackDistanceMeters(local));
                  }
                  final distanceRaw = cloud?['total_distance'];
                  final meters = (distanceRaw is num)
                      ? distanceRaw.toDouble()
                      : double.tryParse(distanceRaw?.toString() ?? '');
                  return meters == null ? '—' : _formatDistanceKm(meters);
                }();

                final durationText = () {
                  if (local != null) {
                    return _formatDurationHm(local.endedAt.difference(local.startedAt));
                  }
                  final startedAt = cloud == null ? null : _tryParseDateTime(cloud['start_time']);
                  final endedAt = cloud == null ? null : _tryParseDateTime(cloud['end_time']);
                  if (startedAt == null || endedAt == null) return '—';
                  return _formatDurationHm(endedAt.difference(startedAt));
                }();

                final pointsText = () {
                  if (local != null) return local.points.length.toString();
                  final pointsCount = cloud?['measurements_count'] ?? cloud?['points_count'];
                  return pointsCount == null ? '—' : pointsCount.toString();
                }();

                String statusText;
                IconData statusIcon;
                Color? statusColor;

                if (cloudId != null) {
                  final cloudStatus = cloud == null ? null : _cloudStatus(cloud);
                  if (cloudStatus == 'pending' || cloudStatus == 'processing') {
                    statusText = l10n.tracksStatusPending;
                    statusIcon = Icons.hourglass_empty;
                    statusColor = Colors.orange;
                  } else
                  if (local != null) {
                    statusText = local.synced ? l10n.tracksStatusSynced : l10n.tracksStatusLocalAndCloud;
                    statusIcon = local.synced ? Icons.cloud_done : Icons.cloud;
                    statusColor = local.synced ? Colors.green : null;
                  } else if (_downloadingCloudTrackIds.contains(cloudId)) {
                    statusText = l10n.tracksStatusDownloading;
                    statusIcon = Icons.cloud_download;
                    statusColor = null;
                  } else if (_cloudDownloadErrors.containsKey(cloudId)) {
                    statusText = l10n.tracksStatusDownloadFailed;
                    statusIcon = Icons.error_outline;
                    statusColor = Colors.red;
                  } else {
                    statusText = l10n.tracksStatusCloudOnly;
                    statusIcon = Icons.cloud_download_outlined;
                    statusColor = null;
                  }
                } else {
                  statusText = local?.synced == true ? l10n.tracksStatusSynced : l10n.tracksStatusLocalOnly;
                  statusIcon = local?.synced == true ? Icons.cloud_done : Icons.folder_open;
                  statusColor = local?.synced == true ? Colors.green : null;
                }

                final isSyncingLocal = local != null && _syncingLocalPaths.contains(local.file.path);
                final canSync = local != null && _isLoggedIn && local.cloudTrackId == null && !local.synced && !isSyncingLocal;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tooltip(
                              message: l10n.tracksTooltipViewOnMap,
                              child: _TrackPolylineThumbnail(
                                points: previewPoints,
                                width: 56,
                                height: 36,
                                onTap: () async {
                                  if (local != null) {
                                    _openLocalTrack(local, showMap: true);
                                    return;
                                  }
                                  if (cloud != null) {
                                    await _openCloudTrackEnsuringLocal(cloud);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () => _toggleExpanded(key),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.tracksSummaryLine(when, distanceText, durationText, pointsText),
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(statusIcon, size: 14, color: statusColor ?? Colors.grey.shade700),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            (cloudId != null && _cloudDownloadErrors.containsKey(cloudId))
                                                ? '$statusText • ${_cloudDownloadErrors[cloudId]!}'
                                                : statusText,
                                            style: TextStyle(fontSize: 12, color: statusColor ?? Colors.grey.shade700),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Buttons row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            const Spacer(),
                            if (cloudId != null && _deletingCloudTrackIds.contains(cloudId))
                              const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else if (cloudId != null && _downloadingCloudTrackIds.contains(cloudId))
                              const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else if (cloudId != null && _cloudDownloadErrors.containsKey(cloudId) && cloud != null)
                              IconButton(
                                tooltip: 'Retry download',
                                onPressed: () async {
                                  await _openCloudTrackEnsuringLocal(cloud);
                                },
                                icon: const Icon(Icons.refresh),
                              ),

                            if (cloudId != null && cloud != null) ...[
                              if ((_cloudStatus(cloud) == 'pending' || _cloudStatus(cloud) == 'processing'))
                                IconButton(
                                  tooltip: 'Delete from cloud',
                                  onPressed: _deletingCloudTrackIds.contains(cloudId)
                                      ? null
                                      : () async {
                                          await _confirmDeletePendingCloudTrack(
                                            cloudTrackId: cloudId,
                                            title: title,
                                            linkedLocal: local,
                                          );
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ],

                            if (local != null) ...[
                              if (isSyncingLocal)
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                IconButton(
                                  tooltip: (local.cloudTrackId != null || local.synced)
                                      ? 'Already uploaded'
                                      : 'Sync to cloud',
                                  onPressed: canSync ? () => _syncLocalTrack(local) : null,
                                  icon: Icon(local.synced ? Icons.cloud_done : Icons.cloud_upload),
                                ),
                              IconButton(
                                tooltip: 'Export JSON',
                                onPressed: isSyncingLocal ? null : () => _exportLocalTrackJson(local),
                                icon: const Icon(Icons.share),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: isSyncingLocal ? null : () => _confirmDeleteLocalTrack(local),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              description.trim().isNotEmpty ? description.trim() : 'No description.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _TrackPolylineThumbnail extends StatelessWidget {
  final List<Offset> points;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const _TrackPolylineThumbnail({
    required this.points,
    this.width = double.infinity,
    this.height = 64,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        width: width,
        child: CustomPaint(
          painter: _TrackPolylinePainter(points),
        ),
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

class _TrackPolylinePainter extends CustomPainter {
  final List<Offset> geoPoints;

  _TrackPolylinePainter(this.geoPoints);

  @override
  void paint(Canvas canvas, ui.Size size) {
    if (geoPoints.isEmpty) {
      if (size.width < 60 || size.height < 36) {
        return;
      }
      final tp = TextPainter(
        text: TextSpan(
          text: 'No preview',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ),
      );
      return;
    }

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final p in geoPoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final pad = 8.0;
    final w = (size.width - pad * 2).clamp(1.0, double.infinity);
    final h = (size.height - pad * 2).clamp(1.0, double.infinity);
    final rangeX = (maxX - minX).abs();
    final rangeY = (maxY - minY).abs();
    final safeRangeX = rangeX < 1e-12 ? 1.0 : rangeX;
    final safeRangeY = rangeY < 1e-12 ? 1.0 : rangeY;

    Offset toCanvas(Offset p) {
      final nx = (p.dx - minX) / safeRangeX;
      final ny = (p.dy - minY) / safeRangeY;
      final x = pad + nx * w;
      final y = pad + (1.0 - ny) * h;
      return Offset(x, y);
    }

    final path = Path();
    final first = toCanvas(geoPoints.first);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < geoPoints.length; i++) {
      final p = toCanvas(geoPoints[i]);
      path.lineTo(p.dx, p.dy);
    }

    final stroke = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, stroke);

    // Start/end markers
    final dotPaint = Paint()..color = Colors.red;
    canvas.drawCircle(first, 2.5, dotPaint);
    final last = toCanvas(geoPoints.last);
    canvas.drawCircle(last, 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _TrackPolylinePainter oldDelegate) {
    return oldDelegate.geoPoints != geoPoints;
  }
}

class UploadMeta {
  final int missionId;
  final String? missionName;
  final int campaignId;
  final String? campaignName;
  final String? campaignPassword;
  final int projectId;

  UploadMeta({
    required this.missionId,
    required this.campaignId,
    required this.projectId,
    this.missionName,
    this.campaignName,
    this.campaignPassword,
  });
}

// Track Detail Page
class TrackDetailPage extends StatefulWidget {
  final Map<String, dynamic> track;
  final bool initialShowMap;
  
  const TrackDetailPage({
    super.key,
    required this.track,
    this.initialShowMap = false,
  });

  @override
  State<TrackDetailPage> createState() => _TrackDetailPageState();
}

class LocalTrackDetailPage extends StatefulWidget {
  final LocalTrackFile track;
  final bool initialShowMap;

  const LocalTrackDetailPage({
    super.key,
    required this.track,
    this.initialShowMap = false,
  });

  @override
  State<LocalTrackDetailPage> createState() => _LocalTrackDetailPageState();
}

class _LocalTrackDetailPageState extends State<LocalTrackDetailPage> {
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _showMap = widget.initialShowMap;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.track.points;
    final startedAt = widget.track.startedAt;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Open-red'),
            Text(
              widget.track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showMap ? 'Hide map' : 'Show map',
            onPressed: () {
              setState(() {
                _showMap = !_showMap;
              });
            },
            icon: Icon(_showMap ? Icons.map_outlined : Icons.map),
          ),
        ],
      ),
      body: points.isEmpty
          ? const Center(
              child: Text(
                'No points in this local track',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade900,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recorded: ${_formatDate(startedAt)}',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      if (widget.track.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.track.description.trim(),
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${points.length} points',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _showMap
                      ? RadiationTrackMap(points: points)
                      : Center(
                          child: Text(
                            'Tap the map icon to show the map.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _TrackDetailPageState extends State<TrackDetailPage> {
  final ApiService _apiService = ApiService();
  int? _currentUserId;
  bool _isPreparing = true;
  String? _message;
  LocalTrackFile? _local;

  Future<Directory> _userTracksDir() async {
    final isLoggedIn = await _apiService.isLoggedIn();
    if (!isLoggedIn) {
      throw Exception('Login required to access local tracks');
    }

    final userId = _currentUserId ?? await _apiService.getCurrentUserId();
    if (userId == null) {
      throw Exception('Failed to fetch user profile');
    }
    _currentUserId = userId;

    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/tracks/$userId');
  }

  @override
  void initState() {
    super.initState();
    _prepareLocalThenShow();
  }

  int? _cloudId() {
    final raw = widget.track['id'] ?? widget.track['track_id'];
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  String? _cloudStatus() {
    final raw = widget.track['status'];
    if (raw == null) return null;
    final s = raw.toString().trim().toLowerCase();
    return s.isEmpty ? null : s;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _sanitizeFileName(String input) {
    var s = input.trim();
    if (s.isEmpty) return 'track';
    s = s.replaceAll(RegExp(r'[\\/]+'), '_');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'track' : s;
  }

  DateTime? _tryParseDateTime(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  Future<LocalTrackFile?> _findLocalByCloudId(int cloudId) async {
    final tracksDir = await _userTracksDir();
    if (!await tracksDir.exists()) return null;

    final prefix = 'cloud_${cloudId}_';
    final files = tracksDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList(growable: false);

    // Fast path: our own naming convention.
    final candidates = files.where((f) => f.path.split('/').last.startsWith(prefix)).toList();
    final toScan = candidates.isNotEmpty ? candidates : files;

    for (final f in toScan) {
      try {
        final raw = await f.readAsString();
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) continue;
        final id = json['cloudTrackId'] ?? json['cloud_track_id'];
        if (id != null && int.tryParse(id.toString()) == cloudId) {
          return LocalTrackFile.fromJson(file: f, json: json);
        }
      } catch (_) {
        // ignore
      }
    }
    return null;
  }

  Future<void> _downloadCloudToLocal(int cloudId) async {
    final result = await _apiService.getTrackMeasurements(cloudId);
    if (result['success'] != true) {
      throw Exception(result['message'] ?? 'Failed to fetch measurements');
    }

    final measurements = (result['measurements'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);

    measurements.sort((a, b) {
      final da = a['dateTime'] ?? a['datetime'] ?? a['timestamp'];
      final db = b['dateTime'] ?? b['datetime'] ?? b['timestamp'];
      DateTime ta;
      DateTime tb;
      if (da is num) {
        ta = DateTime.fromMillisecondsSinceEpoch(da.toInt() * 1000, isUtc: true);
      } else {
        ta = _tryParseDateTime(da) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      if (db is num) {
        tb = DateTime.fromMillisecondsSinceEpoch(db.toInt() * 1000, isUtc: true);
      } else {
        tb = _tryParseDateTime(db) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return ta.compareTo(tb);
    });

    final points = <Map<String, dynamic>>[];
    for (final m in measurements) {
      final lat = _toDouble(m['latitude'] ?? m['lat']);
      final lon = _toDouble(m['longitude'] ?? m['lon'] ?? m['lng']);
      if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) continue;

      DateTime ts;
      final dtRaw = m['dateTime'] ?? m['datetime'];
      if (dtRaw != null) {
        ts = _tryParseDateTime(dtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        final epoch = m['timestamp'];
        ts = (epoch is num)
            ? DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(0);
      }

      points.add({
        'timestamp': ts.toUtc().toIso8601String(),
        'latitude': lat,
        'longitude': lon,
        'altitude': _toDouble(m['altitude']) ?? 0.0,
        'accuracyMeters': _toDouble(m['accuracy']) ?? 0.0,
        'cpm': _toDouble(m['cpm']),
        'cpmRelErr': _toDouble(m['cpm_error'] ?? m['cpmRelErr']),
        'doseMicroSvPerHour': _toDouble(m['dose_rate'] ?? m['doseMicroSvPerHour']),
        'doseMicroSvPerHourRelErr': _toDouble(m['dose_rate_error'] ?? m['doseMicroSvPerHourRelErr']),
      });
    }

    final name = (widget.track['name']?.toString().trim().isNotEmpty == true)
        ? widget.track['name'].toString().trim()
        : 'track_$cloudId.json';

    final startedAtRaw = widget.track['start_time'] ?? widget.track['startedAt'] ?? widget.track['started_at'];
    final endedAtRaw = widget.track['end_time'] ?? widget.track['endedAt'] ?? widget.track['ended_at'];
    var startedAt = _tryParseDateTime(startedAtRaw) ?? (points.isNotEmpty ? DateTime.parse(points.first['timestamp'].toString()) : DateTime.fromMillisecondsSinceEpoch(0));
    var endedAt = _tryParseDateTime(endedAtRaw) ?? (points.isNotEmpty ? DateTime.parse(points.last['timestamp'].toString()) : startedAt);

    final requiredAcc = _toDouble(widget.track['required_gps_accuracy_meters'] ?? widget.track['requiredGpsAccuracyMeters']) ?? 10.0;
    int? parseInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

    final localJson = <String, dynamic>{
      'name': name,
      'description': (widget.track['description'] ?? '').toString(),
      'synced': true,
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      'cloudTrackId': cloudId,
      'missionId': parseInt(widget.track['mission']),
      'missionName': widget.track['mission_name']?.toString(),
      'campaignId': parseInt(widget.track['campaign']),
      'campaignName': widget.track['campaign_name']?.toString(),
      'projectId': parseInt(widget.track['project']),
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'requiredGpsAccuracyMeters': requiredAcc,
      'points': points,
    };

    final tracksDir = await _userTracksDir();
    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }
    final base = _sanitizeFileName(name);
    final fileName = base.toLowerCase().endsWith('.json') ? base : '$base.json';
    final finalName = 'cloud_${cloudId}_$fileName';
    final file = File('${tracksDir.path}/$finalName');
    await file.writeAsString(jsonEncode(localJson));
  }

  Future<void> _prepareLocalThenShow() async {
    final cloudId = _cloudId();
    if (cloudId == null) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _message = 'Track has no id.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isPreparing = true;
      _message = null;
      _local = null;
    });

    final local = await _findLocalByCloudId(cloudId);
    if (local != null) {
      if (!mounted) return;
      setState(() {
        _local = local;
        _isPreparing = false;
      });
      return;
    }

    final status = _cloudStatus();
    if (status == 'pending' || status == 'processing') {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _message = 'Track is $status. Waiting for measurements…';
      });
      return;
    }

    final loggedIn = await _apiService.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _message = 'Login required to download this track.';
      });
      return;
    }

    try {
      await _downloadCloudToLocal(cloudId);
      final downloaded = await _findLocalByCloudId(cloudId);
      if (!mounted) return;
      setState(() {
        _local = downloaded;
        _isPreparing = false;
        _message = downloaded == null ? 'Downloaded, but no local file found.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _message = 'Download failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_local != null) {
      return LocalTrackDetailPage(
        track: _local!,
        initialShowMap: widget.initialShowMap,
      );
    }

    final title = (widget.track['name'] ?? 'Track').toString();
    final status = _cloudStatus();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Open-red'),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _prepareLocalThenShow,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isPreparing
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Downloading track data…'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _message ?? 'No local data available yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Status: $status',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

