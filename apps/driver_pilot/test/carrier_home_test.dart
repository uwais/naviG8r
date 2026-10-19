// The office Home (ca-home, PR 6 of the redesign): which task comes first, and the trips on the road.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/carrier_office_bookings.dart';

void main() {
  group('The office Home', () {
    testWidgets(
        'puts the first task first, with its button, then the others and the trips on the road',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        pending(),
        truckMissing(),
      ], trips: [
        trip(),
        trip(id: 'trip-b', from: 'Hosur', to: 'Coimbatore', reservedKg: 400),
        trip(
            id: 'trip-c',
            from: 'Bengaluru',
            to: 'Mysuru',
            status: 'IN_PROGRESS',
            truck: 'KA 01 AB 5678',
            driverName: 'Suresh Kumar'),
      ]);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('NEEDS YOU'), findsOneWidget,
          reason: 'ca-home: the first task is a NEEDS YOU card');
      expect(find.text('Accept a booking'), findsOneWidget,
          reason: 'accepting blocks everything after it, so it comes first');
      expect(
          find.text(
              'Synthetic Shipper A, 120 kg, on your Bengaluru to Chennai trip, leaves 18 – 19 Oct.'),
          findsOneWidget,
          reason:
              'copy.md: [Shipper], [weight], on your [route] trip, leaves [dates]. The dates are when the truck leaves');
      expect(
          find.widgetWithText(FilledButton, 'Review booking'), findsOneWidget,
          reason: 'the first task has the one primary button');
      expect(find.text('Add the truck to an e-way bill'), findsNothing,
          reason:
              'owner decision 18 Oct 2026: the shipper adds the truck, so it is never the carrier\'s task');
      expect(find.text('Hosur to Coimbatore · Lakshmi Foods'), findsNothing,
          reason: 'no task row for the missing truck');
      expect(find.text('Assign a driver'), findsNWidgets(2),
          reason: 'both booked trips wait for a driver');
      expect(find.text('Hosur to Coimbatore · Leaves 18 – 19 Oct'),
          findsOneWidget,
          reason: 'the task says the days the trip leaves');
      expect(find.text('Today'), findsOneWidget,
          reason: 'ca-home: the trips on the road');
      expect(find.text('Bengaluru to Mysuru'), findsOneWidget);
      expect(find.text('In transit'), findsOneWidget);
      expect(
          find.text('KA01AB5678 · Suresh Kumar · 0 bookings'), findsOneWidget,
          reason:
              'truck in the portal form, the driver, and the bookings on it');
      for (final link in [
        'Sign in with phone',
        'Register as new carrier',
        'Developer lab',
        'Sign out',
      ]) {
        expect(find.text(link), findsNothing,
            reason:
                'copy.md: the signed-in home has no sign-in, register, developer or sign-out links ($link)');
      }
      await tester.tap(find.text('Review booking'));
      await tester.pumpAndSettle();
      expect(find.text('Booking page shipment-a'), findsOneWidget,
          reason: 'the task opens the booking');
    });

    testWidgets(
        'asks to start a trip whose day has come, once a booking is accepted and the driver and truck are set',
        (tester) async {
      final now = DateTime.now().toUtc();
      final today = now.toIso8601String();
      final tomorrow = now.add(const Duration(days: 1)).toIso8601String();
      Map<String, dynamic> readyTrip(String id, String to, String start) => {
            ...trip(
                id: id,
                to: to,
                truck: 'KA01AB1234',
                driverName: 'Prakash Naidu'),
            'windowStart': start,
          };
      final bookings = [
        {...shipmentOnTripA(), 'anchorTripId': 'trip-today'},
        {...shipmentOnTripA(), 'id': 'shipment-t', 'anchorTripId': 'trip-later'},
        {
          ...shipmentOnTripA(status: 'PENDING_CARRIER_ACCEPT'),
          'id': 'shipment-p',
          'anchorTripId': 'trip-unaccepted'
        },
      ];
      final trips = [
        readyTrip('trip-today', 'Chennai', today),
        readyTrip('trip-later', 'Mysuru', tomorrow),
        readyTrip('trip-unaccepted', 'Hosur', today),
      ];

      signInAsCarrierOwner(alsoAllowed: ['load.status_update']);
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('Nothing needs you right now.'), findsNothing,
          reason: 'owner run: Home said this while a trip was ready to start');
      expect(find.text('Start a trip'), findsOneWidget,
          reason: 'only the trip whose day has come and has an accepted booking');
      expect(
          find.text(
              'Bengaluru to Chennai · Leaves ${formatDateRange(DateTime.parse(today), DateTime.parse(tripWindowEnd))}'),
          findsOneWidget,
          reason: 'names the trip and the days it can leave');
      await tester.tap(find.widgetWithText(FilledButton, 'Open trip'));
      await tester.pumpAndSettle();
      expect(find.text('Trip page trip-today'), findsOneWidget,
          reason: 'Start is on the trip screen, behind its confirm sheet');

      signInAsCarrierOwner(
          alsoAllowed: ['load.status_update', 'carrier.offer_accept']);
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen(key: ValueKey(2)));
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('NEEDS YOU'), matching: find.byType(Column)),
              matching: find.text('Accept a booking')),
          findsOneWidget,
          reason: 'accepting comes first; starting comes after');
      expect(find.text('Start a trip'), findsOneWidget);

      signInAsCarrierOwner();
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen(key: ValueKey(3)));
      expect(find.text('Start a trip'), findsNothing,
          reason: 'no task for a login that may not start trips');

      signInAsCarrierOwner(alsoAllowed: ['load.status_update']);
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen(key: ValueKey(4)),
          size: const Size(360, 800), textScale: 2);
      expect(find.text('Start a trip'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'spec: works at 360 dp and 200% text');
    });

    testWidgets('says when nothing needs the office', (tester) async {
      signInAsOwner();
      answer(bookings: []);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('Nothing needs you right now.'), findsOneWidget,
          reason: 'an empty Home says so instead of showing nothing');
      expect(find.text('NEEDS YOU'), findsNothing);
    });

    testWidgets('a driver keeps their own home', (tester) async {
      signInAsCarrierLogin(office: false);
      answer(bookings: [pending()]);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('NEEDS YOU'), findsNothing,
          reason:
              'drivers do not accept bookings from Home; their Today is PR 8');
    });
  });
}
