import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GrabMapsClient {
  GrabMapsClient({
    required String apiKey,
    http.Client? httpClient,
    this.baseUrl = 'https://maps.grab.com',
  })  : _apiKey = apiKey,
        _httpClient = httpClient ?? http.Client();

  final String _apiKey;
  final http.Client _httpClient;
  final String baseUrl;
  final Map<String, _CachedGrabResponse> _cache = <String, _CachedGrabResponse>{};

  Future<Map<String, dynamic>> nearbyPlaces({
    required double lat,
    required double lng,
    double radiusKm = 1,
    int limit = 10,
    String rankBy = 'distance',
    String? language,
  }) {
    return _get(
      '/api/v1/maps/place/v2/nearby',
      {
        'location': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
        'radius': radiusKm.toString(),
        'limit': '$limit',
        'rankBy': rankBy,
        if (language != null && language.isNotEmpty) 'language': language,
      },
    );
  }

  Future<Map<String, dynamic>> searchPlaces({
    required String keyword,
    String? country,
    double? lat,
    double? lng,
    int limit = 10,
  }) {
    return _get(
      '/api/v1/maps/poi/v1/search',
      {
        'keyword': keyword,
        if (country != null && country.isNotEmpty) 'country': country,
        if (lat != null && lng != null)
          'location': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
        'limit': '$limit',
      },
    );
  }

  Future<Map<String, dynamic>> reverseGeocode({
    required double lat,
    required double lng,
    String? type,
  }) {
    return _get(
      '/api/v1/maps/poi/v1/reverse-geo',
      {
        'location': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
  }

  Future<Map<String, dynamic>> getDirections({
    required List<({double lat, double lng})> points,
    String profile = 'driving',
    String overview = 'full',
    bool latFirst = false,
    int? alternatives,
    List<String>? avoid,
  }) {
    final query = <String, String>{
      'profile': profile,
      'overview': overview,
      if (latFirst) 'lat_first': 'true',
      if (alternatives != null) 'alternatives': '$alternatives',
      if (avoid != null && avoid.isNotEmpty) 'avoid': avoid.join(','),
    };

    final coordinates = points
        .map((point) => '${point.lng},${point.lat}')
        .toList(growable: false);

    return _get(
      '/api/v1/maps/eta/v1/direction',
      query,
      repeatedParams: {'coordinates': coordinates},
    );
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query, {
    Map<String, List<String>> repeatedParams = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    final queryParts = <String>[
      for (final entry in query.entries)
        '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
    ];
    for (final entry in repeatedParams.entries) {
      for (final value in entry.value) {
        queryParts.add(
          '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}',
        );
      }
    }

    final rebuilt = Uri.parse(
      '$baseUrl$path${queryParts.isEmpty ? '' : '?${queryParts.join('&')}'}',
    );
    final cacheKey = rebuilt.toString();
    final now = DateTime.now();
    final cached = _cache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      _logGrabRequest(
        path: path,
        query: query,
        repeatedParams: repeatedParams,
        statusCode: 200,
        durationMs: 0,
        responseBody: cached.body,
        cacheHit: true,
      );
      return _cloneJsonMap(cached.body);
    }
    try {
      final response = await _httpClient.get(
        rebuilt,
        headers: {'Authorization': 'Bearer $_apiKey'},
      );
      final decoded = _decodeResponseBody(response.body);
      _logGrabRequest(
        path: path,
        query: query,
        repeatedParams: repeatedParams,
        statusCode: response.statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        responseBody: decoded,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GrabMapsException(
          statusCode: response.statusCode,
          message: 'Grab Maps request failed for $path',
          body: {
            'path': path,
            'query': query,
            if (repeatedParams.isNotEmpty) 'repeatedParams': repeatedParams,
            if (decoded is Map<String, dynamic>) ...decoded else 'raw': decoded,
          },
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw GrabMapsException(
          statusCode: response.statusCode,
          message: 'Grab Maps returned an unexpected payload',
          body: {'raw': decoded},
        );
      }

      _cache[cacheKey] = _CachedGrabResponse(
        body: _cloneJsonMap(decoded),
        expiresAt: now.add(_ttlForPath(path)),
      );
      return decoded;
    } catch (error) {
      if (error is! GrabMapsException) {
        _logGrabRequest(
          path: path,
          query: query,
          repeatedParams: repeatedParams,
          durationMs: stopwatch.elapsedMilliseconds,
          error: error,
        );
      }
      rethrow;
    }
  }

  dynamic _decodeResponseBody(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  void _logGrabRequest({
    required String path,
    required Map<String, String> query,
    required Map<String, List<String>> repeatedParams,
    required int durationMs,
    int? statusCode,
    dynamic responseBody,
    Object? error,
    bool cacheHit = false,
  }) {
    final logLine = <String, dynamic>{
      'source': 'grab_maps',
      'timestamp': DateTime.now().toIso8601String(),
      'method': 'GET',
      'path': path,
      'statusCode': statusCode,
      'durationMs': durationMs,
      'ok': statusCode != null && statusCode >= 200 && statusCode < 300,
      'cacheHit': cacheHit,
      'query': query,
      if (repeatedParams.isNotEmpty) 'repeatedParams': repeatedParams,
      if (error != null) 'error': error.toString(),
      if (statusCode != null && statusCode >= 400)
        'responseBody': _truncateForLog(responseBody),
    };
    stdout.writeln(jsonEncode(logLine));
  }

  Duration _ttlForPath(String path) {
    if (path.contains('/direction')) {
      return const Duration(seconds: 20);
    }
    if (path.contains('/nearby') || path.contains('/search')) {
      return const Duration(seconds: 45);
    }
    return const Duration(minutes: 2);
  }

  Map<String, dynamic> _cloneJsonMap(Map<String, dynamic> input) {
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(input)) as Map<String, dynamic>,
    );
  }

  dynamic _truncateForLog(dynamic value) {
    final encoded = jsonEncode(value);
    if (encoded.length <= 800) {
      return value;
    }
    return '${encoded.substring(0, 800)}...';
  }
}

class _CachedGrabResponse {
  _CachedGrabResponse({
    required this.body,
    required this.expiresAt,
  });

  final Map<String, dynamic> body;
  final DateTime expiresAt;
}

class GrabMapsException implements Exception {
  GrabMapsException({
    required this.statusCode,
    required this.message,
    required this.body,
  });

  final int statusCode;
  final String message;
  final Map<String, dynamic> body;

  @override
  String toString() => 'GrabMapsException($statusCode): $message';
}
