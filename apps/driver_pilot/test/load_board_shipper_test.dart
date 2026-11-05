// Load Board phase 1, the shipper side (4 Nov 2026): Post a load from a search that found nothing, and My loads
// with the trips carriers added. Names and places are synthetic. No amount may show before today's booking.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/load_board/post_a_load.dart' show townToPost;
import 'package:driver_pilot/load_board/posted_load_words.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';

/// Runs the route search for 500 kg with nothing found.
Future<FakeServer> searchWithNothingFound(WidgetTester tester) async {
  final server = await showShipperApp(tester, '/customer/trips?tab=match');
  server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
  await tester.pumpAndSettle();
  await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
  await searchPlace(tester, 'Drop', 'Guindy, Chennai');
  await tester.enterText(field('Weight'), '500');
  await tester.tap(find.text('Find trips'));
  await tester.pumpAndSettle();
  return server;
}

/// The bodies of the POSTs to [path]; My loads also reads that path once posting opens it.
List<Map> postsTo(FakeServer server, String path) => [
      for (final request in server.requests)
        if (request.method == 'POST' && request.path == path)
          request.data as Map
    ];

/// The optional Note field, whose label reads "Note (optional)".
final noteField = find.descendant(
    of: find.byWidgetPredicate((widget) => widget is NvField && widget.label == 'Note'),
    matching: find.byType(TextField));

Future<void> tapButton(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

final today = calendarDayText(todayInIndia());

/// A posted load as GET /v1/posted-loads sends it to its own company.
Map<String, dynamic> myLoad(
        {String id = 'load-1',
        String state = 'OPEN',
        List<Map<String, dynamic>> routes = const [],
        Map<String, dynamic>? booking}) =>
    {
      'id': id,
      'from': {'city': 'Bengaluru', 'lat': 12.8, 'lng': 77.7},
      'to': {'city': 'Chennai', 'lat': 13.0, 'lng': 80.2},
      'weightKg': 500,
      'packages': {
        'kind': 'SIZES',
        'count': 12,
        'length': 40,
        'width': 30,
        'height': 20,
        'unit': 'INCHES'
      },
      'earliestPickupDate': '2026-11-05',
      'latestPickupDate': '2026-11-06',
      'note': 'Fragile cartons',
      'state': state,
      'postedAtUtcMs': 1793000000000,
      'routes': routes,
      if (booking != null) 'booking': booking,
    };

Map<String, dynamic> routeFor(String tripId,
        {bool canBook = true, String? whyNotBookable}) =>
    {
      'tripId': tripId,
      'madeAtUtcMs': 1793000100000,
      'canBook': canBook,
      if (whyNotBookable != null) 'whyNotBookable': whyNotBookable,
      'trip': lane(id: tripId, carrier: 'Deccan Movers'),
    };

/// Every word on screen, for checks that no amount shows.
String wordsOnScreen(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        text.data ?? text.textSpan?.toPlainText() ?? '',
    ].join('\n');

void main() {
  group('Post a load', () {
    testWidgets(
        'nothing found offers Post a load, which opens filled in from the search',
        (tester) async {
      await searchWithNothingFound(tester);
      expect(
          find.text(
              'Or post your load. Carriers going your way can add a trip for it.'),
          findsOneWidget);
      await tapButton(tester, 'Post a load');

      expect(find.text('Post a load'), findsWidgets);
      String fieldText(String label) =>
          tester.widget<TextField>(field(label)).controller!.text;
      expect(fieldText('Pickup town'), 'Bengaluru',
          reason: 'carriers get the town of the searched address, never the address');
      expect(fieldText('Drop town'), 'Chennai');
      expect(
          find.text(
              'Carriers on the Load Board see what you type here. Type the town only, not your street address.'),
          findsNWidgets(2));
      expect(fieldText('Weight'), '500');
      expect(find.textContaining('₹'), findsNothing,
          reason: 'no price before the booking');
    });

    testWidgets(
        'Post load sends the towns, points, size and pickup days, and opens My loads',
        (tester) async {
      final server = await searchWithNothingFound(tester);
      await tapButton(tester, 'Post a load');
      server.answer('/v1/posted-loads', {'loads': <Object>[]});

      await tapButton(tester, 'Number and size');
      await tester.enterText(field('Number of packages'), '12');
      await tester.enterText(field('Length'), '40');
      await tester.enterText(field('Width'), '30');
      await tester.enterText(field('Height'), '20.5');
      await tapButton(tester, 'cm');
      await tester.enterText(noteField, '  Fragile cartons  ');
      await tester.tap(find.text('Post load'));
      await tester.pumpAndSettle();

      final posts = postsTo(server, '/v1/posted-loads');
      expect(posts, hasLength(1));
      expect(posts.single, {
        'from': {'city': 'Bengaluru', 'lat': 12.8, 'lng': 77.7},
        'to': {'city': 'Chennai', 'lat': 12.8, 'lng': 77.7},
        'weightKg': 500,
        'packages': {
          'kind': 'SIZES',
          'count': 12,
          'length': 40,
          'width': 30,
          'height': 20.5,
          'unit': 'CENTIMETRES'
        },
        'earliestPickupDate': today,
        'latestPickupDate': today,
        'note': 'Fragile cartons',
      });
      expect(find.text('My loads'), findsWidgets,
          reason: 'after posting, the shipper sees the load under My loads');
    });

    testWidgets('a total volume is sent with its unit, and no note is sent when empty',
        (tester) async {
      final server = await searchWithNothingFound(tester);
      await tapButton(tester, 'Post a load');
      await tapButton(tester, 'Total volume');
      await tester.enterText(field('Total volume'), '3.5');
      await tapButton(tester, 'Cubic metres');
      await tester.tap(find.text('Post load'));
      await tester.pumpAndSettle();
      final sent = postsTo(server, '/v1/posted-loads').single;
      expect(sent['packages'],
          {'kind': 'TOTAL_VOLUME', 'volume': 3.5, 'unit': 'CUBIC_METRES'});
      expect(sent.containsKey('note'), isFalse);
    });

    testWidgets('without a size it says what is missing and sends nothing',
        (tester) async {
      final server = await searchWithNothingFound(tester);
      await tapButton(tester, 'Post a load');
      await tester.tap(find.text('Post load'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Choose how to give the size: number and size, or total volume.'),
          findsOneWidget);
      expect(postsTo(server, '/v1/posted-loads'), isEmpty);

      await tapButton(tester, 'Number and size');
      await tester.enterText(field('Number of packages'), '12');
      await tester.tap(find.text('Post load'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Enter how many packages, the size of each, and inches or cm.'),
          findsOneWidget);
      expect(postsTo(server, '/v1/posted-loads'), isEmpty);
    });

    testWidgets('the server refusing an eleventh open load is said in words',
        (tester) async {
      final server = await searchWithNothingFound(tester);
      await tapButton(tester, 'Post a load');
      server.answer('/v1/posted-loads',
          {'error': 'too_many_open_loads', 'limit': 10}, 409);
      await tapButton(tester, 'Total volume');
      await tester.enterText(field('Total volume'), '120');
      await tapButton(tester, 'Cubic feet');
      await tester.tap(find.text('Post load'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Your company already has 10 open loads. Withdraw one under My loads to post another.'),
          findsOneWidget);
      expect(find.textContaining('HTTP'), findsNothing);
    });

    testWidgets('a login that cannot book is not offered Post a load',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      AuthorizationSession.principal!['permissions'] = [
        for (final permission
            in AuthorizationSession.principal!['permissions'] as List)
          if (permission != 'load.create') permission
      ];
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '500');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(find.text('No trips pass near this route with capacity for 500 kg.'),
          findsOneWidget);
      expect(find.text('Post a load'), findsNothing);
    });
  });

  group('My loads', () {
    testWidgets(
        'each load shows its state, size, days, note and the trips added, with no amount',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/loads');
      server.answer('/v1/posted-loads', {
        'loads': [
          myLoad(routes: [
            routeFor('trip-a'),
            routeFor('trip-b',
                canBook: false, whyNotBookable: 'NOT_ENOUGH_ROOM')
          ]),
          myLoad(id: 'load-2', state: 'EXPIRED'),
        ]
      });
      await tester.pumpAndSettle();

      expect(find.text('Bengaluru to Chennai'), findsNWidgets(2));
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Pickup days passed'), findsOneWidget);
      final words = wordsOnScreen(tester);
      expect(words, contains('12 packages, each 40 by 30 by 20 inches'));
      expect(words, contains('Fragile cartons'),
          reason: 'the posting company sees its own note');
      expect(find.text('Trips for this load (2)'), findsOneWidget);
      expect(find.text('Deccan Movers'), findsNWidgets(2));
      expect(words, contains('Medium truck'),
          reason: 'the truck as the route search shows it');
      expect(find.widgetWithText(FilledButton, 'Book'), findsOneWidget,
          reason: 'only a trip the server says can be booked has Book');
      expect(find.text('Not enough room left on this trip for this load.'),
          findsOneWidget,
          reason: 'a trip without Book says why');
      expect(words, isNot(contains('₹')), reason: 'no amount on My loads');
      expect(find.text('Withdraw'), findsOneWidget,
          reason: 'only an open load can be withdrawn');
    });

    testWidgets("Book opens today's booking for that trip with the load's weight and points",
        (tester) async {
      final server = await showShipperApp(tester, '/customer/loads');
      server.answer('/v1/posted-loads', {
        'loads': [
          myLoad(routes: [routeFor('lane-1')])
        ]
      });
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.pumpAndSettle();
      await tapButton(tester, 'Book');

      expect(find.text('Book this trip'), findsOneWidget);
      expect(tester.widget<TextField>(field('Weight')).controller!.text, '500');
      expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
          'Bengaluru');
      expect(pinIn(tester, 'Pickup').position, const LatLng(12.8, 77.7));
      expect(pinIn(tester, 'Drop').position, const LatLng(13.0, 80.2));
    });

    testWidgets('Withdraw is one tap, and the list shows the load withdrawn',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/loads');
      var withdrawn = false;
      server.answers['/v1/posted-loads'] = (_) => jsonResponse({
            'loads': [myLoad(state: withdrawn ? 'WITHDRAWN' : 'OPEN')]
          });
      server.answers['/v1/posted-loads/load-1/withdraw'] = (_) {
        withdrawn = true;
        return jsonResponse({'load': myLoad(state: 'WITHDRAWN')});
      };
      await tester.pumpAndSettle();
      expect(find.text('No carrier has added a trip yet. We tell you when one does.'),
          findsOneWidget);
      await tapButton(tester, 'Withdraw');

      expect(server.countOf('/v1/posted-loads/load-1/withdraw'), 1,
          reason: 'one action, no extra step');
      expect(find.text('Withdrawn'), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
    });

    testWidgets('a booked load opens its shipment', (tester) async {
      final server = await showShipperApp(tester, '/customer/loads');
      server.answer('/v1/posted-loads', {
        'loads': [
          myLoad(
              state: 'BOOKED',
              routes: [
                routeFor('trip-a',
                    canBook: false, whyNotBookable: 'YOU_BOOKED_IT'),
                routeFor('trip-b',
                    canBook: false, whyNotBookable: 'LOAD_CLOSED'),
                routeFor('trip-c',
                    canBook: false, whyNotBookable: 'TRIP_CLOSED'),
              ],
              booking: {'shipmentId': 'ship-7', 'bookedAtUtcMs': 1793000200000})
        ]
      });
      await tester.pumpAndSettle();
      expect(find.text('Booked'), findsOneWidget);
      expect(find.text('You booked this trip.'), findsOneWidget);
      expect(
          find.text(
              'This load is closed. You can still book this trip from Book a trip.'),
          findsOneWidget,
          reason: 'a trip with room is still an ordinary trip');
      expect(find.text('This trip is no longer taking bookings.'),
          findsOneWidget);
      expect(find.text('Not open for booking.'), findsNothing);
      await tapButton(tester, 'Open shipment');
      expect(find.text('Shipment ship-7'), findsOneWidget);
    });

    testWidgets('no loads yet says where posting starts', (tester) async {
      final server = await showShipperApp(tester, '/customer/loads');
      server.answer('/v1/posted-loads', {'loads': <Object>[]});
      await tester.pumpAndSettle();
      expect(find.text('No loads posted yet.'), findsOneWidget);
    });
  });

  test('the town box is filled from the pin, never from a one-part typed address', () {
    const point = LatLng(18.63, 73.85);
    expect(
        townToPost((
          words: 'Plot 22 MIDC Bhosari Pune',
          point: point,
          pinAddress: (
            address: 'Plot 22, MIDC, Bhosari, Pune, Maharashtra 411026, India',
            lookupFailed: false
          )
        )),
        'Pune');
    expect(
        townToPost((
          words: 'Bommasandra, Bengaluru',
          point: point,
          pinAddress: (address: null, lookupFailed: true)
        )),
        'Bengaluru',
        reason: 'no pin address: the town of typed words with more than one part');
    expect(
        townToPost((words: 'Plot 22 MIDC Bhosari Pune', point: point, pinAddress: null)),
        '',
        reason: 'one part could be a whole street address, so the shipper types the town');
  });

  test('a posted load is worded without amounts', () {
    expect(packagesWords({'kind': 'TOTAL_VOLUME', 'volume': 120, 'unit': 'CUBIC_FEET'}),
        '120 cubic feet');
    expect(
        packagesWords({
          'kind': 'SIZES',
          'count': 1,
          'length': 40.5,
          'width': 30,
          'height': 20,
          'unit': 'CENTIMETRES'
        }),
        '1 package 40.5 by 30 by 20 cm');
    expect(postedLoadRoute({'fromCity': 'Pune', 'toCity': 'Mumbai'}), 'Pune to Mumbai');
    expect(calendarDayText(DateTime.utc(2026, 11, 5)), '2026-11-05');
    expect(calendarDay('5 Nov'), isNull);
  });
}
