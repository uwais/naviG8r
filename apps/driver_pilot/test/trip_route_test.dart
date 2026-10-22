// How far a Book pin is from its trip's route: a search found Kolar in Himachal Pradesh for a
// Hoskote to Kolar (Karnataka) trip and priced it as a 2,000 km trip.
import 'dart:math';

import 'package:driver_pilot/shipper/trip_route.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const hoskote = LatLng(13.0707, 77.7982);
const kolarKarnataka = LatLng(13.1357, 78.1326);
const kolarHimachal = LatLng(30.5596, 77.2955);

/// A north-to-south route along one meridian, so a pin due east is off it by a known distance.
const routeStart = LatLng(13.0, 78.0);
const routeEnd = LatLng(14.0, 78.0);

/// [km] due east of the route's middle.
LatLng eastOfRouteMiddle(double km) =>
    LatLng(13.5, 78.0 + km / (6371.0 * pi / 180 * cos(13.5 * pi / 180)));

void main() {
  group('kmFromRoute', () {
    test('a pin on the route is about 0 km from it', () {
      expect(kmFromRoute(const LatLng(13.5, 78.0), routeStart, routeEnd),
          closeTo(0, 0.01));
      expect(kmFromRoute(hoskote, hoskote, kolarKarnataka), closeTo(0, 0.01));
      expect(
          kmFromRoute(const LatLng(13.1032, 77.9654), hoskote, kolarKarnataka),
          lessThan(1),
          reason: 'midway between the towns');
    });

    test('Kolar in Himachal Pradesh is over 1,500 km from Hoskote to Kolar', () {
      expect(kmFromRoute(kolarHimachal, hoskote, kolarKarnataka),
          greaterThan(1500));
    });

    test('a pin off the middle of the route is measured to the route, not to a town', () {
      expect(kmFromRoute(eastOfRouteMiddle(30), routeStart, routeEnd),
          closeTo(30, 0.5));
      expect(kmFromRoute(eastOfRouteMiddle(60), routeStart, routeEnd),
          closeTo(60, 0.5));
    });

    test('a pin beyond either end is measured to that end', () {
      // One degree of latitude is about 111 km.
      expect(kmFromRoute(const LatLng(12.5, 78.0), routeStart, routeEnd),
          closeTo(55.6, 0.5));
      expect(kmFromRoute(const LatLng(14.5, 78.0), routeStart, routeEnd),
          closeTo(55.6, 0.5));
    });
  });

  group('kmFarFromRoute', () {
    const ends = (start: routeStart, end: routeEnd);

    test('30 km off the route is allowed', () {
      expect(kmFarFromRoute(eastOfRouteMiddle(30), ends), isNull);
    });

    test('60 km off the route is too far', () {
      expect(kmFarFromRoute(eastOfRouteMiddle(60), ends), closeTo(60, 0.5));
    });

    test('a trip without town pins is not checked', () {
      expect(kmFarFromRoute(kolarHimachal, null), isNull);
      expect(tripEnds({'origin': {'lat': 13.07, 'lng': 77.79}}), isNull);
      expect(tripEnds({
        'origin': {'lat': 13.07, 'lng': 77.79},
        'destination': {'lat': 13.13, 'lng': 78.13},
      }), (start: const LatLng(13.07, 77.79), end: const LatLng(13.13, 78.13)));
    });
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
