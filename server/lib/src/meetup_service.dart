import 'dart:math' as math;

import 'grab_maps_client.dart';

class MeetupService {
  MeetupService(this._client);

  final GrabMapsClient _client;

  Future<Map<String, dynamic>> rankMeetup({
    required List<Map<String, dynamic>> friends,
    String? keyword,
    String? country,
    double radiusKm = 2,
    int candidateLimit = 8,
    String profile = 'driving',
    String rankBy = 'distance',
    String? language,
  }) async {
    if (friends.length < 2) {
      throw ArgumentError('At least two friends are required.');
    }

    final normalizedFriends = friends
        .asMap()
        .entries
        .map(
          (entry) => (
            id: (entry.value['id'] ?? 'friend-${entry.key + 1}').toString(),
            lat: (entry.value['lat'] as num).toDouble(),
            lng: (entry.value['lng'] as num).toDouble(),
          ),
        )
        .toList(growable: false);

    final centroid = _computeCentroid(normalizedFriends);
    final nearbyResponse = await _client.nearbyPlaces(
      lat: centroid.lat,
      lng: centroid.lng,
      radiusKm: radiusKm,
      limit: candidateLimit,
      rankBy: rankBy,
      language: language,
    );

    final candidates = ((nearbyResponse['places'] as List?) ?? const [])
        .whereType<Map>()
        .map((place) => Map<String, dynamic>.from(place.cast<String, dynamic>()))
        .toList();

    if (keyword != null && keyword.trim().isNotEmpty) {
      final searchResponse = await _client.searchPlaces(
        keyword: keyword.trim(),
        country: country,
        lat: centroid.lat,
        lng: centroid.lng,
        limit: candidateLimit,
      );
      final searchCandidates = (searchResponse['places'] as List? ?? const [])
          .whereType<Map>()
          .map((place) => Map<String, dynamic>.from(place.cast<String, dynamic>()))
          .where(
            (place) => _withinRadius(
              centroid,
              (
                lat: _extractLat(place),
                lng: _extractLng(place),
              ),
              radiusKm,
            ),
          );
      candidates.addAll(searchCandidates);
    }

    final deduped = _dedupeCandidates(candidates).take(candidateLimit).toList();
    final ranked = <Map<String, dynamic>>[];

    for (final candidate in deduped) {
      final candidateLat = _extractLat(candidate);
      final candidateLng = _extractLng(candidate);

      final routes = await Future.wait(
        normalizedFriends.map((friend) async {
          final direction = await _client.getDirections(
            points: [
              (lat: friend.lat, lng: friend.lng),
              (lat: candidateLat, lng: candidateLng),
            ],
            profile: profile,
            overview: 'full',
          );
          final routes = (direction['routes'] as List?) ?? const [];
          final route = routes.isEmpty ? null : routes.first;
          final routeMap = route is Map
              ? Map<String, dynamic>.from(route.cast<String, dynamic>())
              : <String, dynamic>{};
          return {
            'friendId': friend.id,
            'origin': {'lat': friend.lat, 'lng': friend.lng},
            'durationSeconds': (routeMap['duration'] as num?)?.toDouble(),
            'distanceMeters': (routeMap['distance'] as num?)?.toDouble(),
            'geometry': routeMap['geometry'],
            'legs': routeMap['legs'],
          };
        }),
      );

      final durations = routes
          .map((route) => route['durationSeconds'])
          .whereType<double>()
          .toList(growable: false);
      if (durations.length != normalizedFriends.length) {
        continue;
      }

      final minDuration = durations.reduce((a, b) => a < b ? a : b);
      final maxDuration = durations.reduce((a, b) => a > b ? a : b);
      final totalDuration = durations.fold<double>(0, (sum, item) => sum + item);

      ranked.add({
        'place': candidate,
        'score': {
          'unfairnessSeconds': maxDuration - minDuration,
          'maxDurationSeconds': maxDuration,
          'minDurationSeconds': minDuration,
          'totalDurationSeconds': totalDuration,
          'averageDurationSeconds': totalDuration / durations.length,
        },
        'routes': routes,
      });
    }

    ranked.sort((a, b) {
      final aScore = Map<String, dynamic>.from(a['score'] as Map);
      final bScore = Map<String, dynamic>.from(b['score'] as Map);
      return _compareScore(aScore, bScore);
    });

    return {
      'centroid': {'lat': centroid.lat, 'lng': centroid.lng},
      'friendCount': normalizedFriends.length,
      'candidateCount': ranked.length,
      'results': ranked,
      'winner': ranked.isEmpty ? null : ranked.first,
    };
  }

  ({double lat, double lng}) _computeCentroid(
    List<({String id, double lat, double lng})> friends,
  ) {
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final friend in friends) {
      latSum += friend.lat;
      lngSum += friend.lng;
    }
    return (lat: latSum / friends.length, lng: lngSum / friends.length);
  }

  Iterable<Map<String, dynamic>> _dedupeCandidates(
    List<Map<String, dynamic>> candidates,
  ) sync* {
    final seen = <String>{};
    for (final candidate in candidates) {
      final key = (candidate['poi_id'] ??
              candidate['id'] ??
              '${candidate['name']}-${_extractLat(candidate)}-${_extractLng(candidate)}')
          .toString();
      if (seen.add(key)) {
        yield candidate;
      }
    }
  }

  bool _withinRadius(
    ({double lat, double lng}) center,
    ({double lat, double lng}) point,
    double radiusKm,
  ) {
    return _distanceKm(center, point) <= radiusKm;
  }

  double _distanceKm(
    ({double lat, double lng}) a,
    ({double lat, double lng}) b,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(b.lat - a.lat);
    final dLng = _toRadians(b.lng - a.lng);
    final lat1 = _toRadians(a.lat);
    final lat2 = _toRadians(b.lat);

    final haversine = (_sinHalf(dLat) * _sinHalf(dLat)) +
        (_sinHalf(dLng) * _sinHalf(dLng) * _cos(lat1) * _cos(lat2));
    final arc = 2 * _atan2SquareRoot(haversine);
    return earthRadiusKm * arc;
  }

  double _toRadians(double degrees) => degrees * 0.017453292519943295;

  double _cos(double value) => math.cos(value);

  int _compareScore(Map<String, dynamic> a, Map<String, dynamic> b) {
    final unfairnessCompare = (a['unfairnessSeconds'] as num)
        .compareTo(b['unfairnessSeconds'] as num);
    if (unfairnessCompare != 0) {
      return unfairnessCompare;
    }

    final maxDurationCompare = (a['maxDurationSeconds'] as num)
        .compareTo(b['maxDurationSeconds'] as num);
    if (maxDurationCompare != 0) {
      return maxDurationCompare;
    }

    return (a['totalDurationSeconds'] as num)
        .compareTo(b['totalDurationSeconds'] as num);
  }
}

double _sinHalf(double angle) => math.sin(angle / 2);

double _atan2SquareRoot(double haversine) =>
    math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));

double _extractLat(Map<String, dynamic> place) {
  final location = place['location'];
  if (location is Map && location['latitude'] != null) {
    return (location['latitude'] as num).toDouble();
  }
  return (place['lat'] as num).toDouble();
}

double _extractLng(Map<String, dynamic> place) {
  final location = place['location'];
  if (location is Map && location['longitude'] != null) {
    return (location['longitude'] as num).toDouble();
  }
  return (place['lng'] as num).toDouble();
}
