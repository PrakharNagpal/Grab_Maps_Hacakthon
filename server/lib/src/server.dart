import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'grab_maps_client.dart';
import 'meetup_service.dart';

Future<HttpServer> serve({
  String host = '0.0.0.0',
  int port = 8080,
  String? apiKey,
}) async {
  final resolvedKey = apiKey ?? Platform.environment['GRAB_MAPS_API_KEY'] ?? '';
  final client = GrabMapsClient(apiKey: resolvedKey);
  final meetupService = MeetupService(client);

  final router = Router()
    ..get('/', (Request request) {
      return _json(
        {
          'name': 'Friendship Radius API',
          'ok': true,
          'endpoints': [
            '/health',
            '/api/reverse-geocode',
            '/api/places/nearby',
            '/api/places/search',
            '/api/routes/direction',
            '/api/meetup/rank',
          ],
        },
      );
    })
    ..get('/health', (Request request) {
      return _json({
        'ok': true,
        'hasApiKey': resolvedKey.isNotEmpty,
      });
    })
    ..post('/api/reverse-geocode', (Request request) async {
      final payload = await _readJson(request);
      final response = await client.reverseGeocode(
        lat: _requiredDouble(payload, 'lat'),
        lng: _requiredDouble(payload, 'lng'),
        type: _optionalString(payload, 'type'),
      );
      return _json(response);
    })
    ..post('/api/places/nearby', (Request request) async {
      final payload = await _readJson(request);
      final response = await client.nearbyPlaces(
        lat: _requiredDouble(payload, 'lat'),
        lng: _requiredDouble(payload, 'lng'),
        radiusKm: _optionalDouble(payload, 'radiusKm') ?? 1,
        limit: _optionalInt(payload, 'limit') ?? 10,
        rankBy: _optionalString(payload, 'rankBy') ?? 'distance',
        language: _optionalString(payload, 'language'),
      );
      return _json(response);
    })
    ..post('/api/places/search', (Request request) async {
      final payload = await _readJson(request);
      final response = await client.searchPlaces(
        keyword: _requiredString(payload, 'keyword'),
        country: _optionalString(payload, 'country'),
        lat: _optionalDouble(payload, 'lat'),
        lng: _optionalDouble(payload, 'lng'),
        limit: _optionalInt(payload, 'limit') ?? 10,
      );
      return _json(response);
    })
    ..post('/api/routes/direction', (Request request) async {
      final payload = await _readJson(request);
      final rawPoints = payload['points'];
      if (rawPoints is! List || rawPoints.length < 2) {
        throw const FormatException('`points` must contain at least two items.');
      }

      final points = rawPoints.map((point) {
        if (point is! Map) {
          throw const FormatException('Each point must be an object.');
        }
        final map = Map<String, dynamic>.from(point.cast<String, dynamic>());
        return (
          lat: _requiredDouble(map, 'lat'),
          lng: _requiredDouble(map, 'lng'),
        );
      }).toList(growable: false);

      final response = await client.getDirections(
        points: points,
        profile: _optionalString(payload, 'profile') ?? 'driving',
        overview: _optionalString(payload, 'overview') ?? 'full',
        alternatives: _optionalInt(payload, 'alternatives'),
        avoid: _optionalStringList(payload, 'avoid'),
      );
      return _json(response);
    })
    ..post('/api/meetup/rank', (Request request) async {
      final payload = await _readJson(request);
      final friends = payload['friends'];
      if (friends is! List || friends.isEmpty) {
        throw const FormatException('`friends` must be a non-empty list.');
      }

      final response = await meetupService.rankMeetup(
        friends: friends
            .whereType<Map>()
            .map((friend) => Map<String, dynamic>.from(friend.cast<String, dynamic>()))
            .toList(growable: false),
        keyword: _optionalString(payload, 'keyword'),
        country: _optionalString(payload, 'country'),
        radiusKm: _optionalDouble(payload, 'radiusKm'),
        candidateLimit: _optionalInt(payload, 'candidateLimit') ?? 8,
        profile: _optionalString(payload, 'profile') ?? 'driving',
        rankBy: _optionalString(payload, 'rankBy') ?? 'distance',
        language: _optionalString(payload, 'language'),
      );
      return _json(response);
    })
    ..options('/<ignored|.*>', (Request request) => _cors(Response.ok('')));

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsHeaders())
      .addMiddleware(_errorHandler())
      .addHandler(router.call);

  return shelf_io.serve(handler, host, port);
}

Middleware _corsHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      return _cors(response);
    };
  };
}

Response _cors(Response response) {
  return response.change(headers: {
    ...response.headers,
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'Origin, Content-Type, Authorization',
  });
}

Middleware _errorHandler() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } on GrabMapsException catch (error) {
        return _json(
          {
            'ok': false,
            'error': error.message,
            'details': error.body,
          },
          statusCode: error.statusCode,
        );
      } on FormatException catch (error) {
        return _json(
          {
            'ok': false,
            'error': error.message,
          },
          statusCode: 400,
        );
      } on ArgumentError catch (error) {
        return _json(
          {
            'ok': false,
            'error': error.message,
          },
          statusCode: 400,
        );
      } catch (error, stackTrace) {
        stderr.writeln(error);
        stderr.writeln(stackTrace);
        return _json(
          {
            'ok': false,
            'error': 'Internal server error',
          },
          statusCode: 500,
        );
      }
    };
  };
}

Future<Map<String, dynamic>> _readJson(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Request body must be a JSON object.');
  }
  return decoded;
}

Response _json(Map<String, dynamic> body, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

String _requiredString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('`$key` is required.');
}

String? _optionalString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('`$key` must be a string.');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _requiredDouble(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('`$key` is required and must be a number.');
}

double? _optionalDouble(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('`$key` must be a number.');
}

int? _optionalInt(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('`$key` must be an integer.');
}

List<String>? _optionalStringList(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw FormatException('`$key` must be a list of strings.');
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
