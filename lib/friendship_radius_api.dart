import 'package:dio/dio.dart';

class FriendshipRadiusApi {
  FriendshipRadiusApi({
    Dio? dio,
    String? baseUrl,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ??
                    const String.fromEnvironment(
                      'FRIENDSHIP_RADIUS_API_BASE_URL',
                      defaultValue: 'http://127.0.0.1:8080',
                    ),
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
                headers: const {'Content-Type': 'application/json'},
              ),
            );

  final Dio _dio;

  Future<ProxyHealth> health() async {
    final response = await _dio.get<Map<String, dynamic>>('/health');
    final data = response.data ?? const <String, dynamic>{};
    return ProxyHealth(
      ok: data['ok'] == true,
      hasApiKey: data['hasApiKey'] == true,
    );
  }

  Future<Map<String, dynamic>> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/reverse-geocode',
      data: {
        'lat': lat,
        'lng': lng,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> searchPlaces({
    required String keyword,
    String? country,
    double? lat,
    double? lng,
    int limit = 6,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/places/search',
      data: {
        'keyword': keyword,
        if (country != null && country.trim().isNotEmpty)
          'country': country.trim(),
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        'limit': limit,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> rankMeetup({
    required List<Map<String, dynamic>> friends,
    String? keyword,
    double radiusKm = 2,
    int candidateLimit = 6,
    String profile = 'driving',
    String rankBy = 'distance',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/meetup/rank',
      data: {
        'friends': friends,
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword': keyword.trim(),
        'radiusKm': radiusKm,
        'candidateLimit': candidateLimit,
        'profile': profile,
        'rankBy': rankBy,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }
}

class ProxyHealth {
  const ProxyHealth({
    required this.ok,
    required this.hasApiKey,
  });

  final bool ok;
  final bool hasApiKey;
}
