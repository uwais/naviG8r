// Placing a trip's cities on the driver's map is a paid geocoding call. It is made once per
// screen: Refresh reloads the trip, and must not pay for the same two cities again. The app only
// geocodes with a maps key, so this runs with --dart-define=MAPS_API_KEY=test.
import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/maps_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';
import 'support/mock_api.dart';

void main() {
  final realAdapter = GoogleGeocodingService.dio.httpClientAdapter;
  tearDown(() {
    GoogleGeocodingService.dio.httpClientAdapter = realAdapter;
    DriverSession.clearCarrierCache();
  });

  testWidgets('Refresh makes no second geocoding call for the trip cities',
      (tester) async {
    final geocoded = <RequestOptions>[];
    GoogleGeocodingService.dio.httpClientAdapter = MockApiAdapter((request) {
      geocoded.add(request);
      return jsonResponse({
        'status': 'OK',
        'results': [
          {
            'formatted_address': 'Bengaluru, Karnataka, India',
            'geometry': {
              'location': {'lat': 12.97, 'lng': 77.59}
            },
          }
        ],
      });
    });
    signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: [carrierTrip('trip-moving', status: 'IN_PROGRESS')],
    ));
    final router = await mountCarrierApp(
        tester, '/driver/trip/trip-moving/active',
        size: const Size(800, 3000));
    expect(geocoded, hasLength(2), reason: 'the two cities, once');

    await tester.tap(find.byTooltip('Refresh').first);
    await tester.pumpAndSettle();
    expect(geocoded, hasLength(2), reason: 'Refresh pays for nothing new');
    router.go('/');
    await tester.pumpAndSettle();
  }, skip: kMapsApiKey.isEmpty);
}
