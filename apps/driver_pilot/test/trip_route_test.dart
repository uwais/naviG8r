// Where a trip runs, for Book: its town pins, the area its place searches prefer, and straight-line km.
import 'package:driver_pilot/shipper/trip_route.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const hoskote = LatLng(13.0707, 77.7982);
const kolarKarnataka = LatLng(13.1357, 78.1326);

void main() {
  test('km between two points: the same point is 0, and one degree of latitude about 111', () {
    expect(kmBetween(hoskote, hoskote), 0);
    expect(kmBetween(const LatLng(13.0, 78.0), const LatLng(14.0, 78.0)),
        closeTo(111.2, 0.1));
    expect(kmBetween(hoskote, kolarKarnataka),
        closeTo(kmBetween(kolarKarnataka, hoskote), 1e-9));
  });

  test('a trip without both town pins has no ends', () {
    expect(tripEnds({'origin': {'lat': 13.07, 'lng': 77.79}}), isNull);
    expect(tripEnds({
      'origin': {'lat': 13.07, 'lng': 77.79},
      'destination': {'lat': 13.13, 'lng': 78.13},
    }), (start: const LatLng(13.07, 77.79), end: const LatLng(13.13, 78.13)));
  });

  test('the search area is both towns with half a degree to spare', () {
    final area = areaAround((start: kolarKarnataka, end: hoskote));
    expect(area.southwest, LatLng(hoskote.latitude - 0.5, hoskote.longitude - 0.5));
    expect(area.northeast,
        LatLng(kolarKarnataka.latitude + 0.5, kolarKarnataka.longitude + 0.5));
  });

  test('km are rounded and grouped the Indian way', () {
    expect(formatKm(44.6), '45 km');
    expect(formatKm(1834.2), '1,834 km');
    expect(formatKm(123456), '1,23,456 km');
  });
}
