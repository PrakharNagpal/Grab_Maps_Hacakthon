import 'dart:convert';

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
    final response = await _httpClient.get(
      rebuilt,
      headers: {'Authorization': 'Bearer $_apiKey'},
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GrabMapsException(
        statusCode: response.statusCode,
        message: 'Grab Maps request failed',
        body: decoded is Map<String, dynamic> ? decoded : {'raw': decoded},
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw GrabMapsException(
        statusCode: response.statusCode,
        message: 'Grab Maps returned an unexpected payload',
        body: {'raw': decoded},
      );
    }

    return decoded;
  }
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
