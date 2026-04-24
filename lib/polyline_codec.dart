class PolylineCodec {
  static List<List<double>> decodePolyline6(String encoded) {
    return _decode(encoded, precision: 6);
  }

  static List<List<double>> _decode(String encoded, {required int precision}) {
    final coordinates = <List<double>>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    final factor = _pow10(precision);

    while (index < encoded.length) {
      final latDelta = _decodeValue(encoded, index);
      index = _nextIndex(encoded, index);
      final lngDelta = _decodeValue(encoded, index);
      index = _nextIndex(encoded, index);
      lat += latDelta;
      lng += lngDelta;
      coordinates.add([lng / factor, lat / factor]);
    }

    return coordinates;
  }

  static int _decodeValue(String encoded, int startIndex) {
    var index = startIndex;
    var result = 0;
    var shift = 0;
    int value = 0;

    do {
      value = encoded.codeUnitAt(index++) - 63;
      result |= (value & 0x1f) << shift;
      shift += 5;
    } while (value >= 0x20);

    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  static int _nextIndex(String encoded, int startIndex) {
    var index = startIndex;
    int value;
    do {
      value = encoded.codeUnitAt(index++) - 63;
    } while (value >= 0x20);
    return index;
  }

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
