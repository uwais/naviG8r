// The place boxes on Match and Book when the place search fails: each failure gets its own plain
// sentence, and a blank place is asked for, not searched.
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/shipper/book_a_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/shipper_lanes_app.dart';

void main() {
  placeSearchFailureTests();
}

/// The real place search with no maps key, as a build without MAPS_API_KEY runs it.
Future<GeocodeOutcome> findWithNoMapsKey(String place) =>
    GoogleGeocodingService.forwardAddress(place, apiKey: '');

PlaceFinder failsWith(String status) =>
    (_) async => GeocodeOutcome.fail(status);

void placeSearchFailureTests() {
  // The sentences that offer the pin: both screens now have a map to drag it on.
  final failures = [
    (
      kind: 'no maps key',
      findPlace: findWithNoMapsKey,
      sentence:
          'Place search is not working right now. Drag the pin on the map to the place.'
    ),
    (
      kind: 'no match',
      findPlace: failsWith('ZERO_RESULTS'),
      sentence:
          'Could not find this place. Try a nearby town, or drag the pin on the map to it.'
    ),
    (
      kind: 'no connection',
      findPlace: failsWith('NETWORK'),
      sentence:
          'Could not reach the map service. Check your connection, then search again.'
    ),
    (
      kind: 'a refused key',
      findPlace: failsWith('REQUEST_DENIED'),
      sentence:
          'Place search is not working right now. Drag the pin on the map to the place.'
    ),
  ];

  Future<FakeServer> fillMatch(WidgetTester tester, PlaceFinder findPlace,
      {String pickup = 'gurugram', String drop = 'jaipur'}) async {
    final server = await showShipperApp(tester, '/customer/trips?tab=match',
        findPlace: findPlace);
    await tester.pumpAndSettle();
    await searchPlace(tester, 'Pickup', pickup);
    await searchPlace(tester, 'Drop', drop);
    await tester.enterText(field('Weight'), '80');
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    return server;
  }

  Future<FakeServer> fillBook(WidgetTester tester, PlaceFinder findPlace,
      {String pickup = 'gurugram', String drop = 'jaipur'}) async {
    final server = await showShipperApp(
        tester, '/customer/book?anchorTripId=lane-1&weightKg=80',
        findPlace: findPlace,
        initialExtra: SearchedPlaces(
            pickup: (words: pickup, point: null),
            drop: (words: drop, point: null)));
    server.answer('/anchor-trips/lane-1', {'trip': lane()});
    await tester.pumpAndSettle();
    for (final title in ['Pickup', 'Drop']) {
      await tester.tap(find.descendant(
          of: placeBox(title), matching: find.byTooltip('Search for place')));
      await tester.pumpAndSettle();
    }
    return server;
  }

  group('a failed place search says what failed', () {
    for (final failure in failures) {
      testWidgets('Match: ${failure.kind}', (tester) async {
        final server = await fillMatch(tester, failure.findPlace);
        expect(find.text(failure.sentence), findsNWidgets(2),
            reason: 'one sentence under Pickup and one under Drop');
        expect(find.byType(GoogleMap), findsNWidgets(2),
            reason: 'the map the sentence offers is there to drag the pin on');
        expect(server.countOf('/v1/customer/eligible-anchor-trips'), 0);
        expect(find.textContaining('dart-define'), findsNothing,
            reason: 'no developer hint on a shipper screen');
        if (failure.kind == 'no maps key') {
          expect(find.textContaining('Could not find this place'), findsNothing,
              reason:
                  'Uwais: "gurugram" and "jaipur" were called unknown places when the app had no maps key');
        }
      });

      testWidgets('Book: ${failure.kind}', (tester) async {
        final server = await fillBook(tester, failure.findPlace);
        expect(find.text(failure.sentence), findsNWidgets(2),
            reason: 'one sentence under Pickup and one under Drop');
        expect(find.byType(GoogleMap), findsNWidgets(2),
            reason: 'the map the sentence offers is there to drag the pin on');
        expect(server.countOf('/shipments/quote'), 0);
        expect(find.textContaining('dart-define'), findsNothing,
            reason: 'no developer hint on a shipper screen');
        if (failure.kind == 'no maps key') {
          expect(find.textContaining('Could not find this place'), findsNothing,
              reason:
                  'Uwais: "gurugram" and "jaipur" were called unknown places when the app had no maps key');
        }
      });
    }

    testWidgets('Match: blank places are asked for, not searched',
        (tester) async {
      var searched = false;
      final server = await showShipperApp(tester, '/customer/trips?tab=match',
          findPlace: (place) async {
        searched = true;
        return findAnyPlace(place);
      });
      await tester.pumpAndSettle();
      await tester.enterText(placeField('Pickup'), '  ');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the pickup place.'), findsOneWidget);
      expect(find.text('Enter the drop place.'), findsOneWidget);
      expect(searched, isFalse);
      expect(server.countOf('/v1/customer/eligible-anchor-trips'), 0);
    });

    testWidgets('Book: blank places are asked for, not searched',
        (tester) async {
      var searched = false;
      final server = await showShipperApp(
          tester, '/customer/book?anchorTripId=lane-1&weightKg=80',
          findPlace: (place) async {
        searched = true;
        return findAnyPlace(place);
      });
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.pumpAndSettle();
      expect(find.text('To see the price, search for the pickup and drop.'),
          findsOneWidget);
      expect(searched, isFalse);
      expect(server.countOf('/shipments/quote'), 0);
    });
  });
}
