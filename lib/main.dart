import 'dart:convert';
import 'dart:math' as math;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'friendship_radius_api.dart';
import 'map_bridge.dart';
import 'polyline_codec.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friendship Radius',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF166534)),
        useMaterial3: true,
        fontFamily: 'ArialUnicode',
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const bool _showRouteLines = false;
  static const _searchPhases = <String>[
    'Finding real venues near the group',
    'Calculating travel times for each friend',
    'Ranking the fairest compromise',
  ];

  final _mapBridge = MapBridge();
  final _api = FriendshipRadiusApi();
  final _friendSearchController = TextEditingController();
  final _maxDistanceController = TextEditingController(text: '5');

  final List<_FriendLocation> _friends = [];
  final List<_MeetingResult> _results = [];
  final Set<String> _renderedFriendIds = <String>{};
  _CenterComparison? _centerComparison;
  final List<_LocationSearchCandidate> _friendSearchResults = [];

  html.EventListener? _mapClickListener;

  bool _mapLoaded = false;
  bool _proxyHealthy = false;
  bool _proxyHasKey = false;
  bool _isAddingFriend = false;
  bool _isRunningSearch = false;
  bool _isComparingCategories = false;
  bool _isSearchingFriendLocation = false;
  bool _didBootstrap = false;
  int _selectedResultIndex = 0;
  int _searchTickerToken = 0;

  String _mapStatus = 'Loading map...';
  String _proxyStatus = 'Checking Shelf proxy...';
  String _meetupStatus = 'Preparing your map...';
  String _searchStage = _searchPhases.first;
  String _selectedCategory = 'bar';
  String _selectedProfile = 'driving';
  String? _movingFriendId;
  final List<_CategoryComparisonResult> _categoryComparisons = [];

  static const _friendTemplates = <_FriendTemplate>[
    _FriendTemplate(label: 'A', color: '#EF4444'),
    _FriendTemplate(label: 'B', color: '#3B82F6'),
    _FriendTemplate(label: 'C', color: '#F59E0B'),
    _FriendTemplate(label: 'D', color: '#8B5CF6'),
    _FriendTemplate(label: 'E', color: '#10B981'),
  ];

  static const _categoryOptions = <_CategoryOption>[
    _CategoryOption(label: 'Restaurant', keyword: 'restaurant'),
    _CategoryOption(label: 'Cafe', keyword: 'cafe'),
    _CategoryOption(label: 'Bar', keyword: 'bar'),
    _CategoryOption(label: 'Hawker', keyword: 'hawker'),
    _CategoryOption(label: 'Mall', keyword: 'mall'),
  ];

  static const _profileOptions = <_ProfileOption>[
    _ProfileOption(label: 'Driving', value: 'driving'),
    _ProfileOption(label: 'Motorcycle', value: 'motorcycle'),
    _ProfileOption(label: 'Tricycle', value: 'tricycle'),
    _ProfileOption(label: 'Cycling', value: 'cycling'),
    _ProfileOption(label: 'Walking', value: 'walking'),
  ];

  static const _recommendedFarPlaces = <_RecommendedFarPlace>[
    _RecommendedFarPlace(
      name: 'Marina Bay Sands',
      subtitle: 'Iconic skyline destination',
      lat: 1.2834,
      lng: 103.8607,
      categoryKeywords: ['mall', 'bar', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'Gardens by the Bay',
      subtitle: 'Waterfront landmark',
      lat: 1.2816,
      lng: 103.8636,
      categoryKeywords: ['cafe', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'Jewel Changi Airport',
      subtitle: 'Famous shopping and dining hub',
      lat: 1.3603,
      lng: 103.9894,
      categoryKeywords: ['mall', 'cafe', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'Newton Food Centre',
      subtitle: 'Popular local food spot',
      lat: 1.3127,
      lng: 103.8390,
      categoryKeywords: ['hawker', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'Lau Pa Sat',
      subtitle: 'Historic hawker destination',
      lat: 1.2806,
      lng: 103.8507,
      categoryKeywords: ['hawker', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'Haji Lane',
      subtitle: 'Trendy cafe and bar strip',
      lat: 1.3008,
      lng: 103.8585,
      categoryKeywords: ['bar', 'cafe', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'Clarke Quay',
      subtitle: 'Riverside nightlife cluster',
      lat: 1.2906,
      lng: 103.8465,
      categoryKeywords: ['bar', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'ION Orchard',
      subtitle: 'Orchard flagship mall',
      lat: 1.3040,
      lng: 103.8318,
      categoryKeywords: ['mall', 'cafe', 'restaurant'],
    ),
    _RecommendedFarPlace(
      name: 'VivoCity',
      subtitle: 'Large lifestyle mall by the harbour',
      lat: 1.2644,
      lng: 103.8223,
      categoryKeywords: ['mall', 'restaurant', 'cafe'],
    ),
  ];

  static const _seedFriends = <({double lat, double lng})>[
    (lat: 1.2834, lng: 103.8607),
    (lat: 1.3009, lng: 103.8394),
    (lat: 1.3521, lng: 103.8198),
  ];

  @override
  void initState() {
    super.initState();
    _mapClickListener = (event) => _handleCustomMapClick(event);
    html.window.addEventListener('grabmaps-click', _mapClickListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _friendSearchController.dispose();
    _maxDistanceController.dispose();
    if (_mapClickListener != null) {
      html.window.removeEventListener('grabmaps-click', _mapClickListener);
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_didBootstrap) {
      return;
    }
    _didBootstrap = true;

    try {
      _initMap();
      if (!_mapLoaded) {
        return;
      }

      await Future<void>.delayed(const Duration(seconds: 2));
      _seedInitialFriends();
      await _checkProxy();
      await _resolveAllFriendAddresses();

      if (!mounted) {
        return;
      }
      setState(() {
        _meetupStatus =
            'Tap `Find Fairest Spot` to rank real venues for your current group.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _proxyStatus = 'Bootstrap failed: $error';
        _meetupStatus = 'Fix the setup issue above, then try again.';
      });
    }
  }

  void _initMap() {
    const apiKey = 'bm_1776994862_KawMha9ThhfhcffRIuVgjLRcynTD5DEk';
    final success = _mapBridge.init(apiKey);
    setState(() {
      _mapLoaded = success;
      final error = _mapBridge.lastError;
      _mapStatus = success
          ? 'Map loaded and ready for interaction.'
          : error.isEmpty
              ? 'Map failed to load'
              : 'Map failed to load: $error';
    });
  }

  Future<void> _checkProxy() async {
    setState(() {
      _proxyStatus = 'Checking Shelf proxy...';
    });

    try {
      final health = await _api.health();
      if (!mounted) {
        return;
      }
      setState(() {
        _proxyHealthy = health.ok;
        _proxyHasKey = health.hasApiKey;
        _proxyStatus = health.ok
            ? health.hasApiKey
                ? 'Proxy healthy and Grab API key is present.'
                : 'Proxy healthy, but GRAB_MAPS_API_KEY is missing.'
            : 'Proxy health check failed.';
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _proxyHealthy = false;
        _proxyHasKey = false;
        _proxyStatus = 'Proxy check failed: ${_describeDioError(error)}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _proxyHealthy = false;
        _proxyHasKey = false;
        _proxyStatus = 'Proxy check failed: $error';
      });
    }
  }

  void _seedInitialFriends() {
    if (_friends.isNotEmpty) {
      return;
    }

    for (var i = 0; i < _seedFriends.length; i++) {
      final template = _friendTemplates[i];
      final point = _seedFriends[i];
      _friends.add(
        _FriendLocation(
          id: 'friend_${template.label.toLowerCase()}',
          label: template.label,
          color: template.color,
          lat: point.lat,
          lng: point.lng,
        ),
      );
    }

    _syncFriendMarkers();
  }

  Future<void> _resolveAllFriendAddresses() async {
    if (!_proxyHealthy || !_proxyHasKey) {
      return;
    }
    await Future.wait(_friends.map(_resolveFriendAddress));
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _resolveFriendAddress(_FriendLocation friend) async {
    try {
      final response = await _api.reverseGeocode(
        lat: friend.lat,
        lng: friend.lng,
      );
      final places = (response['places'] as List?) ?? const [];
      if (places.isEmpty) {
        return;
      }
      final place = places.first;
      if (place is! Map) {
        return;
      }
      final data = Map<String, dynamic>.from(place.cast<String, dynamic>());
      final address = (data['formatted_address'] ?? data['name'])?.toString();
      if (address == null || address.isEmpty) {
        return;
      }
      friend.address = address;
    } catch (_) {
      // Leave the address empty if reverse geocoding fails.
    }
  }

  void _handleCustomMapClick(html.Event event) {
    if (!_isAddingFriend && _movingFriendId == null) {
      return;
    }

    final detail =
        event is html.CustomEvent ? event.detail?.toString() : null;
    if (detail == null || detail.isEmpty) {
      return;
    }

    final payload = jsonDecode(detail);
    if (payload is! Map<String, dynamic>) {
      return;
    }

    final lat = _readJsDouble(payload, 'lat');
    final lng = _readJsDouble(payload, 'lng');
    if (lat == null || lng == null) {
      return;
    }

    if (_movingFriendId != null) {
      _moveFriendFromMap(lat, lng);
      return;
    }

    _addFriendFromMap(lat, lng);
  }

  Future<void> _addFriendFromMap(double lat, double lng) async {
    final template = _nextFriendTemplate();
    if (template == null) {
      return;
    }

    final friend = _FriendLocation(
      id: 'friend_${template.label.toLowerCase()}',
      label: template.label,
      color: template.color,
      lat: lat,
      lng: lng,
    );

    setState(() {
      _friends.add(friend);
      _isAddingFriend = false;
      _categoryComparisons.clear();
      _friendSearchResults.clear();
      _friendSearchController.clear();
      _meetupStatus =
          'Added friend ${friend.label}. Adjust filters or tap `Find Fairest Spot`.';
    });

    _mapBridge.setClickToPlace(false);
    _syncFriendMarkers();
    await _resolveFriendAddress(friend);
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleAddFriendMode() {
    if (_friends.length >= _friendTemplates.length) {
      return;
    }

    final next = !_isAddingFriend;
    setState(() {
      _isAddingFriend = next;
      _movingFriendId = null;
      if (next) {
        _friendSearchResults.clear();
      }
      _meetupStatus = next
          ? 'Click anywhere on the map to place friend ${_nextFriendTemplate()?.label ?? ''}.'
          : 'Friend placement canceled.';
    });
    _mapBridge.setClickToPlace(next);
  }

  void _startMoveFriend(_FriendLocation friend) {
    setState(() {
      _isAddingFriend = false;
      _movingFriendId = friend.id;
      _friendSearchResults.clear();
      _meetupStatus =
          'Click anywhere on the map to move friend ${friend.label}.';
    });
    _mapBridge.setClickToPlace(true);
  }

  Future<void> _moveFriendFromMap(double lat, double lng) async {
    final friend = _friendById(_movingFriendId ?? '');
    if (friend == null) {
      return;
    }

    setState(() {
      friend.lat = lat;
      friend.lng = lng;
      friend.address = null;
      _movingFriendId = null;
      _results.clear();
      _centerComparison = null;
      _categoryComparisons.clear();
      _friendSearchResults.clear();
      _friendSearchController.clear();
      _selectedResultIndex = 0;
      _meetupStatus =
          'Moved friend ${friend.label}. Tap `Find Fairest Spot` to rerank venues.';
    });

    _mapBridge.setClickToPlace(false);
    _mapBridge.clearResults();
    _syncFriendMarkers();
    await _resolveFriendAddress(friend);
    if (mounted) {
      setState(() {});
    }
  }

  void _removeFriend(_FriendLocation friend) {
    setState(() {
      _friends.removeWhere((item) => item.id == friend.id);
      _results.clear();
      _categoryComparisons.clear();
      _friendSearchResults.clear();
      if (_movingFriendId == friend.id) {
        _movingFriendId = null;
      }
      _selectedResultIndex = 0;
      _meetupStatus =
          'Removed friend ${friend.label}. Add another friend or search again.';
    });
    _mapBridge.removeFriendPin(friend.id);
    _renderedFriendIds.remove(friend.id);
    _mapBridge.clearResults();
    _syncFriendMarkers();
  }

  Future<void> _searchFriendLocations() async {
    final query = _friendSearchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _friendSearchResults.clear();
        _meetupStatus = 'Type a place name, building, or address to search.';
      });
      return;
    }
    if (!_proxyHealthy || !_proxyHasKey) {
      setState(() {
        _meetupStatus =
            'Start the proxy with a valid key before searching places.';
      });
      return;
    }

    setState(() {
      _isSearchingFriendLocation = true;
      _friendSearchResults.clear();
      _meetupStatus = 'Searching for "$query"...';
    });

    try {
      final anchor = _friends.isEmpty ? null : _friends.first;
      final response = await _api.searchPlaces(
        keyword: query,
        country: anchor == null ? 'SGP' : null,
        lat: anchor?.lat,
        lng: anchor?.lng,
        limit: 6,
      );
      final places = (response['places'] as List?) ?? const [];
      final results = places.whereType<Map>().map((place) {
        final map = Map<String, dynamic>.from(place.cast<String, dynamic>());
        return _LocationSearchCandidate(
          name: (map['name'] ?? 'Unknown place').toString(),
          subtitle: (map['formatted_address'] ??
                  map['address'] ??
                  map['business_type'] ??
                  map['category'])
              ?.toString(),
          lat: _placeLat(map),
          lng: _placeLng(map),
        );
      }).where((place) => place.lat != 0 || place.lng != 0).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _isSearchingFriendLocation = false;
        _friendSearchResults
          ..clear()
          ..addAll(results);
        _meetupStatus = results.isEmpty
            ? 'No matching places found. Try a more specific search.'
            : 'Tap a result to add it as a friend location.';
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearchingFriendLocation = false;
        _meetupStatus = 'Place search failed: ${_describeDioError(error)}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearchingFriendLocation = false;
        _meetupStatus = 'Place search failed: $error';
      });
    }
  }

  Future<void> _selectFriendSearchResult(_LocationSearchCandidate candidate) async {
    if (_movingFriendId != null) {
      await _moveFriendFromMap(candidate.lat, candidate.lng);
      return;
    }

    if (_friends.length >= _friendTemplates.length) {
      setState(() {
        _meetupStatus = 'You already have the maximum of 5 friends.';
      });
      return;
    }

    final template = _nextFriendTemplate();
    if (template == null) {
      return;
    }

    final friend = _FriendLocation(
      id: 'friend_${template.label.toLowerCase()}',
      label: template.label,
      color: template.color,
      lat: candidate.lat,
      lng: candidate.lng,
    )..address = candidate.subtitle ?? candidate.name;

    setState(() {
      _friends.add(friend);
      _isAddingFriend = false;
      _friendSearchResults.clear();
      _friendSearchController.clear();
      _categoryComparisons.clear();
      _meetupStatus =
          'Added friend ${friend.label} from search. Adjust filters or tap `Find Fairest Spot`.';
    });

    _mapBridge.setClickToPlace(false);
    _syncFriendMarkers();
    await _resolveFriendAddress(friend);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _findFairestSpot() async {
    if (_friends.length < 2) {
      setState(() {
        _meetupStatus = 'Add at least 2 friends before calculating fairness.';
      });
      return;
    }
    if (!_proxyHealthy) {
      setState(() {
        _meetupStatus =
            'Proxy is not reachable yet. Start the Shelf server first.';
      });
      return;
    }
    if (!_proxyHasKey) {
      setState(() {
        _meetupStatus =
            'Proxy is running without GRAB_MAPS_API_KEY. Add the key and retry.';
      });
      return;
    }

    final radiusKm = _parsedMaxDistanceKm();
    if (radiusKm == null) {
      if (_maxDistanceController.text.trim().isNotEmpty) {
        setState(() {
          _meetupStatus =
              'Enter a valid maximum distance in km before searching.';
        });
        return;
      }
    }

    setState(() {
      _isRunningSearch = true;
      _searchStage = _searchPhases.first;
      _meetupStatus = radiusKm == null
          ? 'Searching nearby ${_selectedCategory}s with no distance cap and calculating fairness...'
          : 'Searching nearby ${_selectedCategory}s within ${radiusKm.toStringAsFixed(1)} km and calculating fairness...';
    });
    _startSearchStageTicker();

    try {
      final result = await _api.rankMeetup(
        friends: _friends
            .map((friend) => {
                  'id': friend.id,
                  'lat': friend.lat,
                  'lng': friend.lng,
                })
            .toList(),
        keyword: _selectedCategory,
        radiusKm: radiusKm,
        candidateLimit: 8,
        profile: _selectedProfile,
      );

      final parsedResults = _parseMeetingResults(result);
      if (!mounted) {
        return;
      }

      if (parsedResults.isEmpty) {
        setState(() {
          _results..clear();
          _centerComparison = null;
          _isRunningSearch = false;
          _searchStage = _searchPhases.first;
          _meetupStatus =
              'No candidate venues were ranked. Try another category or move the pins.';
        });
        _stopSearchStageTicker();
        _mapBridge.clearResults();
        return;
      }

      _stopSearchStageTicker();
      setState(() {
        _results
          ..clear()
          ..addAll(parsedResults);
        _centerComparison = _parseCenterComparison(result);
        _selectedResultIndex = 0;
        _isRunningSearch = false;
        _searchStage = _searchPhases.last;
      });
      _renderSelectedResult();
    } on DioException catch (error) {
      _stopSearchStageTicker();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRunningSearch = false;
        _centerComparison = null;
        _searchStage = _searchPhases.first;
        _meetupStatus = 'Meetup search failed: ${_describeDioError(error)}';
      });
    } catch (error) {
      _stopSearchStageTicker();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRunningSearch = false;
        _centerComparison = null;
        _searchStage = _searchPhases.first;
        _meetupStatus = 'Meetup search failed: $error';
      });
    }
  }

  Future<void> _compareCategories() async {
    if (_friends.length < 2) {
      setState(() {
        _meetupStatus = 'Add at least 2 friends before comparing categories.';
      });
      return;
    }
    if (!_proxyHealthy || !_proxyHasKey) {
      setState(() {
        _meetupStatus =
            'Start the proxy with a valid key before comparing categories.';
      });
      return;
    }

    final radiusKm = _parsedMaxDistanceKm();
    if (radiusKm == null) {
      if (_maxDistanceController.text.trim().isNotEmpty) {
        setState(() {
          _meetupStatus =
              'Enter a valid maximum distance in km before comparing categories.';
        });
        return;
      }
    }

    setState(() {
      _isComparingCategories = true;
      _meetupStatus = radiusKm == null
          ? 'Comparing the best meetup option across categories with no distance cap...'
          : 'Comparing the best meetup option across categories within ${radiusKm.toStringAsFixed(1)} km...';
    });

    try {
      final responses = await Future.wait(
        _categoryOptions.map((option) async {
          final response = await _api.rankMeetup(
            friends: _friends
                .map((friend) => {
                      'id': friend.id,
                      'lat': friend.lat,
                      'lng': friend.lng,
                    })
                .toList(),
            keyword: option.keyword,
            radiusKm: radiusKm,
            candidateLimit: 6,
            profile: _selectedProfile,
          );
          final results = _parseMeetingResults(response);
          if (results.isEmpty) {
            return null;
          }
          return _CategoryComparisonResult(
            categoryLabel: option.label,
            categoryKeyword: option.keyword,
            winner: results.first,
          );
        }),
      );

      final comparisons = responses.whereType<_CategoryComparisonResult>().toList()
        ..sort(
          (a, b) => a.winner.unfairnessSeconds.compareTo(
            b.winner.unfairnessSeconds,
          ),
        );

      if (!mounted) {
        return;
      }

      setState(() {
        _isComparingCategories = false;
        _categoryComparisons
          ..clear()
          ..addAll(comparisons);
        _meetupStatus = comparisons.isEmpty
            ? 'No category comparison winners were found nearby.'
            : '${comparisons.first.categoryLabel} is currently the fairest vibe for this group.';
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isComparingCategories = false;
        _meetupStatus = 'Category comparison failed: ${_describeDioError(error)}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isComparingCategories = false;
        _meetupStatus = 'Category comparison failed: $error';
      });
    }
  }

  void _startSearchStageTicker() {
    final token = ++_searchTickerToken;
    Future<void>(() async {
      for (final phase in _searchPhases.skip(1)) {
        await Future<void>.delayed(const Duration(milliseconds: 950));
        if (!mounted || token != _searchTickerToken || !_isRunningSearch) {
          return;
        }
        setState(() {
          _searchStage = phase;
        });
      }
    });
  }

  void _stopSearchStageTicker() {
    _searchTickerToken++;
  }

  List<_MeetingResult> _parseMeetingResults(Map<String, dynamic> result) {
    final rawResults = (result['results'] as List?) ?? const [];
    return rawResults.whereType<Map>().map((entry) {
      final map = Map<String, dynamic>.from(entry.cast<String, dynamic>());
      final place = Map<String, dynamic>.from(
        (map['place'] as Map).cast<String, dynamic>(),
      );
      final score = Map<String, dynamic>.from(
        (map['score'] as Map).cast<String, dynamic>(),
      );
      final routes =
          ((map['routes'] as List?) ?? const []).whereType<Map>().map((route) {
        final routeMap =
            Map<String, dynamic>.from(route.cast<String, dynamic>());
        return _ResultRoute(
          friendId: routeMap['friendId'].toString(),
          durationSeconds:
              (routeMap['durationSeconds'] as num?)?.toDouble() ?? 0,
          distanceMeters: (routeMap['distanceMeters'] as num?)?.toDouble() ?? 0,
          geometry: _geometryToString(routeMap['geometry']),
        );
      }).toList();

      return _MeetingResult(
        poiId: (place['poi_id'] ?? place['id'] ?? place['name']).toString(),
        name: (place['name'] ?? 'Unknown place').toString(),
        address: (place['formatted_address'] ?? place['address'])?.toString(),
        businessType: (place['business_type'] ??
                place['category'] ??
                _firstCategoryName(place['categories']))
            ?.toString(),
        lat: _placeLat(place),
        lng: _placeLng(place),
        unfairnessSeconds:
            (score['unfairnessSeconds'] as num?)?.toDouble() ?? 0,
        maxDurationSeconds:
            (score['maxDurationSeconds'] as num?)?.toDouble() ?? 0,
        minDurationSeconds:
            (score['minDurationSeconds'] as num?)?.toDouble() ?? 0,
        avgDurationSeconds:
            (score['averageDurationSeconds'] as num?)?.toDouble() ?? 0,
        centroidDistanceMeters:
            (score['centroidDistanceMeters'] as num?)?.toDouble() ?? 0,
        routes: routes,
      );
    }).toList();
  }

  _CenterComparison? _parseCenterComparison(Map<String, dynamic> result) {
    final raw = result['geographicCenterComparison'];
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
    final location = map['location'];
    final score = map['score'];
    if (location is! Map || score is! Map) {
      return null;
    }

    final locationMap = Map<String, dynamic>.from(location.cast<String, dynamic>());
    final scoreMap = Map<String, dynamic>.from(score.cast<String, dynamic>());
    final winnerDelta = map['winnerDelta'];
    final winnerDeltaMap = winnerDelta is Map
        ? Map<String, dynamic>.from(winnerDelta.cast<String, dynamic>())
        : const <String, dynamic>{};

    return _CenterComparison(
      label: (map['label'] ?? 'Geographic Center').toString(),
      description:
          (map['description'] ?? 'Naive midpoint before venue ranking').toString(),
      lat: (locationMap['lat'] as num?)?.toDouble() ?? 0,
      lng: (locationMap['lng'] as num?)?.toDouble() ?? 0,
      unfairnessSeconds:
          (scoreMap['unfairnessSeconds'] as num?)?.toDouble() ?? 0,
      maxDurationSeconds:
          (scoreMap['maxDurationSeconds'] as num?)?.toDouble() ?? 0,
      avgDurationSeconds:
          (scoreMap['averageDurationSeconds'] as num?)?.toDouble() ?? 0,
      unfairnessSecondsSaved:
          (winnerDeltaMap['unfairnessSecondsSaved'] as num?)?.toDouble() ?? 0,
      maxTripSecondsSaved:
          (winnerDeltaMap['maxTripSecondsSaved'] as num?)?.toDouble() ?? 0,
    );
  }

  void _renderSelectedResult() {
    if (_results.isEmpty) {
      _mapBridge.clearResults();
      return;
    }

    final selected = _results[_selectedResultIndex];
    _mapBridge.clearResults();

    for (var i = 0; i < _results.length && i < 5; i++) {
      final candidate = _results[i];
      final markerId = _mapObjectId('result', candidate.poiId);
      _mapBridge.addResultPin(
        id: markerId,
        lat: candidate.lat,
        lng: candidate.lng,
        color: i == _selectedResultIndex ? '#111827' : '#15803D',
        rank: '${i + 1}',
      );
    }

    _drawRoutesForResult(selected);

    final focusPoints = <({double lat, double lng})>[
      ..._friends.map((friend) => (lat: friend.lat, lng: friend.lng)),
      (lat: selected.lat, lng: selected.lng),
    ];
    _mapBridge.fitBoundsToPoints(focusPoints);

    setState(() {
      final comparison = _centerComparison;
      final comparisonSuffix = comparison == null
          ? ''
          : ' Saves ${_formatMinutes(comparison.unfairnessSecondsSaved)} min of unfairness vs the geographic center.';
      _meetupStatus =
          'Winner: ${selected.name}. Fairness gap ${_formatMinutes(selected.unfairnessSeconds)} min, max trip ${_formatMinutes(selected.maxDurationSeconds)} min.$comparisonSuffix';
    });
  }

  void _drawRoutesForResult(_MeetingResult result) {
    _mapBridge.clearRoutes();
    for (final route in result.routes) {
      final friend = _friendById(route.friendId);
      if (friend == null || route.geometry == null || route.geometry!.isEmpty) {
        continue;
      }
      final coordinates = _decodeGeometry(route.geometry!);
      if (coordinates.isEmpty) continue;
      _mapBridge.drawRoute(
        routeId: _mapObjectId('route_${route.friendId}', result.poiId),
        coordinates: coordinates,
        color: _showRouteLines ? friend.color : 'rgba(0,0,0,0)',
        width: _showRouteLines ? 5 : 0.01,
      );
    }
  }

  // Decodes geometry that is either a polyline6 string or a GeoJSON LineString.
  List<List<double>> _decodeGeometry(String geometry) {
    if (geometry.trimLeft().startsWith('{')) {
      try {
        final geoJson = jsonDecode(geometry) as Map<String, dynamic>;
        final rawCoords = geoJson['coordinates'] as List<dynamic>;
        return rawCoords.map<List<double>>((c) {
          final pair = c as List<dynamic>;
          return [(pair[0] as num).toDouble(), (pair[1] as num).toDouble()];
        }).toList();
      } catch (_) {
        return [];
      }
    }
    return PolylineCodec.decodePolyline6(geometry);
  }

  // Converts a route geometry value (String or GeoJSON Map) to a string.
  // Uses jsonEncode for Maps so the JSON structure is preserved, not Dart's toString().
  static String? _geometryToString(dynamic geometry) {
    if (geometry == null) return null;
    if (geometry is String) return geometry.isEmpty ? null : geometry;
    if (geometry is Map) return jsonEncode(geometry);
    return null;
  }

  String _mapObjectId(String prefix, String rawId) {
    final sanitized = rawId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? prefix : '${prefix}_$sanitized';
  }

  void _focusSelectedResult() {
    if (_results.isEmpty) {
      return;
    }
    final selected = _results[_selectedResultIndex];
    _mapBridge.fitBoundsToPoints([
      ..._friends.map((friend) => (lat: friend.lat, lng: friend.lng)),
      (lat: selected.lat, lng: selected.lng),
    ]);
  }

  void _selectResult(int index) {
    setState(() {
      _selectedResultIndex = index;
    });
    _renderSelectedResult();
  }

  void _applyCategory(String keyword) {
    if (_selectedCategory == keyword) {
      return;
    }
    setState(() {
      _selectedCategory = keyword;
      _results.clear();
      _centerComparison = null;
      _categoryComparisons.clear();
      _selectedResultIndex = 0;
      _meetupStatus =
          'Category set to $keyword. Tap `Find Fairest Spot` to rerank venues.';
    });
    _mapBridge.clearResults();
  }

  void _applyProfile(String value) {
    if (_selectedProfile == value) {
      return;
    }
    setState(() {
      _selectedProfile = value;
      _results.clear();
      _centerComparison = null;
      _categoryComparisons.clear();
      _selectedResultIndex = 0;
      _meetupStatus =
          'Travel mode set to $value. Tap `Find Fairest Spot` to rerank routes.';
    });
    _mapBridge.clearResults();
  }

  double? _parsedMaxDistanceKm() {
    final raw = _maxDistanceController.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  bool _isSlightlyFar(_MeetingResult result) {
    final limitKm = _parsedMaxDistanceKm();
    if (limitKm == null) {
      return false;
    }
    return result.routes.any((route) => (route.distanceMeters / 1000) > limitKm);
  }

  List<_RecommendedFarPlace> _recommendedFarPlacesForCurrentSearch() {
    final limitKm = _parsedMaxDistanceKm();
    if (limitKm == null || _friends.isEmpty) {
      return const [];
    }

    final centroid = (
      lat: _friends.fold<double>(0, (sum, friend) => sum + friend.lat) /
          _friends.length,
      lng: _friends.fold<double>(0, (sum, friend) => sum + friend.lng) /
          _friends.length,
    );

    final filtered = _recommendedFarPlaces.where((place) {
      if (!place.categoryKeywords.contains(_selectedCategory)) {
        return false;
      }
      final distanceKm = _distanceKmBetween(
        centroidLat: centroid.lat,
        centroidLng: centroid.lng,
        targetLat: place.lat,
        targetLng: place.lng,
      );
      return distanceKm > limitKm;
    }).toList()
      ..sort((a, b) {
        final aDistance = _distanceKmBetween(
          centroidLat: centroid.lat,
          centroidLng: centroid.lng,
          targetLat: a.lat,
          targetLng: a.lng,
        );
        final bDistance = _distanceKmBetween(
          centroidLat: centroid.lat,
          centroidLng: centroid.lng,
          targetLat: b.lat,
          targetLng: b.lng,
        );
        return aDistance.compareTo(bDistance);
      });

    return filtered.take(3).toList(growable: false);
  }

  double _distanceKmBetween({
    required double centroidLat,
    required double centroidLng,
    required double targetLat,
    required double targetLng,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(targetLat - centroidLat);
    final dLng = _toRadians(targetLng - centroidLng);
    final lat1 = _toRadians(centroidLat);
    final lat2 = _toRadians(targetLat);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(lat1) *
            math.cos(lat2) *
            (math.sin(dLng / 2) * math.sin(dLng / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * 0.017453292519943295;

  void _focusRecommendedFarPlace(_RecommendedFarPlace place) {
    _mapBridge.fitBoundsToPoints([
      ..._friends.map((friend) => (lat: friend.lat, lng: friend.lng)),
      (lat: place.lat, lng: place.lng),
    ]);
    setState(() {
      _meetupStatus =
          'Recommended but far: ${place.name}. It is outside your current ${_parsedMaxDistanceKm()?.toStringAsFixed(1) ?? '--'} km radius.';
    });
  }

  void _syncFriendMarkers() {
    final activeIds = _friends.map((friend) => friend.id).toSet();
    for (final staleId in _renderedFriendIds.difference(activeIds).toList()) {
      _mapBridge.removeFriendPin(staleId);
      _renderedFriendIds.remove(staleId);
    }

    for (final friend in _friends) {
      _mapBridge.addFriendPin(
        id: friend.id,
        lat: friend.lat,
        lng: friend.lng,
        color: friend.color,
        label: friend.label,
      );
      _renderedFriendIds.add(friend.id);
    }

    if (_friends.isNotEmpty) {
      _mapBridge.fitBoundsToPoints(
        _friends.map((friend) => (lat: friend.lat, lng: friend.lng)).toList(),
      );
    }
  }

  _FriendTemplate? _nextFriendTemplate() {
    final usedLabels = _friends.map((friend) => friend.label).toSet();
    for (final template in _friendTemplates) {
      if (!usedLabels.contains(template.label)) {
        return template;
      }
    }
    return null;
  }

  _FriendLocation? _friendById(String friendId) {
    for (final friend in _friends) {
      if (friend.id == friendId) {
        return friend;
      }
    }
    return null;
  }

  double _placeLat(Map<String, dynamic> place) {
    final location = place['location'];
    if (location is Map && location['latitude'] is num) {
      return (location['latitude'] as num).toDouble();
    }
    return (place['lat'] as num?)?.toDouble() ?? 0;
  }

  double _placeLng(Map<String, dynamic> place) {
    final location = place['location'];
    if (location is Map && location['longitude'] is num) {
      return (location['longitude'] as num).toDouble();
    }
    return (place['lng'] as num?)?.toDouble() ?? 0;
  }

  String _formatMinutes(double? seconds) {
    if (seconds == null) {
      return '-';
    }
    return (seconds / 60).toStringAsFixed(1);
  }

  String _describeDioError(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach ${const String.fromEnvironment(
        'FRIENDSHIP_RADIUS_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080',
      )}';
    }
    if (error.response?.data case final Map data) {
      final message = data['error'];
      if (message != null) {
        return message.toString();
      }
    }
    return error.message ?? error.toString();
  }

  double? _readJsDouble(dynamic object, String property) {
    try {
      final value = object is Map<String, dynamic>
          ? object[property]
          : object is Map
              ? object[property]
              : null;
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value.toString());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedResult = _results.isEmpty
        ? null
        : _results[_selectedResultIndex.clamp(0, _results.length - 1)];
    final recommendedFarPlaces = _recommendedFarPlacesForCurrentSearch();
    final theme = Theme.of(context);
    final fairestPoiId = _results.isEmpty ? null : _results.first.poiId;
    final fastestPoiId = _results.isEmpty
        ? null
        : _results
            .reduce((a, b) => a.avgDurationSeconds <= b.avgDurationSeconds ? a : b)
            .poiId;
    final closestPoiId = _results.isEmpty
        ? null
        : _results
            .reduce(
              (a, b) => a.centroidDistanceMeters <= b.centroidDistanceMeters ? a : b,
            )
            .poiId;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            constraints: const BoxConstraints(maxWidth: 430),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF8FFF9), Color(0xFFF3F8FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.82),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.18),
                  blurRadius: 38,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF14532D),
                          Color(0xFF166534),
                          Color(0xFF115E59),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'CITY FAIRNESS LAB',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Friendship Radius',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.02,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A left-rail meetup studio with the map acting as the live stage.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFFD1FAE5),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusBadge(
                          label: 'Map', value: _mapStatus, ok: _mapLoaded),
                      _StatusBadge(
                        label: 'Proxy',
                        value: _proxyStatus,
                        ok: _proxyHealthy && _proxyHasKey,
                      ),
                      _StatusBadge(
                        label: 'Meetup',
                        value: _meetupStatus,
                        ok: _results.isNotEmpty,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: 'Friends',
                    subtitle:
                        'Use the seeded friends or add more by clicking the map. Minimum 2, maximum 5.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _friendSearchController,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => _searchFriendLocations(),
                                decoration: InputDecoration(
                                  hintText: _movingFriendId != null
                                      ? 'Search a new place for friend ${_friendById(_movingFriendId!)?.label ?? ''}'
                                      : 'Search a friend location by place or address',
                                  prefixIcon: const Icon(Icons.search),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: _isSearchingFriendLocation
                                  ? null
                                  : _searchFriendLocations,
                              child: _isSearchingFriendLocation
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Search'),
                            ),
                          ],
                        ),
                        if (_friendSearchResults.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              for (final place in _friendSearchResults.take(4)) ...[
                                _FriendSearchResultTile(
                                  candidate: place,
                                  onTap: () => _selectFriendSearchResult(place),
                                ),
                                if (place != _friendSearchResults.take(4).last)
                                  const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final friend in _friends)
                        _FriendChip(
                          friend: friend,
                          moving: _movingFriendId == friend.id,
                          onMove: () => _startMoveFriend(friend),
                          onRemove: () => _removeFriend(friend),
                        ),
                      if (_friends.length < _friendTemplates.length)
                        OutlinedButton.icon(
                          onPressed: _mapLoaded ? _toggleAddFriendMode : null,
                          icon: Icon(_isAddingFriend ? Icons.close : Icons.add),
                          label: Text(
                            _isAddingFriend ? 'Cancel Add' : 'Add Friend',
                          ),
                        ),
                    ],
                  ),
                  if (_isAddingFriend || _movingFriendId != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _movingFriendId != null
                          ? 'Click on the map to move friend ${_friendById(_movingFriendId!)?.label ?? ''}.'
                          : 'Click on the map to place friend ${_nextFriendTemplate()?.label ?? ''}.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF166534),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: 'Filters',
                    subtitle:
                        'Pick a vibe, choose a travel mode, and set the maximum distance before ranking venues.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Venue type',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final option in _categoryOptions)
                                ChoiceChip(
                                  label: Text(option.label),
                                  selected: _selectedCategory == option.keyword,
                                  onSelected: (_) =>
                                      _applyCategory(option.keyword),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Travel mode',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final option in _profileOptions)
                                ChoiceChip(
                                  label: Text(option.label),
                                  selected: _selectedProfile == option.value,
                                  onSelected: (_) =>
                                      _applyProfile(option.value),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Maximum distance (km)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _maxDistanceController,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) {
                                  setState(() {
                                    _results.clear();
                                    _centerComparison = null;
                                    _categoryComparisons.clear();
                                    _selectedResultIndex = 0;
                                  });
                                  _mapBridge.clearResults();
                                },
                                decoration: InputDecoration(
                                  hintText: 'e.g. 3 or 4',
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  isDense: true,
                                  suffixText: 'km',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFBBF7D0),
                                ),
                              ),
                              child: Text(
                                _parsedMaxDistanceKm() == null
                                    ? 'Optional'
                                    : '${_parsedMaxDistanceKm()!.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isRunningSearch ? null : _findFairestSpot,
                      icon: _isRunningSearch
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.route),
                      label: Text(
                        _isRunningSearch
                            ? 'Calculating fairness...'
                            : 'Find Fairest Spot',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isComparingCategories || _isRunningSearch
                          ? null
                          : _compareCategories,
                      icon: _isComparingCategories
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.tune),
                      label: Text(
                        _isComparingCategories
                            ? 'Comparing Categories...'
                            : 'Compare Categories',
                      ),
                    ),
                  ),
                  if (_isRunningSearch) ...[
                    const SizedBox(height: 16),
                    _SearchProgressCard(
                      activeStage: _searchStage,
                      stages: _searchPhases,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (selectedResult != null) ...[
                    _WinnerSpotlight(
                      result: selectedResult,
                      rank: _selectedResultIndex + 1,
                      isTopPick: _selectedResultIndex == 0,
                      friends: _friends,
                      slightlyFar: _isSlightlyFar(selectedResult),
                      onFocus: _focusSelectedResult,
                      formatMinutes: _formatMinutes,
                    ),
                    if (_centerComparison != null) ...[
                      const SizedBox(height: 14),
                      _CenterComparisonCard(
                        comparison: _centerComparison!,
                        winner: selectedResult,
                        formatMinutes: _formatMinutes,
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                  if (_categoryComparisons.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Best Vibe Match',
                      subtitle:
                          'Compare the fairest winner across categories for this exact group.',
                    ),
                    const SizedBox(height: 12),
                    _CategoryComparisonCard(
                      comparisons: _categoryComparisons,
                      formatMinutes: _formatMinutes,
                      onSelect: (comparison) {
                        _applyCategory(comparison.categoryKeyword);
                        setState(() {
                          _results
                            ..clear()
                            ..add(comparison.winner);
                          _selectedResultIndex = 0;
                        });
                        _renderSelectedResult();
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                  _SectionHeader(
                    title: 'Fairest Meeting Points',
                    subtitle: _results.isEmpty
                        ? 'Run a search to rank the fairest venues.'
                        : 'Badges show which option is fairest, fastest, or closest to the group.',
                  ),
                  const SizedBox(height: 12),
                  if (_results.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Text(
                        'No ranked venues yet. Choose your category, then tap `Find Fairest Spot`.',
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (var i = 0; i < _results.length && i < 5; i++) ...[
                          _ResultCard(
                            result: _results[i],
                            rank: i + 1,
                            selected: i == _selectedResultIndex,
                            friends: _friends,
                            isFairest: _results[i].poiId == fairestPoiId,
                            isFastest: _results[i].poiId == fastestPoiId,
                            isClosest: _results[i].poiId == closestPoiId,
                            slightlyFar: _isSlightlyFar(_results[i]),
                            onTap: () => _selectResult(i),
                            formatMinutes: _formatMinutes,
                          ),
                          if (i < _results.length - 1 && i < 4)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  if (recommendedFarPlaces.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionHeader(
                      title: 'Recommended But Far',
                      subtitle:
                          'Well-known places outside your current distance radius, shown as optional stretch picks.',
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        for (final place in recommendedFarPlaces) ...[
                          _RecommendedFarPlaceCard(
                            place: place,
                            radiusKm: _parsedMaxDistanceKm()!,
                            distanceKm: _distanceKmBetween(
                              centroidLat: _friends.fold<double>(
                                    0,
                                    (sum, friend) => sum + friend.lat,
                                  ) /
                                  _friends.length,
                              centroidLng: _friends.fold<double>(
                                    0,
                                    (sum, friend) => sum + friend.lng,
                                  ) /
                                  _friends.length,
                              targetLat: place.lat,
                              targetLng: place.lng,
                            ),
                            onTap: () => _focusRecommendedFarPlace(place),
                          ),
                          if (place != recommendedFarPlaces.last)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendTemplate {
  const _FriendTemplate({
    required this.label,
    required this.color,
  });

  final String label;
  final String color;
}

class _FriendLocation {
  _FriendLocation({
    required this.id,
    required this.label,
    required this.color,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String label;
  final String color;
  double lat;
  double lng;
  String? address;
}

class _CategoryOption {
  const _CategoryOption({
    required this.label,
    required this.keyword,
  });

  final String label;
  final String keyword;
}

class _ProfileOption {
  const _ProfileOption({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _MeetingResult {
  const _MeetingResult({
    required this.poiId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.unfairnessSeconds,
    required this.maxDurationSeconds,
    required this.minDurationSeconds,
    required this.avgDurationSeconds,
    required this.centroidDistanceMeters,
    required this.routes,
    this.address,
    this.businessType,
  });

  final String poiId;
  final String name;
  final String? address;
  final String? businessType;
  final double lat;
  final double lng;
  final double unfairnessSeconds;
  final double maxDurationSeconds;
  final double minDurationSeconds;
  final double avgDurationSeconds;
  final double centroidDistanceMeters;
  final List<_ResultRoute> routes;
}

class _CenterComparison {
  const _CenterComparison({
    required this.label,
    required this.description,
    required this.lat,
    required this.lng,
    required this.unfairnessSeconds,
    required this.maxDurationSeconds,
    required this.avgDurationSeconds,
    required this.unfairnessSecondsSaved,
    required this.maxTripSecondsSaved,
  });

  final String label;
  final String description;
  final double lat;
  final double lng;
  final double unfairnessSeconds;
  final double maxDurationSeconds;
  final double avgDurationSeconds;
  final double unfairnessSecondsSaved;
  final double maxTripSecondsSaved;
}

class _CategoryComparisonResult {
  const _CategoryComparisonResult({
    required this.categoryLabel,
    required this.categoryKeyword,
    required this.winner,
  });

  final String categoryLabel;
  final String categoryKeyword;
  final _MeetingResult winner;
}

class _LocationSearchCandidate {
  const _LocationSearchCandidate({
    required this.name,
    required this.lat,
    required this.lng,
    this.subtitle,
  });

  final String name;
  final String? subtitle;
  final double lat;
  final double lng;
}

class _ResultRoute {
  const _ResultRoute({
    required this.friendId,
    required this.durationSeconds,
    required this.distanceMeters,
    this.geometry,
  });

  final String friendId;
  final double durationSeconds;
  final double distanceMeters;
  final String? geometry;
}

class _RecommendedFarPlace {
  const _RecommendedFarPlace({
    required this.name,
    required this.subtitle,
    required this.lat,
    required this.lng,
    required this.categoryKeywords,
  });

  final String name;
  final String subtitle;
  final double lat;
  final double lng;
  final List<String> categoryKeywords;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF166534) : const Color(0xFF92400E);
    final bg = ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    return Container(
      constraints: const BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(value),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
          ),
        ),
      ],
    );
  }
}

class _SearchProgressCard extends StatelessWidget {
  const _SearchProgressCard({
    required this.activeStage,
    required this.stages,
  });

  final String activeStage;
  final List<String> stages;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECFCCB), Color(0xFFD9F99D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFA3E635)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF3F6212),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Building the fairest meetup',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF365314),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeStage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4D7C0F),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              for (final stage in stages) ...[
                _SearchStageRow(
                  label: stage,
                  state: stage == activeStage
                      ? _SearchStageState.active
                      : stages.indexOf(stage) < stages.indexOf(activeStage)
                          ? _SearchStageState.complete
                          : _SearchStageState.pending,
                ),
                if (stage != stages.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum _SearchStageState { pending, active, complete }

class _SearchStageRow extends StatelessWidget {
  const _SearchStageRow({
    required this.label,
    required this.state,
  });

  final String label;
  final _SearchStageState state;

  @override
  Widget build(BuildContext context) {
    final isActive = state == _SearchStageState.active;
    final isComplete = state == _SearchStageState.complete;
    final bg = isComplete
        ? const Color(0xFFDCFCE7)
        : isActive
            ? Colors.white
            : Colors.white.withValues(alpha: 0.55);
    final color = isComplete
        ? const Color(0xFF166534)
        : isActive
            ? const Color(0xFF3F6212)
            : const Color(0xFF6B7280);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isComplete
                  ? const Color(0xFF16A34A)
                  : isActive
                      ? const Color(0xFF65A30D)
                      : const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Icon(
              isComplete
                  ? Icons.check
                  : isActive
                      ? Icons.timelapse
                      : Icons.more_horiz,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: isActive || isComplete
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendSearchResultTile extends StatelessWidget {
  const _FriendSearchResultTile({
    required this.candidate,
    required this.onTap,
  });

  final _LocationSearchCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.place_rounded,
                color: Color(0xFF166534),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (candidate.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      candidate.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, size: 15),
          ],
        ),
      ),
    );
  }
}

class _FriendChip extends StatelessWidget {
  const _FriendChip({
    required this.friend,
    required this.moving,
    required this.onMove,
    required this.onRemove,
  });

  final _FriendLocation friend;
  final bool moving;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: moving ? const Color(0xFFECFCCB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: moving ? const Color(0xFF65A30D) : const Color(0xFFE5E7EB),
          width: moving ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Color(_hexToColor(friend.color)),
            child: Text(
              friend.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Friend ${friend.label}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  friend.address ??
                      '${friend.lat.toStringAsFixed(4)}, ${friend.lng.toStringAsFixed(4)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onMove,
            icon: const Icon(Icons.open_with),
            tooltip: 'Move friend',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Remove friend',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.rank,
    required this.selected,
    required this.friends,
    required this.isFairest,
    required this.isFastest,
    required this.isClosest,
    required this.slightlyFar,
    required this.onTap,
    required this.formatMinutes,
  });

  final _MeetingResult result;
  final int rank;
  final bool selected;
  final List<_FriendLocation> friends;
  final bool isFairest;
  final bool isFastest;
  final bool isClosest;
  final bool slightlyFar;
  final VoidCallback onTap;
  final String Function(double?) formatMinutes;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? const Color(0xFF166534) : const Color(0xFFE5E7EB);
    final bg = selected ? const Color(0xFFF0FDF4) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF166534)
                        : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isFairest)
                            const _ResultBadge(
                              label: 'Fairest',
                              background: Color(0xFFDCFCE7),
                              foreground: Color(0xFF166534),
                            ),
                          if (isFastest)
                            const _ResultBadge(
                              label: 'Fastest',
                              background: Color(0xFFDBEAFE),
                              foreground: Color(0xFF1D4ED8),
                            ),
                          if (isClosest)
                            const _ResultBadge(
                              label: 'Closest',
                              background: Color(0xFFFEF3C7),
                              foreground: Color(0xFFB45309),
                            ),
                          if (slightlyFar)
                            const _ResultBadge(
                              label: 'Slightly Far',
                              background: Color(0xFFFFEDD5),
                              foreground: Color(0xFF9A3412),
                            ),
                        ],
                      ),
                      if (isFairest || isFastest || isClosest || slightlyFar)
                        const SizedBox(height: 8),
                      Text(
                        result.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      if (result.address != null || result.businessType != null)
                        Text(
                          [
                            if (result.businessType != null)
                              result.businessType!,
                            if (result.address != null) result.address!,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${formatMinutes(result.maxDurationSeconds)} min max',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Spread ${formatMinutes(result.unfairnessSeconds)} min',
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final friend in friends) ...[
              _RouteSummaryRow(
                friend: friend,
                route: result.routes
                    .where((route) => route.friendId == friend.id)
                    .firstOrNull,
                formatMinutes: formatMinutes,
              ),
              if (friend != friends.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _WinnerSpotlight extends StatelessWidget {
  const _WinnerSpotlight({
    required this.result,
    required this.rank,
    required this.isTopPick,
    required this.friends,
    required this.slightlyFar,
    required this.onFocus,
    required this.formatMinutes,
  });

  final _MeetingResult result;
  final int rank;
  final bool isTopPick;
  final List<_FriendLocation> friends;
  final bool slightlyFar;
  final VoidCallback onFocus;
  final String Function(double?) formatMinutes;

  @override
  Widget build(BuildContext context) {
    final topCopy = isTopPick
        ? 'This is the fairest compromise for the whole group.'
        : 'Previewing an alternative meeting point for comparison.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isTopPick ? 'Top Pick' : 'Alternative #$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (result.businessType != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    result.businessType!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    ),
                  ),
              if (slightlyFar)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE68A).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFDE68A).withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text(
                    'Slightly Far',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            result.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          if (result.address != null) ...[
            const SizedBox(height: 6),
            Text(
              result.address!,
              style: const TextStyle(
                color: Color(0xFFD1FAE5),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            topCopy,
            style: const TextStyle(
              color: Color(0xFFECFDF5),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onFocus,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Focus On Map'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SpotlightMetric(
                label: 'Fairness Gap',
                value: '${formatMinutes(result.unfairnessSeconds)} min',
              ),
              _SpotlightMetric(
                label: 'Max Trip',
                value: '${formatMinutes(result.maxDurationSeconds)} min',
              ),
              _SpotlightMetric(
                label: 'Average Trip',
                value: '${formatMinutes(result.avgDurationSeconds)} min',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              for (final friend in friends) ...[
                _SpotlightRouteRow(
                  friend: friend,
                  route: result.routes
                      .where((route) => route.friendId == friend.id)
                      .firstOrNull,
                  formatMinutes: formatMinutes,
                ),
                if (friend != friends.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightMetric extends StatelessWidget {
  const _SpotlightMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD1FAE5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightRouteRow extends StatelessWidget {
  const _SpotlightRouteRow({
    required this.friend,
    required this.route,
    required this.formatMinutes,
  });

  final _FriendLocation friend;
  final _ResultRoute? route;
  final String Function(double?) formatMinutes;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Color(_hexToColor(friend.color)),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            friend.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Friend ${friend.label}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: ((route?.durationSeconds ?? 0) / 2400).clamp(0.04, 1.0),
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
                color: Color(_hexToColor(friend.color)),
                backgroundColor: Colors.white.withValues(alpha: 0.18),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: Text(
            '${formatMinutes(route?.durationSeconds)} min\n'
            '${((route?.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _CenterComparisonCard extends StatelessWidget {
  const _CenterComparisonCard({
    required this.comparison,
    required this.winner,
    required this.formatMinutes,
  });

  final _CenterComparison comparison;
  final _MeetingResult winner;
  final String Function(double?) formatMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.compare_arrows, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why the winner beats the midpoint',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF92400E),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      comparison.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF78350F),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ComparisonMetric(
                label: 'Winner Spread',
                value: '${formatMinutes(winner.unfairnessSeconds)} min',
                positive: true,
              ),
              _ComparisonMetric(
                label: 'Midpoint Spread',
                value: '${formatMinutes(comparison.unfairnessSeconds)} min',
              ),
              _ComparisonMetric(
                label: 'Spread Saved',
                value: '${formatMinutes(comparison.unfairnessSecondsSaved)} min',
                positive: comparison.unfairnessSecondsSaved >= 0,
              ),
              _ComparisonMetric(
                label: 'Max Trip Saved',
                value: '${formatMinutes(comparison.maxTripSecondsSaved)} min',
                positive: comparison.maxTripSecondsSaved >= 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${winner.name} is fairer than the naive geographic center by reducing the travel-time spread across friends.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF78350F),
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonMetric extends StatelessWidget {
  const _ComparisonMetric({
    required this.label,
    required this.value,
    this.positive = false,
  });

  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final bg = positive ? const Color(0xFFECFDF5) : Colors.white;
    final color = positive ? const Color(0xFF166534) : const Color(0xFF92400E);
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: positive ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSummaryRow extends StatelessWidget {
  const _RouteSummaryRow({
    required this.friend,
    required this.route,
    required this.formatMinutes,
  });

  final _FriendLocation friend;
  final _ResultRoute? route;
  final String Function(double?) formatMinutes;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Color(_hexToColor(friend.color)),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            friend.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LinearProgressIndicator(
            value: ((route?.durationSeconds ?? 0) / 2400).clamp(0.04, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            color: Color(_hexToColor(friend.color)),
            backgroundColor: const Color(0xFFE5E7EB),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: Text(
            '${formatMinutes(route?.durationSeconds)} min · '
            '${((route?.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _CategoryComparisonCard extends StatelessWidget {
  const _CategoryComparisonCard({
    required this.comparisons,
    required this.formatMinutes,
    required this.onSelect,
  });

  final List<_CategoryComparisonResult> comparisons;
  final String Function(double?) formatMinutes;
  final void Function(_CategoryComparisonResult comparison) onSelect;

  @override
  Widget build(BuildContext context) {
    final best = comparisons.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Best overall vibe right now: ${best.categoryLabel}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${best.winner.name} wins with a ${formatMinutes(best.winner.unfairnessSeconds)} min fairness gap.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                ),
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              for (final comparison in comparisons.take(5)) ...[
                InkWell(
                  onTap: () => onSelect(comparison),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: comparison == best
                          ? const Color(0xFFECFCCB)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: comparison == best
                            ? const Color(0xFF84CC16)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: comparison == best
                                ? const Color(0xFF65A30D)
                                : const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${comparisons.indexOf(comparison) + 1}',
                            style: TextStyle(
                              color: comparison == best
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comparison.categoryLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                comparison.winner.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${formatMinutes(comparison.winner.unfairnessSeconds)} min spread',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${formatMinutes(comparison.winner.maxDurationSeconds)} min max',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (comparison != comparisons.take(5).last)
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendedFarPlaceCard extends StatelessWidget {
  const _RecommendedFarPlaceCard({
    required this.place,
    required this.radiusKm,
    required this.distanceKm,
    required this.onTap,
  });

  final _RecommendedFarPlace place;
  final double radiusKm;
  final double distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF59E0B)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.star_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ResultBadge(
                    label: 'Recommended But Far',
                    background: Color(0xFFFFEDD5),
                    foreground: Color(0xFF9A3412),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    place.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    place.subtitle,
                    style: const TextStyle(color: Color(0xFF78716C)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${distanceKm.toStringAsFixed(1)} km from the group centroid, beyond your ${radiusKm.toStringAsFixed(1)} km radius',
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.center_focus_strong, color: Color(0xFF92400E)),
          ],
        ),
      ),
    );
  }
}

String? _firstCategoryName(dynamic categories) {
  if (categories is! List || categories.isEmpty) {
    return null;
  }
  final first = categories.first;
  if (first is! Map) {
    return null;
  }
  return first['category_name']?.toString();
}

int _hexToColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return int.parse('FF$cleaned', radix: 16);
}

extension _IterableFirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
