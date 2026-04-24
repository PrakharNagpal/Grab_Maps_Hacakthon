import 'dart:convert';
import 'dart:js_interop';

// JS function bindings
@JS('initGrabMap')
external JSBoolean? jsInitGrabMap(JSString apiKey);

@JS('flyToLocation')
external void jsFlyTo(JSNumber lng, JSNumber lat, JSNumber zoom);

@JS('addMarker')
external void jsAddMarker(
  JSString id, JSNumber lat, JSNumber lng,
  JSString color, JSString label,
);

@JS('removeMarker')
external void jsRemoveMarker(JSString id);

@JS('addResultMarker')
external void jsAddResultMarker(
  JSString id, JSNumber lat, JSNumber lng,
  JSString color, JSString rank,
);

// Passes coordinates as a JSON string to avoid dart:js_interop array interop issues.
@JS('drawRouteLineJson')
external void jsDrawRouteLineJson(
  JSString routeId, JSString coordsJson,
  JSString color, JSNumber width,
);

@JS('clearRoutes')
external void jsClearRoutes();

@JS('clearResults')
external void jsClearResults();

@JS('fitBounds')
external void jsFitBounds(JSArray<JSObject> points);

@JS('setClickToPlace')
external void jsSetClickToPlace(JSBoolean enabled);

@JS('setupClickListener')
external void jsSetupClickListener();

@JS('getGrabMapError')
external JSString? jsGetGrabMapError();

/// Dart-friendly wrapper around JS map functions
class MapBridge {
  bool _initialized = false;

  bool init(String apiKey) {
    final result = jsInitGrabMap(apiKey.toJS);
    _initialized = result?.toDart ?? false;

    if (_initialized) {
      Future.delayed(const Duration(seconds: 2), () {
        jsSetupClickListener();
      });
    }

    return _initialized;
  }

  String get lastError => jsGetGrabMapError()?.toDart ?? '';

  void flyTo(double lat, double lng, {double zoom = 13}) {
    if (!_initialized) return;
    jsFlyTo(lng.toJS, lat.toJS, zoom.toJS);
  }

  void addFriendPin({
    required String id,
    required double lat,
    required double lng,
    required String color,
    required String label,
  }) {
    if (!_initialized) return;
    jsAddMarker(id.toJS, lat.toJS, lng.toJS, color.toJS, label.toJS);
  }

  void removeFriendPin(String id) {
    if (!_initialized) return;
    jsRemoveMarker(id.toJS);
  }

  void addResultPin({
    required String id,
    required double lat,
    required double lng,
    required String color,
    required String rank,
  }) {
    if (!_initialized) return;
    jsAddResultMarker(id.toJS, lat.toJS, lng.toJS, color.toJS, rank.toJS);
  }

  void drawRoute({
    required String routeId,
    required List<List<double>> coordinates, // [[lng, lat], ...]
    required String color,
    double width = 4,
  }) {
    if (!_initialized) return;
    // Serialize as JSON string to avoid dart:js_interop nested-array interop issues.
    final coordsJson = jsonEncode(coordinates);
    jsDrawRouteLineJson(routeId.toJS, coordsJson.toJS, color.toJS, width.toJS);
  }

  void clearRoutes() {
    if (!_initialized) return;
    jsClearRoutes();
  }

  void clearResults() {
    if (!_initialized) return;
    jsClearResults();
  }

  void setClickToPlace(bool enabled) {
    if (!_initialized) return;
    jsSetClickToPlace(enabled.toJS);
  }

  void fitBoundsToPoints(List<({double lat, double lng})> points) {
    if (!_initialized) return;
    if (points.isEmpty) return;
    double avgLat = 0, avgLng = 0;
    for (final p in points) {
      avgLat += p.lat;
      avgLng += p.lng;
    }
    avgLat /= points.length;
    avgLng /= points.length;
    flyTo(avgLat, avgLng, zoom: 12);
  }
}
