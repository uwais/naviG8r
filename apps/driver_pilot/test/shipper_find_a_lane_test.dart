// PR 4 of the redesign: the shipper Home and Find a lane (sh-home, sh-lanes-*). Names, places and
// amounts are the mockups' synthetic ones.
import 'dart:async';

import 'package:dio/dio.dart';
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
      expect(find.widgetWithText(OutlinedButton, 'Find a lane for new goods'),
          findsOneWidget,
          reason: 'with a task waiting, Find a lane steps back');
      expect(find.text('Waiting for carrier'), findsOneWidget,
          reason: 'sh-home: Your shipments counts by status word');

      await tester.tap(find.text('Open shipment'));
      await tester.pumpAndSettle();
      expect(find.text('Shipment needs-bill'), findsOneWidget,
          reason: 'Open shipment opens the shipment the task is on');
    });

    testWidgets('with nothing to do, Find a lane is the primary action',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      expect(find.text('NEEDS YOU'), findsNothing,
          reason: 'copy.md: nothing needs you, the card is hidden');
      expect(find.widgetWithText(FilledButton, 'Find a lane for new goods'),
          findsOneWidget,
          reason: 'copy.md: Find a lane becomes primary');
      await tester.tap(find.text('Find a lane for new goods'));
      await tester.pumpAndSettle();
      expect(find.text('Find a lane'), findsWidgets,
          reason: 'the button opens Find a lane');
    });

    testWidgets(
        'Home has an Updates row instead of a bell, and no Book or Sign out of its own',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer(
          '/v1/notifications/shipments', {'shipments': [], 'unreadCount': 2});
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets, reason: 'sh-home: titled Home');
      expect(find.byType(NotificationBell), findsNothing,
          reason: 'screens.md: the Updates row replaces the bell');
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

  group('Find a lane', () {
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

      expect(find.text('Pick a lane going your way.'), findsOneWidget,
          reason: 'copy.md: lanes sub');
      expect(
          find.text(
              'Every lane, whatever its status, not sorted by distance. To see the closest to your route first, use Match my route.'),
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
      expect(find.text('Capacity 1000 kg (895 kg reserved)'), findsNothing,
          reason: 'copy.md Formats: never capacity with reserved');
      expect(find.text('None'), findsOneWidget,
          reason: 'copy.md: a full lane says "Room left: None"');
      expect(find.text('Full'), findsOneWidget, reason: 'the status is a word');
      expect(find.text('Book this lane'), findsNothing,
          reason: 'cp-card: no buttons inside a card; the card opens');

      await tester.tap(find.text('Bengaluru to Chennai'));
      await tester.pumpAndSettle();
      expect(find.text('Book space'), findsOneWidget,
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
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              '2 lanes with room for 80 kg, closest to your route first.'),
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
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();
      final searched = server.requests
          .lastWhere((request) =>
              request.uri.path == '/v1/customer/eligible-anchor-trips')
          .uri
          .queryParameters;
      expect(searched['pickupLat'], '12.85',
          reason: 'the point sent is where the pin is');
    });

    testWidgets('Match asks for a place that has not been searched',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      await tester.pumpAndSettle();
      await tester.enterText(placeField('Pickup'), 'Bommasandra');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();
      expect(find.text('Search for the pickup place.'), findsOneWidget,
          reason: 'words with no pin have no point to match');
      expect(server.countOf('/v1/customer/eligible-anchor-trips'), 0);
    });

    testWidgets('Match asks again for a place whose words changed after its search',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(placeField('Pickup'), 'Hosur');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();
      expect(find.text('Search for the pickup place.'), findsOneWidget,
          reason:
              'reviewer: the match used the Bommasandra pin under the name Hosur');
      expect(server.countOf('/v1/customer/eligible-anchor-trips'), 0);
    });

    testWidgets(
        'a lane card carries the place names searched, even when the words change while Match waits',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answers['/v1/customer/eligible-anchor-trips'] =
          (_) => answer.future;
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find matching lanes'));
      await pumpWhileWaiting(tester);
      await tester.enterText(placeField('Pickup'), 'Hosur');
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
          'Bommasandra, Bengaluru',
          reason: 'review: the Bommasandra pin went to Book under the name Hosur');
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
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();

      expect(find.text('No lanes pass near this route with room for 500 kg.'),
          findsOneWidget,
          reason: 'copy.md: empty match');
      expect(
          find.text('Try a lower weight, or browse all lanes.'), findsOneWidget,
          reason: 'copy.md: empty match help');
      expect(find.widgetWithText(FilledButton, 'Change weight'), findsOneWidget,
          reason: 'sh-lanes-empty: Change weight is primary');

      await tester.tap(find.text('Browse all lanes'));
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'Browse all lanes switches to Browse');
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
    expect(announced, containsAllInOrder(['Loading lanes.', '2 lanes']),
        reason:
            'accessibility.md: "Loading lanes." once, then the count when loaded');
  });
}
