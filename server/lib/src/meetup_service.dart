import 'dart:math' as math;

import 'grab_maps_client.dart';

class MeetupService {
  MeetupService(this._client);

  final GrabMapsClient _client;

  static const Map<String, List<String>> _categoryAliases = {
    'restaurant': [
      'restaurant',
      'food',
      'f&b',
      'diner',
      'eatery',
      'kitchen',
      'grill',
      'bistro',
    ],
    'cafe': [
      'cafe',
      'coffee',
      'espresso',
      'latte',
      'bakery',
      'tea',
      'dessert',
    ],
    'bar': [
      'bar',
      'pub',
      'cocktail',
      'brew',
      'taproom',
      'speakeasy',
      'wine',
      'beer',
    ],
    'hawker': [
      'hawker',
      'food court',
      'kopitiam',
      'canteen',
      'foodhub',
    ],
    'mall': [
      'mall',
      'shopping',
      'plaza',
      'centre',
      'center',
      'retail',
      'department store',
    ],
  };

  static const List<String> _residentialTerms = [
    'residential',
    'residence',
    'apartment',
    'apartments',
    'condominium',
    'condo',
    'housing',
    'hdb',
    'block ',
    'tower ',
    'villa',
    'estate',
  ];

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

    final normalizedKeyword = keyword?.trim().toLowerCase();
    final searchLimit = math.max(candidateLimit * 3, candidateLimit + 8);

    final centroid = _computeCentroid(normalizedFriends);
    final nearbyResponse = await _client.nearbyPlaces(
      lat: centroid.lat,
      lng: centroid.lng,
      radiusKm: radiusKm,
      limit: searchLimit,
      rankBy: rankBy,
      language: language,
    );

    final candidates = ((nearbyResponse['places'] as List?) ?? const [])
        .whereType<Map>()
        .map((place) => Map<String, dynamic>.from(place.cast<String, dynamic>()))
        .where(_isUsefulVenueCandidate)
        .toList();

    if (normalizedKeyword != null && normalizedKeyword.isNotEmpty) {
      final searchResponse = await _client.searchPlaces(
        keyword: normalizedKeyword,
        country: country,
        lat: centroid.lat,
        lng: centroid.lng,
        limit: searchLimit,
      );
      final searchCandidates = (searchResponse['places'] as List? ?? const [])
          .whereType<Map>()
          .map((place) => Map<String, dynamic>.from(place.cast<String, dynamic>()))
          .where(_isUsefulVenueCandidate)
          .where(
            (place) => _withinRadius(
              centroid,
              (
                lat: _extractLat(place),
                lng: _extractLng(place),
              ),
              radiusKm,
            ),
          )
          .toList();
      candidates.addAll(searchCandidates);
    }

    final deduped = _dedupeCandidates(candidates).toList();
    final filteredCandidates = normalizedKeyword == null || normalizedKeyword.isEmpty
        ? deduped
        : deduped
            .where((candidate) => _matchesCategory(candidate, normalizedKeyword))
            .toList();
    final rankedCandidates = filteredCandidates.take(candidateLimit).toList();
    final ranked = <Map<String, dynamic>>[];

    for (final candidate in rankedCandidates) {
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
      'rawCandidateCount': candidates.length,
      'filteredCandidateCount': rankedCandidates.length,
      'candidateCount': ranked.length,
      'appliedKeyword': normalizedKeyword,
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

  bool _isUsefulVenueCandidate(Map<String, dynamic> place) {
    final lat = _extractLatOrNull(place);
    final lng = _extractLngOrNull(place);
    if (lat == null || lng == null) {
      return false;
    }

    final name = (place['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return false;
    }

    final searchableText = _placeSearchBlob(place);
    if (searchableText.isEmpty) {
      return false;
    }

    for (final term in _residentialTerms) {
      if (searchableText.contains(term)) {
        return false;
      }
    }

    return true;
  }

  bool _matchesCategory(Map<String, dynamic> place, String keyword) {
    final searchableText = _placeSearchBlob(place);
    if (searchableText.isEmpty) {
      return false;
    }

    final aliases = _categoryAliases[keyword] ?? <String>[keyword];
    return aliases.any(searchableText.contains);
  }

  String _placeSearchBlob(Map<String, dynamic> place) {
    final fields = <String>[
      if (place['name'] != null) place['name'].toString(),
      if (place['business_type'] != null) place['business_type'].toString(),
      if (place['category'] != null) place['category'].toString(),
      if (place['formatted_address'] != null)
        place['formatted_address'].toString(),
      if (place['address'] != null) place['address'].toString(),
    ];

    final categories = place['categories'];
    if (categories is List) {
      for (final item in categories.whereType<Map>()) {
        final name = item['category_name']?.toString();
        if (name != null && name.isNotEmpty) {
          fields.add(name);
        }
      }
    }

    return fields.join(' ').toLowerCase();
  }

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
  final value = _extractLatOrNull(place);
  if (value == null) {
    throw StateError('Place is missing latitude.');
  }
  return value;
}

double? _extractLatOrNull(Map<String, dynamic> place) {
  final location = place['location'];
  if (location is Map && location['latitude'] != null) {
    return (location['latitude'] as num).toDouble();
  }
  final value = place['lat'];
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

double _extractLng(Map<String, dynamic> place) {
  final value = _extractLngOrNull(place);
  if (value == null) {
    throw StateError('Place is missing longitude.');
  }
  return value;
}

double? _extractLngOrNull(Map<String, dynamic> place) {
  final location = place['location'];
  if (location is Map && location['longitude'] != null) {
    return (location['longitude'] as num).toDouble();
  }
  final value = place['lng'];
  if (value is num) {
    return value.toDouble();
  }
  return null;
}
