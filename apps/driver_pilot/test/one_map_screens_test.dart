// Owner, 5 Nov 2026: Search by route, Book this trip and Add trip each show one map for their two places,
// in place of a map under each place box. Book clears its price when the map moves either pin.
import 'dart:async';

import 'package:dio/dio.dart' show ResponseBody;
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/carrier_office_screens.dart';
import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';

void main() {
  testWidgets('Search by route: one map shows both places', (tester) async {
    final server = await showShipperApp(tester, '/customer/trips?tab=match',
        findPlace: (place) async => GeocodeOutcome.ok(
            place.contains('Chennai') ? const LatLng(13.0, 80.2) : const LatLng(12.8, 77.7),
            place,
            place));
    server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
    await tester.pumpAndSettle();
    await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
    await searchPlace(tester, 'Drop', 'Guindy, Chennai');
    expect(find.byType(GoogleMap), findsOneWidget);
    expect(oneMap(tester).markers.map((pin) => pin.infoWindow.title), ['Pickup', 'Drop']);
    expect(pinOnMap(tester, 'Drop').position, const LatLng(13.0, 80.2));
    expect(find.text('Tap the map to move the drop pin.'), findsOneWidget,
        reason: 'the Drop box was touched last');
  });

  testWidgets('Book this trip: one map shows both places', (tester) async {
    await showPricedBook(tester);
    expect(find.byType(GoogleMap), findsOneWidget,
        reason: 'the pins check below has no map of its own now');
    expect(oneMap(tester).markers, hasLength(2));
  });

  group('Book this trip clears the price when the map moves a pin', () {
    for (final title in ['Pickup', 'Drop']) {
      testWidgets(title, (tester) async {
        final server = await showPricedBook(tester);
        expect(bookButton(tester).label, 'Book and pay ₹2,640');
        final newPrice = Completer<ResponseBody>();
        server.answers['/shipments/quote'] = (_) => newPrice.future;
        await chooseOnMap(tester, title);
        oneMap(tester).onTap!(const LatLng(12.9, 77.6));
        await pumpWhileWaiting(tester);
        expect(find.text('₹2,640'), findsNothing,
            reason: 'the old price goes at once: it is for the old pin');
        expect(bookButton(tester).label, isNot(contains('₹')));
        expect(server.countOf('/shipments/quote'), 2, reason: 'the moved pin is priced again');
        expect(
            (server.sentTo('/shipments/quote').last[title.toLowerCase()] as Map)['lat'], 12.9,
            reason: 'only the $title pin moved');
        newPrice.complete(jsonResponse({
          'quote': {'grossPaise': 300000}
        }));
        await tester.pumpAndSettle();
      });
    }
  });

  group('Add trip', () {
    setUp(() => GeolocatorPlatform.instance = NoLocation());
    tearDown(DriverSession.clearCarrierCache);

    testWidgets('one map shows From and To, and moves one at a time', (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.ok(
                  place == 'Hoskote' ? const LatLng(13.07, 77.79) : const LatLng(13.13, 78.13),
                  '$place, Karnataka'),
              namePin: (point) async => GeocodeOutcome.ok(point, 'Malur, Karnataka', 'Malur')),
          size: const Size(800, 3000));
      for (final (index, place) in [(0, 'Hoskote'), (1, 'Kolar')]) {
        await tester.enterText(find.byType(TextField).at(index), place);
        await tester.tap(find.byTooltip(index == 0 ? 'Search for From' : 'Search for To'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(GoogleMap), findsOneWidget);
      await chooseOnMap(tester, 'From');
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to move the From pin.'), findsOneWidget);
      oneMap(tester).onTap!(const LatLng(13.0, 78.0));
      await tester.pumpAndSettle();
      expect(pinOnMap(tester, 'From').position, const LatLng(13.0, 78.0));
      expect(pinOnMap(tester, 'To').position, const LatLng(13.13, 78.13));
      expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, 'Malur',
          reason: 'the From town is looked up for the moved pin, as after a drag');
    });
  });
}
