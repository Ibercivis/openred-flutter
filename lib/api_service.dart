import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

enum H3AggregationSource {
  radiation,
  lightPollution,
}

class ApiService {
  static String get baseUrl => Config.apiBaseUrl;
  static String get authBaseUrl => Config.authBaseUrl;

  static const String _prefsAuthTokenKey = 'auth_token';
  static const String _prefsAuthUserIdKey = 'auth_user_id';
  
  // Set to false to use real API
  static const bool useMockApi = false;
  
  // Get stored auth token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsAuthTokenKey);
  }
  
  // Save auth token
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAuthTokenKey, token);
  }
  
  // Remove auth token (logout)
  Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAuthTokenKey);
    await prefs.remove(_prefsAuthUserIdKey);
  }

  Future<int?> getStoredUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsAuthUserIdKey);
  }

  Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsAuthUserIdKey, userId);
  }

  Future<void> removeUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAuthUserIdKey);
  }

  /// Returns the stable backend user id for the currently logged-in user.
  /// Uses a cached value when possible; falls back to `getProfile()`.
  Future<int?> getCurrentUserId({bool refresh = false}) async {
    print('[ApiService.getCurrentUserId] Starting (refresh: $refresh)');
    
    if (!refresh) {
      final cached = await getStoredUserId();
      print('[ApiService.getCurrentUserId] Cached user ID: $cached');
      if (cached != null) return cached;
    }

    print('[ApiService.getCurrentUserId] Calling getProfile()...');
    final profile = await getProfile();
    print('[ApiService.getCurrentUserId] getProfile result: $profile');
    
    if (profile['success'] == true) {
      final user = profile['user'];
      if (user is Map) {
        final idRaw = user['id'] ?? user['pk'];
        final id = (idRaw is int) ? idRaw : int.tryParse(idRaw?.toString() ?? '');
        print('[ApiService.getCurrentUserId] Extracted user ID: $id');
        if (id != null) {
          await saveUserId(id);
          return id;
        }
      }
    }

    print('[ApiService.getCurrentUserId] Returning null');
    return null;
  }

  Future<http.Response> _authorizedGet(Uri uri, {required String token}) async {
    Future<http.Response> doGet(String authorizationHeader) {
      return http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authorizationHeader,
        },
      );
    }

    // Prefer Bearer auth (matches the curl example)
    var response = await doGet('Bearer $token');
    if (response.statusCode == 401 || response.statusCode == 403) {
      response = await doGet('Token $token');
    }
    return response;
  }

  Future<http.Response> _authorizedDelete(Uri uri, {required String token}) async {
    Future<http.Response> doDelete(String authorizationHeader) {
      return http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authorizationHeader,
        },
      );
    }

    // Prefer Bearer auth (matches the curl example)
    var response = await doDelete('Bearer $token');
    if (response.statusCode == 401 || response.statusCode == 403) {
      response = await doDelete('Token $token');
    }
    return response;
  }

  Map<String, dynamic> _decodeMapOrDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'detail': decoded.toString()};
    } catch (_) {
      return {'detail': body};
    }
  }

  Future<List<dynamic>> _fetchAllPages({
    required Uri initialUri,
    required String token,
  }) async {
    final items = <dynamic>[];
    Uri? uri = initialUri;

    while (uri != null) {
      final response = await _authorizedGet(uri, token: token);
      if (response.statusCode != 200) {
        final data = _decodeMapOrDetail(response.body);
        throw Exception(data['detail'] ?? 'Request failed (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        items.addAll(decoded);
        break;
      }

      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        final results = m['results'];
        if (results is List) {
          items.addAll(results);
        }

        final next = m['next'];
        if (next is String && next.trim().isNotEmpty) {
          uri = Uri.parse(next);
          continue;
        }
        break;
      }

      break;
    }

    return items;
  }
  
  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    final result = token != null && token.isNotEmpty;
    print('ApiService.isLoggedIn() - token: ${token?.substring(0, 10)}..., result: $result');
    return result;
  }
  
  // Login user
  Future<Map<String, dynamic>> login(String email, String password) async {
    if (useMockApi) {
      // Mock API response
      await Future.delayed(const Duration(seconds: 1));
      
      // Simulate login validation
      if (email.isNotEmpty && password.length >= 6) {
        final mockToken = 'mock_token_${DateTime.now().millisecondsSinceEpoch}';
        await saveToken(mockToken);
        
        return {
          'success': true,
          'token': mockToken,
          'user': {
            'id': 1,
            'name': 'Test User',
            'email': email,
          }
        };
      } else {
        return {
          'success': false,
          'message': 'Invalid credentials'
        };
      }
    }
    
    // Real API call
    try {
      final response = await http.post(
        Uri.parse('$authBaseUrl/dj-rest-auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        // dj-rest-auth returns token in 'key' field
        final token = data['key'] ?? data['token'];
        if (token != null) {
          await saveToken(token);
          return {'success': true, 'token': token, 'user': data['user']};
        }
      }
      
      return {
        'success': false,
        'message': data['non_field_errors']?[0] ?? data['detail'] ?? 'Login failed'
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  // Login/register using Google OAuth access token (dj-rest-auth + allauth)
  // POST /dj-rest-auth/google/ { "access_token": "ya29..." }
  // Successful response: { "key": "...", "user": { ... } }
  Future<Map<String, dynamic>> loginWithGoogleAccessToken(String accessToken) async {
    if (useMockApi) {
      await Future.delayed(const Duration(seconds: 1));
      final mockToken = 'mock_google_token_${DateTime.now().millisecondsSinceEpoch}';
      await saveToken(mockToken);
      return {
        'success': true,
        'token': mockToken,
        'user': {
          'id': 1,
          'email': 'test@example.com',
          'username': 'test_example_com',
        },
      };
    }

    try {
      final response = await http.post(
        Uri.parse('$authBaseUrl/dj-rest-auth/google/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'access_token': accessToken}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final token = data['key'] ?? data['token'];
        if (token != null) {
          await saveToken(token);
          return {'success': true, 'token': token, 'user': data['user']};
        }
        return {
          'success': false,
          'message': 'Login succeeded but no token returned',
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? (data['non_field_errors']?[0] ?? data['detail'] ?? 'Google login failed')
            : 'Google login failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
  
  // Register new user
  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) async {
    if (useMockApi) {
      // Mock API response
      await Future.delayed(const Duration(seconds: 1));
      
      // Simulate registration validation
      if (name.isNotEmpty && email.contains('@') && password.length >= 6) {
        final mockToken = 'mock_token_${DateTime.now().millisecondsSinceEpoch}';
        await saveToken(mockToken);
        
        return {
          'success': true,
          'token': mockToken,
          'user': {
            'id': DateTime.now().millisecondsSinceEpoch,
            'name': name,
            'email': email,
          }
        };
      } else {
        return {
          'success': false,
          'message': 'Invalid registration data'
        };
      }
    }
    
    // Real API call
    try {
      final response = await http.post(
        Uri.parse('$authBaseUrl/dj-rest-auth/registration/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': email.split('@')[0], // Use email prefix as username
          'email': email,
          'password1': password,
          'password2': password,
        }),
      );
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        final token = data['key'] ?? data['token'];
        if (token != null) {
          await saveToken(token);
          return {'success': true, 'token': token, 'user': data['user']};
        }
      }
      
      // Handle validation errors
      String errorMessage = 'Registration failed';
      if (data['email'] != null) {
        errorMessage = data['email'][0];
      } else if (data['password1'] != null) {
        errorMessage = data['password1'][0];
      } else if (data['username'] != null) {
        errorMessage = data['username'][0];
      } else if (data['non_field_errors'] != null) {
        errorMessage = data['non_field_errors'][0];
      }
      
      return {
        'success': false,
        'message': errorMessage
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }
  
  // Get user profile
  Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    
    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }
    
    if (useMockApi) {
      // Mock API response
      await Future.delayed(const Duration(milliseconds: 500));
      
      return {
        'success': true,
        'user': {
          'id': 1,
          'name': 'Test User',
          'email': 'test@example.com',
          'created_at': '2025-01-01',
        }
      };
    }
    
    // Real API call
    try {
      final uri = Uri.parse('$authBaseUrl/dj-rest-auth/user/');
      final response = await _authorizedGet(uri, token: token);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (data is Map) {
          final idRaw = data['id'] ?? data['pk'];
          final id = (idRaw is int) ? idRaw : int.tryParse(idRaw?.toString() ?? '');
          if (id != null) {
            await saveUserId(id);
          }
        }
        return {'success': true, 'user': data};
      }

      final message = (data is Map)
          ? (data['detail'] ?? data['message'] ?? 'Failed to fetch profile')
          : 'Failed to fetch profile';
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }
  
  // Get user's tracks
  Future<Map<String, dynamic>> getMyTracks() async {
    final token = await getToken();
    
    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }
    
    try {
      final items = await _fetchAllPages(
        initialUri: Uri.parse('$baseUrl/tracks/my_tracks/'),
        token: token,
      );
      return {
        'success': true,
        'tracks': items,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  // Get tracks (preferred). Falls back to /tracks/my_tracks/ if /tracks/ isn't available.
  Future<Map<String, dynamic>> getTracks() async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }

    try {
      try {
        final items = await _fetchAllPages(
          initialUri: Uri.parse('$baseUrl/tracks/'),
          token: token,
        );
        return {
          'success': true,
          'tracks': items,
        };
      } catch (_) {
        final items = await _fetchAllPages(
          initialUri: Uri.parse('$baseUrl/tracks/my_tracks/'),
          token: token,
        );
        return {
          'success': true,
          'tracks': items,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  Future<Map<String, dynamic>> deleteTrack(int trackId) async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }

    try {
      final response = await _authorizedDelete(
        Uri.parse('$baseUrl/tracks/$trackId/'),
        token: token,
      );

      // DRF typically returns 204 No Content on delete.
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {
          'success': true,
        };
      }

      final data = _decodeMapOrDetail(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to delete track',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  // Get available missions (used when saving/syncing local tracks)
  // List missions in a project: GET /api/projects/{project_id}/missions/
  Future<Map<String, dynamic>> getMissions({required int projectId}) async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }

    try {
      final uri = Uri.parse('$baseUrl/projects/$projectId/missions/');
      final response = await _authorizedGet(uri, token: token);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List missions;
        if (data is List) {
          missions = data;
        } else if (data is Map && data['results'] is List) {
          missions = data['results'] as List;
        } else {
          missions = const [];
        }
        return {
          'success': true,
          'missions': missions,
        };
      } else {
        final data = _decodeMapOrDetail(response.body);
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': (data['detail'] ?? data['message'] ?? 'Failed to fetch missions').toString(),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  // Get campaigns filtered by mission + project
  Future<Map<String, dynamic>> getCampaigns({
    required int missionId,
  }) async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }

    try {
      final uri = Uri.parse('$baseUrl/missions/$missionId/campaigns/');

      final response = await _authorizedGet(uri, token: token);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List campaigns;
        if (data is List) {
          campaigns = data;
        } else if (data is Map && data['results'] is List) {
          campaigns = data['results'] as List;
        } else {
          campaigns = const [];
        }
        return {
          'success': true,
          'campaigns': campaigns,
        };
      } else {
        final data = _decodeMapOrDetail(response.body);
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': (data['detail'] ?? data['message'] ?? 'Failed to fetch campaigns').toString(),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }
  
  // Get radiation measurements for a track
  Future<Map<String, dynamic>> getTrackMeasurements(int trackId) async {
    final token = await getToken();
    
    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }
    
    try {
      final items = await _fetchAllPages(
        initialUri: Uri.parse('$baseUrl/radiation-measurements/?track=$trackId'),
        token: token,
      );
      return {
        'success': true,
        'measurements': items,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  /// Backend data source for H3 aggregation.
  ///
  /// - [H3AggregationSource.radiation] uses `/api/radiation-measurements/h3-aggregation-vertex/`
  /// - [H3AggregationSource.lightPollution] uses `/api/light-pollution-measurements/h3-aggregation-vertex/`
  ///
  /// Both are queried with the same bounding-box + resolution parameters.
  /// Some sources may ignore optional params like `measurementType`.
  ///
  /// Note: declared inside this file so callers can use a typed selector.
  static const _h3SourceRadiationPath = 'radiation-measurements';
  static const _h3SourceLightPath = 'light-pollution-measurements';

  static String _h3PathForSource(H3AggregationSource source) {
    switch (source) {
      case H3AggregationSource.radiation:
        return _h3SourceRadiationPath;
      case H3AggregationSource.lightPollution:
        return _h3SourceLightPath;
    }
  }

  /// Fetch H3 aggregation (hexagons) for a given source.
  ///
  /// Endpoint (radiation example):
  /// `/api/radiation-measurements/h3-aggregation-vertex/?resolution=..&project=..&measurementType=..&north=..&south=..&east=..&west=..`
  ///
  /// Endpoint (light pollution):
  /// `/api/light-pollution-measurements/h3-aggregation-vertex/?resolution=..&project=..&north=..&south=..&east=..&west=..`
  ///
  /// This method returns the decoded JSON payload as `data` and leaves
  /// interpretation of the response shape to callers.
  Future<Map<String, dynamic>> getH3Aggregation({
    required H3AggregationSource source,
    required int resolution,
    required int projectId,
    String? measurementType,
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    try {
      final queryParameters = <String, String>{
        'resolution': resolution.toString(),
        'project': projectId.toString(),
        'north': north.toString(),
        'south': south.toString(),
        'east': east.toString(),
        'west': west.toString(),
      };

      final mt = measurementType?.trim();
      if (mt != null && mt.isNotEmpty) {
        queryParameters['measurementType'] = mt;
      }

      final path = _h3PathForSource(source);
      final uri = Uri.parse('$baseUrl/$path/h3-aggregation-vertex/').replace(
        queryParameters: queryParameters,
      );

      final token = await getToken();
      final http.Response response;
      if (token != null && token.isNotEmpty) {
        response = await _authorizedGet(uri, token: token);
      } else {
        response = await http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
          },
        );
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'success': true,
          'data': decoded,
        };
      }

      final detail = _decodeMapOrDetail(response.body)['detail'];
      return {
        'success': false,
        'message': detail?.toString() ?? 'Failed to fetch h3 aggregation (${response.statusCode})',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  // Create a new track (used for syncing local tracks)
  Future<Map<String, dynamic>> createTrack({
    required String name,
    DateTime? startedAt,
    DateTime? endedAt,
    int? campaignId,
  }) async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }

    try {
      final body = <String, dynamic>{
        'name': name,
      };

      if (campaignId != null) {
        body['campaign'] = campaignId;
      }

      // These field names match typical REST patterns; if the server uses
      // different names it will return a validation error which we surface.
      if (startedAt != null) {
        body['start_time'] = startedAt.toUtc().toIso8601String();
      }
      if (endedAt != null) {
        body['end_time'] = endedAt.toUtc().toIso8601String();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/tracks/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'track': data,
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? (data['detail']?.toString() ?? data.toString())
            : 'Failed to create track',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  // Upload one radiation measurement
  Future<Map<String, dynamic>> createRadiationMeasurement({
    required int trackId,
    required Map<String, dynamic> measurement,
  }) async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated'
      };
    }

    try {
      final payload = <String, dynamic>{
        ...measurement,
        // Many APIs use `track` as FK field.
        'track': trackId,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/radiation-measurements/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'measurement': data,
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? (data['detail']?.toString() ?? data.toString())
            : 'Failed to create measurement',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e'
      };
    }
  }

  // Upload a full track as JSON (single request)
  // POST /api/tracks/upload_json/ (expects Authorization: Bearer <token> per spec)
  // We also fall back to Token auth for compatibility with dj-rest-auth TokenAuthentication.
  Future<Map<String, dynamic>> uploadTrackJson({
    required Map<String, dynamic> trackJson,
  }) async {
    final token = await getToken();

    if (token == null) {
      return {
        'success': false,
        'message': 'Not authenticated',
      };
    }

    Future<http.Response> doPost(String authorizationHeader) {
      return http.post(
        Uri.parse('$baseUrl/tracks/upload_json/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authorizationHeader,
        },
        body: jsonEncode(trackJson),
      );
    }

    Map<String, dynamic> decodeBody(String body) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return {'detail': decoded.toString()};
      } catch (_) {
        return {'detail': body};
      }
    }

    String extractErrorMessage(Map<String, dynamic> data) {
      // Common DRF/dj-rest-auth shapes.
      final nonField = data['non_field_errors'];
      if (nonField is List && nonField.isNotEmpty) {
        return nonField.first.toString();
      }

      final campaignPassword = data['campaign_password'] ?? data['campaignPassword'];
      if (campaignPassword is List && campaignPassword.isNotEmpty) {
        return campaignPassword.first.toString();
      }

      final detail = data['detail'];
      if (detail != null) return detail.toString();

      // Fallback: first stringy field.
      for (final entry in data.entries) {
        final v = entry.value;
        if (v is String && v.trim().isNotEmpty) return v;
        if (v is List && v.isNotEmpty) return v.first.toString();
      }

      return data.toString();
    }

    try {
      // Prefer Bearer auth (matches provided curl example)
      var response = await doPost('Bearer $token');
      var data = decodeBody(response.body);

      // Fallback to Token auth if server rejects Bearer.
      if (response.statusCode == 401 || response.statusCode == 403) {
        response = await doPost('Token $token');
        data = decodeBody(response.body);
      }

      // Some backends enqueue processing and respond with 202 Accepted.
      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
        return {
          'success': true,
          'track': data,
        };
      }

      return {
        'success': false,
        'message': extractErrorMessage(data),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
  
  // Logout user
  Future<void> logout() async {
    await removeToken();
  }
}
