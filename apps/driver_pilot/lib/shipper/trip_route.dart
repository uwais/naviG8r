// Where a trip runs, for Book's pickup and drop: its two town pins, the area a place search prefers, and
// the straight-line distance between two points.
import "dart:math";

import "package:google_maps_flutter/google_maps_flutter.dart";

typedef TripEnds = ({LatLng start, LatLng end});

/// The trip's start and end town pins, or null when it has no pin for either.
TripEnds? tripEnds(Map<String, dynamic> trip) {
  final start = _pointOf(trip["origin"]);
  final end = _pointOf(trip["destination"]);
  return start == null || end == null ? null : (start: start, end: end);
}

LatLng? _pointOf(Object? place) {
  if (place is! Map) return null;
  final lat = place["lat"];
  final lng = place["lng"];
  return lat is num && lng is num ? LatLng(lat.toDouble(), lng.toDouble()) : null;
}

/// The rectangle around both town pins with half a degree (about 55 km) to spare on each side.
LatLngBounds areaAround(TripEnds ends) {
  const spareDegrees = 0.5;
  final (start, end) = (ends.start, ends.end);
  return LatLngBounds(
    southwest: LatLng(min(start.latitude, end.latitude) - spareDegrees,
        min(start.longitude, end.longitude) - spareDegrees),
    northeast: LatLng(max(start.latitude, end.latitude) + spareDegrees,
        max(start.longitude, end.longitude) + spareDegrees),
  );
}

/// The straight-line distance over the earth, in km: the same haversine formula as the server's
/// distanceBetweenGeoPointsKm, so both measure a pin alike.
double kmBetween(LatLng from, LatLng to) {
  double radians(double degrees) => degrees * pi / 180;
  final latitudeGap = radians(to.latitude - from.latitude);
  final longitudeGap = radians(to.longitude - from.longitude);
  final haversine = pow(sin(latitudeGap / 2), 2) +
      cos(radians(from.latitude)) * cos(radians(to.latitude)) * pow(sin(longitudeGap / 2), 2);
  return 2 * 6371 * asin(min(1, sqrt(haversine)));
}
