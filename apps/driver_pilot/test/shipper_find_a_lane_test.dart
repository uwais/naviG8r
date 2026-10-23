// PR 4 of the redesign: the shipper Home and Book a trip (sh-home, sh-lanes-*). Names, places and
// amounts are the mockups' synthetic ones.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/notification_bell.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';
import 'support/shipper_screen_checks.dart';

void main() {
  group('Home', () {
    testWidgets('the first task that needs the shipper comes first',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'waiting',
            'status': 'PENDING_CARRIER_ACCEPT',
            'carrierDisplayName': 'Deccan Movers'
          },
          {
            'id': 'needs-bill',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways',
            'pickupAddress': 'Bommasandra, Bengaluru',
            'dropAddress': 'Guindy, Chennai',
            'assignedTruckNumber': 'KA01AB1234',
          },
        ]
      });
      await tester.pumpAndSettle();

      expect(find.text('NEEDS YOU'), findsOneWidget,
          reason: 'sh-home: the needs-you card leads Home');
      expect(find.text('Make the e-way bill'), findsOneWidget,
          reason: 'copy.md: the card names the task');
      expect(
          find.text(
              'Bommasandra, Bengaluru to Guindy, Chennai. Ravi Roadways accepted and named the truck.'),
          findsOneWidget,
          reason: 'copy.md: the card says which shipment and who did what');
      expect(find.widgetWithText(FilledButton, 'Open shipment'), findsOneWidget,
          reason: 'screens.md: the first needs-you task is the primary action');
      expect(find.widgetWithText(OutlinedButton, 'Book a trip for new goods'),
          findsOneWidget,
          reason: 'with a task waiting, Book a trip steps back');
      expect(find.text('Waiting for carrier'), findsOneWidget,
          reason: 'sh-home: Your shipments counts by status word');

      await tester.tap(find.text('Open shipment'));
      await tester.pumpAndSettle();
      expect(find.text('Shipment needs-bill'), findsOneWidget,
          reason: 'Open shipment opens the shipment the task is on');
    });

    testWidgets('with nothing to do, Book a trip is the primary action',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      expect(find.text('NEEDS YOU'), findsNothing,
          reason: 'copy.md: nothing needs you, the card is hidden');
      expect(find.widgetWithText(FilledButton, 'Book a trip for new goods'),
          findsOneWidget,
          reason: 'copy.md: Book a trip becomes primary');
      await tester.tap(find.text('Book a trip for new goods'));
      await tester.pumpAndSettle();
      expect(find.text('Book a trip'), findsWidgets,
          reason: 'the button opens Book a trip');
    });

    testWidgets(
        'Home has an Updates row and the header bell, and no Book or Sign out of its own',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer('/v1/notifications', {'notifications': [], 'unreadCount': 2});
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets, reason: 'sh-home: titled Home');
      expect(find.byType(NotificationBell), findsOneWidget,
          reason:
              'Rishabh, 20 Oct 2026: the bell is in the header on every signed-in screen, Home too');
      expect(find.text('Book a shipment'), findsNothing,
          reason: 'decisions.md: no Book with no lane');
      expect(find.text('Sign out'), findsNothing,
          reason: 'the account menu is the one place to sign out');
      expect(find.text('Book freight'), findsNothing,
          reason: 'the old Home title is gone');
      expect(find.text('Updates'), findsOneWidget,
          reason: 'copy.md: the Updates row on Home');
      expect(find.text('2 new'), findsOneWidget,
          reason: 'the row says how many updates are unread');

      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxScreen), findsOneWidget,
          reason: 'screens.md: notifications open from the Updates row');
      // Closes the inbox, whose 30 second poll would otherwise outlive the test.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Book a trip', () {
    testWidgets(
        'Browse shows lane cards with route, carrier, size and room left, unsorted',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips');
      server.answer('/anchor-trips', {
        'trips': [
          lane(),
          lane(
              id: 'lane-2',
              to: 'Hyderabad',
              carrier: 'Deccan Movers',
              reservedKg: 1000,
              status: 'FULL'),
        ]
      });
      await tester.pumpAndSettle();

      expect(find.text('Pick a trip going your way.'), findsOneWidget,
          reason: 'copy.md: lanes sub');
      expect(
          find.text(
              'All trips, not by distance. For the closest, use Search by route.'),
          findsOneWidget,
          reason:
              'copy.md: Browse is not ranked and says so; it lists full and finished lanes too (RECON gap 19), so it never says "open"');
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'copy.md: lane card route');
      expect(find.text('Ravi Roadways · Medium truck'), findsOneWidget,
          reason: 'copy.md: carrier and size on the card');
      expect(find.text('Leaves'), findsNWidgets(2),
          reason: 'the dates are when the truck leaves, never an arrival');
      expect(find.text('105 kg'), findsOneWidget,
          reason: 'room left = capacity 1000 minus booked 895');
      expect(find.text('Capacity remaining'), findsWidgets,
          reason: 'Find keeps the trip\'s own figure as Capacity remaining');
      expect(find.text('Capacity 1000 kg (895 kg reserved)'), findsNothing,
          reason: 'copy.md Formats: never capacity with reserved');
      expect(find.text('None'), findsOneWidget,
          reason: 'copy.md: a full lane says "Room left: None"');
      expect(find.text('Full'), findsOneWidget, reason: 'the status is a word');
      expect(find.text('Book this lane'), findsNothing,
          reason: 'cp-card: no buttons inside a card; the card opens');

      await tester.tap(find.text('Bengaluru to Chennai'));
      await tester.pumpAndSettle();
      expect(find.text('Book this trip'), findsOneWidget,
          reason: 'a lane card opens Book for that lane');
    });

    testWidgets(
        'Match keeps the server order and says "closest to your route first"',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
          {
            'trip': lane(id: 'lane-far', to: 'Madurai'),
            'eligibility': {'eligible': false}
          },
          {
            'trip': lane(id: 'lane-3', from: 'Hosur', to: 'Kanchipuram'),
            'eligibility': {'eligible': true}
          },
        ]
      });
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Weight')).controller!.text, '',
          reason: 'decisions.md 6: nothing preselected, no preset weight');
      expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
          '',
          reason: 'no preset pickup');

      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              '2 trips with capacity for 80 kg, closest to your route first.'),
          findsOneWidget,
          reason: 'copy.md: match result line');
      final first = tester.getTopLeft(find.text('Bengaluru to Chennai')).dy;
      final second = tester.getTopLeft(find.text('Hosur to Kanchipuram')).dy;
      expect(first < second, isTrue,
          reason: 'screens.md: the server order is kept, not re-sorted');
      expect(find.text('Bengaluru to Madurai'), findsNothing,
          reason: 'lanes failing the distance test stay hidden');

      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.tap(find.text('Bengaluru to Chennai'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Weight')).controller!.text, '80',
          reason: 'screens.md: Book starts at the searched weight');
      expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
          'Bommasandra, Bengaluru',
          reason: 'screens.md: Book starts at the searched pickup');
      expect(pinIn(tester, 'Pickup').position, const LatLng(12.8, 77.7),
          reason: 'Rishabh: Book keeps the places Match found, pins placed');
      expect(
          find.descendant(
              of: placeBox('Pickup'),
              matching: find.text('Pin: Bommasandra, Bengaluru')),
          findsOneWidget,
          reason: "Google's address for the pin comes to Book with it");
    });

    testWidgets('Match has the search-and-pin place box for pickup and drop',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await tester.pumpAndSettle();
      expect(placeBox('Pickup'), findsOneWidget,
          reason: 'Rishabh: Match gets the place box Publish uses');
      expect(placeBox('Drop'), findsOneWidget);
      expect(find.byType(GoogleMap), findsNothing,
          reason: 'a map shows once its place is found');

      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      expect(find.byType(GoogleMap), findsOneWidget,
          reason: 'the pickup map opens on its found place');
      expect(pinIn(tester, 'Pickup').draggable, isTrue,
          reason: 'the pin can be dragged to the exact spot');

      pinIn(tester, 'Pickup').onDragEnd!(const LatLng(12.85, 77.65));
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      final searched = server.requests
          .lastWhere((request) =>
              request.uri.path == '/v1/customer/eligible-anchor-trips')
          .uri
          .queryParameters;
      expect(searched['pickupLat'], '12.85',
          reason: 'the point sent is where the pin is');
    });

    testWidgets('after a pin drag, Find trips waits until the pin has its town name',
        (tester) async {
      final town = Completer<GeocodeOutcome>();
      final server = await showShipperApp(tester, '/customer/trips?tab=match',
          namePin: (_) => town.future);
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      pinIn(tester, 'Pickup').onDragEnd!(const LatLng(12.85, 77.65));
      await tester.pumpAndSettle();
      FilledButton findLanes() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Find trips'));
      expect(findLanes().onPressed, isNull,
          reason: 'review: a lane card would carry the old town name to Book with the new pin');
      expect(find.text('Updating address from pin…'), findsNWidgets(2),
          reason: 'under the place box, and under the disabled button to say why');

      town.complete(GeocodeOutcome.ok(
          const LatLng(12.85, 77.65), 'Electronic City, Bengaluru', 'Electronic City'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(server.countOf('/v1/customer/eligible-anchor-trips'), 1);
    });

    testWidgets('after a failed match, Try again also waits for a dragged pin to be named',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match',
          namePin: (_) => Completer<GeocodeOutcome>().future);
      server.answer('/v1/customer/eligible-anchor-trips', {'error': 'internal_error'}, 500);
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load trips.'), findsOneWidget);
      pinIn(tester, 'Pickup').onDragEnd!(const LatLng(12.85, 77.65));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(server.countOf('/v1/customer/eligible-anchor-trips'), 1,
          reason: 'a retry before the name came back would match under the old name');
    });

    testWidgets('Match asks for a place that has not been searched',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      await tester.pumpAndSettle();
      await tester.enterText(placeField('Pickup'), 'Bommasandra');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(find.text('Search for the pickup place.'), findsOneWidget,
          reason: 'words with no pin have no point to match');
      expect(server.countOf('/v1/customer/eligible-anchor-trips'), 0);
    });

    testWidgets('new words in a place box after its search keep the pin, and Match uses it',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(placeField('Pickup'), 'Gate 2, Hosur Road');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(find.text('Search for the pickup place.'), findsNothing,
          reason: 'owner, 21 Oct 2026: typing never drops the pin; the pin decides the place');
      final searched = server.requests
          .lastWhere((request) =>
              request.uri.path == '/v1/customer/eligible-anchor-trips')
          .uri
          .queryParameters;
      expect(searched['pickupLat'], '12.8');
    });

    testWidgets(
        'while Match waits both place boxes are read-only, and a lane card carries the places searched',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answers['/v1/customer/eligible-anchor-trips'] =
          (_) => answer.future;
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await pumpWhileWaiting(tester);
      for (final title in ['Pickup', 'Drop']) {
        expect(tester.widget<TextField>(placeField(title)).readOnly, isTrue,
            reason: 'review: the words could change under a match being sent');
        expect(pinIn(tester, title).draggable, isFalse);
      }
      answer.complete(jsonResponse({
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
        ]
      }));
      await tester.pumpAndSettle();

      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.tap(find.text('Bengaluru to Chennai'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
          'Bommasandra, Bengaluru');
      expect(pinIn(tester, 'Pickup').position, const LatLng(12.8, 77.7));
    });

    testWidgets('Match with no lanes offers a lower weight or every lane',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      server.answer('/anchor-trips', {
        'trips': [lane()]
      });
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '500');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();

      expect(find.text('No trips pass near this route with capacity for 500 kg.'),
          findsOneWidget,
          reason: 'copy.md: empty match');
      expect(
          find.text('Try less weight, or see all trips.'), findsOneWidget,
          reason: 'copy.md: empty match help');
      expect(find.widgetWithText(FilledButton, 'Change weight'), findsOneWidget,
          reason: 'sh-lanes-empty: Change weight is primary');

      await tester.tap(find.text('See all trips'));
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'See all trips switches to Browse');
    });

    testWidgets('Home, Browse and the Match form fit 360 dp at 200% text',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'a',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways'
          },
          {'id': 'b', 'status': 'PENDING_CARRIER_ACCEPT'},
        ]
      });
      server.answer('/anchor-trips', {
        'trips': [lane()]
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: Home fits at 200% text');
      await tester.tap(find.text('Book a trip').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: Browse fits at 200% text');
      await tester.tap(find.text('Search by route'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: the Match form fits at 200% text');
    });

    testWidgets('Find trips waits while a place search is out', (tester) async {
      final found = Completer<GeocodeOutcome>();
      final server = await showShipperApp(tester, '/customer/trips?tab=match',
          findPlace: (place) => place.contains('Adyar')
              ? found.future
              : findAnyPlace(place));
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.enterText(placeField('Drop'), 'Adyar, Chennai');
      await tester.tap(find.descendant(
          of: placeBox('Drop'), matching: find.byTooltip('Search for place')));
      await pumpWhileWaiting(tester);
      FilledButton findTrips() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Find trips'));
      expect(findTrips().onPressed, isNull,
          reason: 'review: the answer would move the pin after the trips were found');
      expect(find.text('Searching for the place…'), findsOneWidget,
          reason: 'a disabled button says why');
      found.complete(GeocodeOutcome.ok(const LatLng(13.0, 80.25),
          'Adyar, Chennai, Tamil Nadu 600020, India', 'Chennai'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      expect(
          server.requests
              .lastWhere((request) =>
                  request.uri.path == '/v1/customer/eligible-anchor-trips')
              .uri
              .queryParameters['dropLng'],
          '80.25',
          reason: 'the place found is the one matched');
    });

    testWidgets('after Change, each place box still shows its Pin line', (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      for (final (title, address) in [
        ('Pickup', 'Bommasandra, Bengaluru'),
        ('Drop', 'Guindy, Chennai'),
      ]) {
        expect(
            find.descendant(of: placeBox(title), matching: find.text('Pin: $address')),
            findsOneWidget,
            reason: 'review: Find did not hand the box its pin address, as Book does');
      }
    });

    testWidgets('Match asks for the address for the driver', (tester) async {
      await showShipperApp(tester, '/customer/trips?tab=match');
      await tester.pumpAndSettle();
      for (final title in ['Pickup', 'Drop']) {
        final box = tester.widget<TextField>(placeField(title)).decoration!;
        expect(box.labelText, 'Address for the driver', reason: title);
        expect(box.hintText, 'House or plot, street, area', reason: title);
      }
    });
  });

  announcementTests();
}

void announcementTests() {
  testWidgets('Browse says it is loading lanes, then how many it found',
      (tester) async {
    final announced = watchAnnouncements(tester);
    final server = await showShipperApp(tester, '/customer/trips');
    server.answer('/anchor-trips', {
      'trips': [lane(), lane(id: 'lane-2', to: 'Hyderabad')]
    });
    await tester.pumpAndSettle();
    expect(announced, containsAllInOrder(['Loading trips.', '2 trips']),
        reason:
            'accessibility.md: "Loading lanes." once, then the count when loaded');
  });
}
