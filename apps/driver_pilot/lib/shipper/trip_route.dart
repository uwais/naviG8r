// Where a trip runs, for Book's pickup and drop: the area a place search prefers, and how far a pin is
// from the route. A trip holds only its two town pins and no stops, so the route is the one stretch
// between them.
import "dart:math";

import "package:google_maps_flutter/google_maps_flutter.dart";

/// A pickup or drop pin further than this from the trip's route stops Book and pay: a search can find a
/// town of the same name in another state ("Kolar" in Himachal Pradesh for a Karnataka trip).
const farFromRouteKm = 50;

const _earthRadiusKm = 6371.0;

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

/// How far [pin] is from the trip's route when that is more than [farFromRouteKm]. Null when it is
/// nearer, or when the pin or the trip's town pins are missing: a trip without them books as before.
double? kmFarFromRoute(LatLng? pin, TripEnds? ends) {
  if (pin == null || ends == null) return null;
  final km = kmFromRoute(pin, ends.start, ends.end);
  return km > farFromRouteKm ? km : null;
}

/// The straight-line distance over the earth, in km, from [pin] to the nearest point of the shortest
/// path from [start] to [end]. Cross-track and along-track distance, as in Chris Veness's "Calculate
/// distance, bearing and more between Latitude/Longitude points" (movable-type.co.uk).
double kmFromRoute(LatLng pin, LatLng start, LatLng end) {
  final routeAngle = _angleBetween(start, end);
  final pinAngle = _angleBetween(start, pin);
  final bearingGap = _bearing(start, pin) - _bearing(start, end);
  // Behind the start, the start is the nearest point of the route.
  if (cos(bearingGap) < 0) return pinAngle * _earthRadiusKm;
  final offRoute = asin((sin(pinAngle) * sin(bearingGap)).clamp(-1.0, 1.0));
  final alongRoute = acos((cos(pinAngle) / cos(offRoute)).clamp(-1.0, 1.0));
  // Past the end, the end is.
  if (alongRoute > routeAngle) return _angleBetween(end, pin) * _earthRadiusKm;
  return offRoute.abs() * _earthRadiusKm;
}

double _radians(double degrees) => degrees * pi / 180;

/// The angle at the earth's centre between two points (haversine).
double _angleBetween(LatLng from, LatLng to) {
  final latitudeGap = _radians(to.latitude - from.latitude);
  final longitudeGap = _radians(to.longitude - from.longitude);
  final haversine = pow(sin(latitudeGap / 2), 2) +
      cos(_radians(from.latitude)) * cos(_radians(to.latitude)) * pow(sin(longitudeGap / 2), 2);
  return 2 * atan2(sqrt(haversine), sqrt(1 - haversine));
}

/// The compass direction, in radians, to set off in from [from] towards [to].
double _bearing(LatLng from, LatLng to) {
  final fromLatitude = _radians(from.latitude);
  final toLatitude = _radians(to.latitude);
  final longitudeGap = _radians(to.longitude - from.longitude);
  return atan2(sin(longitudeGap) * cos(toLatitude),
      cos(fromLatitude) * sin(toLatitude) - sin(fromLatitude) * cos(toLatitude) * cos(longitudeGap));
}
