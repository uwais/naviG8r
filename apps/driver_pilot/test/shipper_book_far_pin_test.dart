// Book stops a pickup or drop pin far from the trip's route: on the demo, "Kolar Bus Stand" for a
// Hoskote to Kolar (Karnataka) trip found Kolar in Himachal Pradesh, and priced a 2,000 km trip.
// Names, places and amounts are synthetic.
import 'package:dio/dio.dart' show RequestOptions;
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/maps_config.dart';
import 'package:driver_pilot/shipper/trip_route.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';

const hoskote = LatLng(13.0707, 77.7982);
const kolarKarnataka = LatLng(13.1357, 78.1326);
const kolarHimachal = LatLng(30.5596, 77.2955);

Map<String, dynamic> hoskoteToKolar() => {
      ...lane(from: 'Hoskote', to: 'Kolar'),
      'origin': {'lat': hoskote.latitude, 'lng': hoskote.longitude},
      'destination': {'lat': kolarKarnataka.latitude, 'lng': kolarKarnataka.longitude},
    };

/// Google's answer on the demo: the drop's words found the Kolar in Himachal Pradesh.
Future<GeocodeOutcome> findAsOnTheDemo(String place) async => place.contains('Kolar')
    ? GeocodeOutcome.ok(kolarHimachal, 'Kolar, Himachal Pradesh 173001, India', 'Kolar')
    : GeocodeOutcome.ok(hoskote, 'Hoskote, Karnataka 562114, India', 'Hoskote');

Future<FakeServer> fillBook(WidgetTester tester, Map<String, dynamic> trip,
    {PlaceFinder? findPlace = findAsOnTheDemo}) async {
  final server = await showShipperApp(tester, '/customer/book?anchorTripId=lane-1',
      findPlace: findPlace);
  server.answer('/anchor-trips/lane-1', {'trip': trip});
  server.answers['/shipments/quote'] = priceByWeight;
  await tester.pumpAndSettle();
  await tester.enterText(field('Weight'), '80');
  await searchPlace(tester, 'Pickup', 'Bus stand, Hoskote');
  await searchPlace(tester, 'Drop', 'Kolar Bus Stand');
  return server;
}

void main() {
  final farDropLine =
      "This pin is ${formatKm(kmFromRoute(kolarHimachal, hoskote, kolarKarnataka))} from this trip's route. Check the town and state, or move the pin.";
  const moveDropHelp = "Move the drop pin closer to this trip's route.";

  testWidgets('a drop pin far from the route says so, gets no price, and keeps Book and pay off',
      (tester) async {
    final server = await fillBook(tester, hoskoteToKolar());
    expect(find.text(farDropLine), findsOneWidget,
        reason: 'under the drop address, with how far the pin is');
    expect(server.countOf('/shipments/quote'), 0,
        reason: 'no price for a pin in the wrong state');
    expect(bookButton(tester).onPressed, isNull);
    expect(bookButton(tester).disabledReason, moveDropHelp);
    expect(find.text(moveDropHelp), findsOneWidget);

    pinIn(tester, 'Drop').onDragEnd!(kolarKarnataka);
    await tester.pumpAndSettle();
    expect(find.text(farDropLine), findsNothing,
        reason: 'the pin is on the route now');
    expect(server.countOf('/shipments/quote'), 1);
    expect(bookButton(tester).label, 'Book and pay ₹2,640');
    expect(bookButton(tester).onPressed, isNotNull);
  });

  testWidgets('a trip with no town pins is not checked, and books as before',
      (tester) async {
    final server = await fillBook(
        tester, hoskoteToKolar()..remove('origin')..remove('destination'));
    expect(find.textContaining("from this trip's route"), findsNothing);
    expect(server.countOf('/shipments/quote'), 1);
    expect(bookButton(tester).label, 'Book and pay ₹2,640');
  });

  testWidgets("Book's own search prefers the area around the trip's towns",
      (tester) async {
    final realAdapter = GoogleGeocodingService.dio.httpClientAdapter;
    addTearDown(() => GoogleGeocodingService.dio.httpClientAdapter = realAdapter);
    final searches = <RequestOptions>[];
    GoogleGeocodingService.dio.httpClientAdapter = MockApiAdapter((request) {
      searches.add(request);
      return jsonResponse({'status': 'ZERO_RESULTS', 'results': []});
    });
    await fillBook(tester, hoskoteToKolar(), findPlace: null);
    final area = areaAround((start: hoskote, end: kolarKarnataka));
    expect(searches, hasLength(2), reason: 'the pickup and the drop');
    for (final search in searches) {
      expect(search.queryParameters['bounds'],
          '${area.southwest.latitude},${area.southwest.longitude}|${area.northeast.latitude},${area.northeast.longitude}');
      expect(search.queryParameters['components'], 'country:IN');
    }
  }, skip: kMapsApiKey.isEmpty);
}
