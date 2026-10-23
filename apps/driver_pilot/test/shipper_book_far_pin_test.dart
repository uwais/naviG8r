// Book holds back a pickup far from the trip's start town or a drop far from its end town, the
// server's own 15 km rule: on the demo, "Kolar Bus Stand" for a Hoskote to Kolar (Karnataka) trip
// found Kolar in Himachal Pradesh, and priced a 2,000 km trip. Names, places and amounts are synthetic.
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart' show RequestOptions, ResponseBody;
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/shipper/book_far_pin.dart';
import 'package:driver_pilot/shipper/trip_route.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';

const hoskote = LatLng(13.0707, 77.7982);
const kolarKarnataka = LatLng(13.1357, 78.1326);
const kolarHimachal = LatLng(30.5596, 77.2955);

/// [km] due east of [town].
LatLng eastOf(LatLng town, double km) => LatLng(town.latitude,
    town.longitude + km / (6371 * pi / 180 * cos(town.latitude * pi / 180)));

Map<String, dynamic> hoskoteToKolar() => {
      ...lane(from: 'Hoskote', to: 'Kolar'),
      'origin': {'lat': hoskote.latitude, 'lng': hoskote.longitude},
      'destination': {'lat': kolarKarnataka.latitude, 'lng': kolarKarnataka.longitude},
    };

/// Google's answer on the demo: the drop's words found the Kolar in Himachal Pradesh.
Future<GeocodeOutcome> findAsOnTheDemo(String place) async => place.contains('Kolar')
    ? GeocodeOutcome.ok(kolarHimachal, 'Kolar, Himachal Pradesh 173001, India', 'Kolar')
    : GeocodeOutcome.ok(hoskote, 'Hoskote, Karnataka 562114, India', 'Hoskote');

/// A dragged pin is named at once, with no address, so no test waits on Google.
Future<GeocodeOutcome> nameNoPin(LatLng point) async => GeocodeOutcome.fail('ZERO_RESULTS');

Future<FakeServer> openBook(WidgetTester tester, Map<String, dynamic> trip,
    {PlaceFinder? findPlace = findAsOnTheDemo, String? mapsApiKey}) async {
  final server = await showShipperApp(tester, '/customer/book?anchorTripId=lane-1',
      findPlace: findPlace, namePin: nameNoPin, mapsApiKey: mapsApiKey);
  server.answer('/anchor-trips/lane-1', {'trip': trip});
  server.answers['/shipments/quote'] = priceByWeight;
  await tester.pumpAndSettle();
  await tester.enterText(field('Weight'), '80');
  await searchPlace(tester, 'Pickup', 'Bus stand, Hoskote');
  return server;
}

Future<FakeServer> fillBook(WidgetTester tester, Map<String, dynamic> trip,
    {PlaceFinder? findPlace = findAsOnTheDemo, String? mapsApiKey}) async {
  final server = await openBook(tester, trip, findPlace: findPlace, mapsApiKey: mapsApiKey);
  await searchPlace(tester, 'Drop', 'Kolar Bus Stand');
  return server;
}

Future<void> movePin(WidgetTester tester, String title, LatLng to) async {
  pinIn(tester, title).onDragEnd!(to);
  await tester.pumpAndSettle();
}

String dropLine(int km) =>
    'About ${formatKm(km)} from Kolar.';
String pickupLine(int km) =>
    'About ${formatKm(km)} from Hoskote.';
const moveDropHelp = 'Move the drop pin, or choose another trip.';
const movePickupHelp = 'Move the pickup pin, or choose another trip.';

void expectNoPrice(WidgetTester tester) {
  expect(bookButton(tester).label, 'Book and pay');
  expect(bookButton(tester).onPressed, isNull);
  expect(find.textContaining('Book and pay ₹'), findsNothing);
}

void main() {
  group('the 15 km rule', () {
    test('mirrors the server default', () {
      expect(farPinLimitKm, 15);
    });

    test('10 km from the town is allowed, 20 km is too far', () {
      expect(farPinKm(eastOf(hoskote, 10), hoskote), isNull);
      expect(farPinKm(eastOf(hoskote, 20), hoskote), closeTo(20, 0.1));
    });

    test('Kolar in Himachal Pradesh is far over the limit from Kolar in Karnataka', () {
      expect(farPinKm(kolarHimachal, kolarKarnataka), greaterThan(1500));
    });

    test('a missing pin or town pin is not checked', () {
      expect(farPinKm(null, kolarKarnataka), isNull);
      expect(farPinKm(kolarHimachal, null), isNull);
    });

    ({String sentence, String help}) refusal(Map<String, Object> body) =>
        farPinsRefusal(body, startTown: 'Hoskote', endTown: 'Kolar');

    test("the server's refusal names the pin it refused and how far", () {
      expect(
          refusal({'pickupDistanceKm': 15.3, 'dropDistanceKm': 2, 'maxPickupKm': 15, 'maxDropKm': 15}),
          (
            sentence:
                'Pickup pin is 16 km from Hoskote.',
            help: 'Move the pickup pin, or choose another trip.',
          ));
      expect(
          refusal({'pickupDistanceKm': 20.1, 'dropDistanceKm': 30, 'maxPickupKm': 12.5, 'maxDropKm': 15})
              .sentence,
          'Pickup pin is 21 km from Hoskote, drop pin 30 km from Kolar.',
          reason: 'distance rounded up');
    });

    test("without the server's numbers, both pins", () {
      expect(refusal({'error': 'phase_a_not_eligible'}), (
        sentence:
            'A pin is too far from Hoskote or Kolar.',
        help: 'Move the pickup and drop pins, or choose another trip.',
      ));
    });
  });

  testWidgets(
      'a drop pin far from the end town says so, gets no price, and offers another trip',
      (tester) async {
    final server = await fillBook(tester, hoskoteToKolar());
    final km = kmBetween(kolarHimachal, kolarKarnataka).ceil();
    expect(find.text(dropLine(km)), findsOneWidget,
        reason: 'under the drop address, with about how far the pin is');
    expect(server.countOf('/shipments/quote'), 0,
        reason: 'no price for a pin in the wrong state');
    expectNoPrice(tester);
    expect(bookButton(tester).disabledReason, moveDropHelp);
    expect(find.text(moveDropHelp), findsOneWidget);
    expect(find.text('Choose another trip'), findsOneWidget,
        reason: 'the same way out as a weight that does not fit');

    await movePin(tester, 'Drop', eastOf(kolarKarnataka, 10));
    expect(find.text(dropLine(km)), findsNothing, reason: '10 km from Kolar is allowed');
    expect(find.text('Choose another trip'), findsNothing);
    expect(server.countOf('/shipments/quote'), 1);
    expect(bookButton(tester).label, 'Book and pay ₹2,640');
    expect(bookButton(tester).onPressed, isNotNull);
  });

  testWidgets('a pickup just over 15 km reads as 16, never 15, and says which pin to move',
      (tester) async {
    final server = await fillBook(tester, hoskoteToKolar());
    await movePin(tester, 'Drop', kolarKarnataka);
    await movePin(tester, 'Pickup', eastOf(hoskote, 15.3));
    expect(find.text(pickupLine(16)), findsOneWidget,
        reason: 'review: rounded up, so a refused pin never reads as within 15 km');
    expect(bookButton(tester).disabledReason, movePickupHelp);
    expectNoPrice(tester);
    expect(server.countOf('/shipments/quote'), 1, reason: 'only the price before the move');

    await movePin(tester, 'Pickup', eastOf(hoskote, 20));
    await movePin(tester, 'Drop', kolarHimachal);
    expect(bookButton(tester).disabledReason,
        'Move the pickup and drop pins, or choose another trip.');
  });

  testWidgets('an emptied address box asks for a search, not to move its pin',
      (tester) async {
    await fillBook(tester, hoskoteToKolar());
    await tester.enterText(placeField('Drop'), '');
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^About \d')), findsNothing,
        reason: 'review: an empty box is no place, so there is no far pin');
    expect(bookButton(tester).disabledReason, 'To see the price, search for the drop.');
  });

  testWidgets('a priced booking whose drop pin then moves far loses its price and asks for none',
      (tester) async {
    final server = await fillBook(tester, hoskoteToKolar());
    await movePin(tester, 'Drop', kolarKarnataka);
    expect(bookButton(tester).label, 'Book and pay ₹2,640');
    await movePin(tester, 'Drop', kolarHimachal);
    expectNoPrice(tester);
    expect(server.countOf('/shipments/quote'), 1, reason: 'no new price request');
  });

  testWidgets('a price that answers after its pin moved far is not shown', (tester) async {
    final server = await openBook(tester, hoskoteToKolar(),
        findPlace: (place) async => GeocodeOutcome.ok(
            place.contains('Kolar') ? kolarKarnataka : hoskote, place, place));
    final answer = Completer<ResponseBody>();
    server.answers['/shipments/quote'] = (_) => answer.future;
    await tester.enterText(placeField('Drop'), 'Kolar Bus Stand');
    await tester.tap(find.descendant(
        of: placeBox('Drop'), matching: find.byTooltip('Search for place')));
    await pumpWhileWaiting(tester);
    expect(server.countOf('/shipments/quote'), 1, reason: 'the price is out');

    pinIn(tester, 'Drop').onDragEnd!(kolarHimachal);
    await pumpWhileWaiting(tester);
    answer.complete(jsonResponse({'quote': {'grossPaise': 264000}}));
    await tester.pumpAndSettle();
    expectNoPrice(tester);
    expect(bookButton(tester).disabledReason, moveDropHelp);
  });

  testWidgets('a trip with no town pins is not checked, and books as before',
      (tester) async {
    final server = await fillBook(
        tester, hoskoteToKolar()..remove('origin')..remove('destination'));
    expect(find.textContaining(RegExp(r'^About \d')), findsNothing);
    expect(server.countOf('/shipments/quote'), 1);
    expect(bookButton(tester).label, 'Book and pay ₹2,640');
  });

  testWidgets("the server's far-pin refusal is said in plain words", (tester) async {
    final server = await fillBook(tester, hoskoteToKolar());
    await movePin(tester, 'Drop', kolarKarnataka);
    server.answer('/shipments/book', {
      'error': 'phase_a_not_eligible',
      'reason': 'too_far_from_endpoints',
      'pickupDistanceKm': 0,
      'dropDistanceKm': 13.2,
      'maxPickupKm': 15,
      'maxDropKm': 12,
    }, 400);
    final tripLoads = server.countOf('/anchor-trips/lane-1');
    await tester.tap(find.text('Book and pay ₹2,640'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Drop pin is 14 km from Kolar.'),
        findsOneWidget,
        reason: 'not "Could not book. Check your connection"');
    expectNoPrice(tester);
    expect(bookButton(tester).disabledReason, moveDropHelp);
    expect(find.text('Choose another trip'), findsOneWidget);
    expect(server.countOf('/anchor-trips/lane-1'), tripLoads + 1,
        reason: 'the trip is loaded again, as after a closed-trip refusal');
    expect(server.countOf('/shipments/quote'), 1, reason: 'no new price until a pin moves');

    await movePin(tester, 'Drop', eastOf(kolarKarnataka, 5));
    expect(bookButton(tester).label, 'Book and pay ₹2,640',
        reason: 'a moved pin is priced again');
  });

  testWidgets('a pinned trip states its rule under the summary',
      (tester) async {
    const rule = 'Picks up within 15 km of Hoskote and drops within 15 km of Kolar.';
    await openBook(tester, hoskoteToKolar());
    expect(find.text(rule), findsOneWidget);
  });

  testWidgets('a trip without town pins states no rule', (tester) async {
    await openBook(tester, hoskoteToKolar()..remove('origin')..remove('destination'));
    expect(find.textContaining('Picks up within'), findsNothing);
  });

  testWidgets('pickup and drop within 15 km book, with both pins, and open the shipment',
      (tester) async {
    final server = await fillBook(tester, hoskoteToKolar());
    await movePin(tester, 'Drop', eastOf(kolarKarnataka, 10));
    server.answer('/shipments/book', {
      'shipment': {'id': 'shipment-9'},
      'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
    }, 201);
    await tester.tap(find.text('Book and pay ₹2,640'));
    await tester.pumpAndSettle();
    final booked = server.sentTo('/shipments/book').single;
    expect(booked['pickup'], containsPair('lat', hoskote.latitude));
    expect(booked['pickup'], containsPair('lng', hoskote.longitude));
    final drop = eastOf(kolarKarnataka, 10);
    expect(booked['drop'], containsPair('lat', drop.latitude));
    expect(booked['drop'], containsPair('lng', drop.longitude));
    expect(find.text('Shipment shipment-9'), findsOneWidget,
        reason: 'after booking, the shipment opens');
  });

  testWidgets("Book's own search takes an answer that is only a state as not found",
      (tester) async {
    final realAdapter = GoogleGeocodingService.dio.httpClientAdapter;
    addTearDown(() => GoogleGeocodingService.dio.httpClientAdapter = realAdapter);
    GoogleGeocodingService.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
          'status': 'OK',
          'results': [
            {
              'formatted_address': 'Karnataka, India',
              'types': ['administrative_area_level_1', 'political'],
              'geometry': {
                'location': {'lat': 15.32, 'lng': 75.71}
              },
            }
          ],
        }));
    await openBook(tester, hoskoteToKolar(), findPlace: null, mapsApiKey: 'test-key');
    expect(find.text(placeSearchFailureSentence(PlaceSearchFailure.notFound, pinOnMap: true)),
        findsOneWidget,
        reason: 'no pickup pin in the middle of the state');
  });

  testWidgets("Book's own search sends the country and the area around the trip's towns",
      (tester) async {
    final realAdapter = GoogleGeocodingService.dio.httpClientAdapter;
    addTearDown(() => GoogleGeocodingService.dio.httpClientAdapter = realAdapter);
    final searches = <RequestOptions>[];
    GoogleGeocodingService.dio.httpClientAdapter = MockApiAdapter((request) {
      searches.add(request);
      return jsonResponse({'status': 'ZERO_RESULTS', 'results': []});
    });
    await fillBook(tester, hoskoteToKolar(), findPlace: null, mapsApiKey: 'test-key');
    final area = areaAround((start: hoskote, end: kolarKarnataka));
    expect(searches, hasLength(2), reason: 'the pickup and the drop');
    for (final search in searches) {
      expect(search.queryParameters['bounds'],
          '${area.southwest.latitude},${area.southwest.longitude}|${area.northeast.latitude},${area.northeast.longitude}');
      expect(search.queryParameters['components'], 'country:IN');
    }
  });
}
