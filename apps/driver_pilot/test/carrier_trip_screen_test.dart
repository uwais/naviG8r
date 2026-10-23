// Over 500 lines and one file: every test drives the one trip screen through the same fake server and bookings.
// The office's trip screen and its Start sheet (ca-trip, ca-start, PR 7 of the redesign): the trip, its
// bookings, and Start only behind the sheet.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';
import 'support/eway_bill_fixtures.dart' show finalBill;
import 'support/mock_api.dart';

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Trip screen (ca-trip, ca-start)', () {
    final mehta = bookingOn('trip-a', 'mehta',
        shipper: 'Mehta Hardware',
        weightKg: 400,
        bill: {'kind': 'BILL', 'billNumber': '123456789012'});
    final sharma = bookingOn('trip-a', 'sharma',
        shipper: 'Sharma Textiles',
        weightKg: 80,
        bill: finalBill(billNumber: '123456789013'));
    final mehtaReady = {...mehta, 'ewayBill': finalBill()};

    testWidgets('names the trip, its room and its bookings as the mockup does',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: [
        tripAt('trip-a', assigned: const {'assignedTruckNumber': 'KA01AB1234'})
      ], bookings: [
        sharma
      ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      expect(find.text('TRIP'), findsOneWidget);
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Leaves 18 – 19 Oct · Medium truck'), findsOneWidget,
          reason: 'the dates are when the truck leaves, not an arrival');
      expect(find.text('Capacity remaining: 25 kg of 1,000 kg'), findsOneWidget,
          reason:
              'copy.md: Room left: [n] kg of [capacity] kg; mockup ca-trip groups thousands, "1,000 kg"');
      expect(find.text('Truck and driver'), findsOneWidget);
      expect(find.text('Bookings on this trip (1)'), findsOneWidget);
      expect(find.text('Sharma Textiles · 80 kg'), findsOneWidget);
      await tester.tap(find.text('Choose driver'));
      await tester.pumpAndSettle();
      expect(
          inSheet(find.textContaining('Bengaluru to Chennai, leaves 18 – 19 Oct')),
          findsOneWidget,
          reason: 'the assign sheet names the trip by the days it leaves');
    });

    testWidgets('Start is disabled with its reason until a driver is assigned',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: [
        tripAt('trip-a', assigned: const {'assignedTruckNumber': 'KA01AB1234'})
      ], bookings: [
        sharma
      ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Start trip'))
              .onPressed,
          isNull);
      expect(find.text('Choose a driver first. Then start on loading day.'),
          findsOneWidget,
          reason: 'copy.md Start (disabled)');
      expect(find.text('Start the trip'), findsOneWidget,
          reason:
              'copy.md Start (disabled) and ca-trip: the block has a heading');
    });

    for (final (who, driver, shares) in [
      ('an office phone', 'driver-1', false),
      ('an owner who drives the trip', 'carrier-person', true),
    ]) {
      testWidgets('a trip in transit on $who: location shared is $shares',
          (tester) async {
        final location = CountingLocation();
        GeolocatorPlatform.instance = location;
        signInWith(Server(allowed: ownerAllowed, trips: [
          tripAt('trip-a',
              status: 'IN_PROGRESS',
              assigned: {...truckAndDriver, 'assignedDriverUserId': driver})
        ], bookings: [
          sharma
        ]));
        await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
            size: const Size(800, 2000));
        expect(location.permissionChecks > 0, shares,
            reason:
                "only the phone in the truck sends its position as the truck's");
        // This phone has location refused, so the phone in the truck reads the off line in place of the shared one.
        expect(
            find.text(
                'Location is off, so shippers cannot see the truck. Turn it on in your phone settings.'),
            shares ? findsOneWidget : findsNothing,
            reason: 'whoever shares is told about it, and nobody else is');
        expect(
            find.text(
                'Shippers see your location while you are on the way and this app is open.'),
            findsNothing);
      });
    }

    testWidgets('Start opens the sheet before any request; the sheet sends it',
        (tester) async {
      final server = signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma, mehtaReady]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect((Offset.zero & view).contains(tester.getRect(start).bottomRight),
          isTrue,
          reason:
              'success criterion: primary action visible without scrolling at 360 x 800');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty,
          reason: 'decisions.md: Start only behind the confirm sheet');
      expect(find.text('Start Bengaluru to Chennai now?'), findsOneWidget);
      expect(inSheet(find.text('KA01AB1234')), findsOneWidget);
      expect(inSheet(find.text('Synthetic Driver One')), findsOneWidget);
      expect(inSheet(find.text('2 · 480 kg')), findsOneWidget,
          reason: 'Bookings row');
      expect(
          inSheet(find
              .text('Starting tells each shipper their goods are on the way.')),
          findsOneWidget);
      expect(inSheet(find.textContaining('e-way bill')), findsNothing,
          reason: 'every bill is final, so the sheet warns of none');

      await tester.tap(inSheet(find.text('Not yet')));
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty, reason: 'Not yet starts nothing');

      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(server.sent.map((request) => request.path),
          ['/v1/pilot/anchor-trips/trip-a/start']);
      expect(
          find.text(
              'Trip started. Shippers are told their goods are on the way.'),
          findsOneWidget,
          reason: 'accessibility.md: Start trip announcement');
    });

    testWidgets('a refused Start says so in plain words, never HTTP text',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma],
          refusesWrites: true));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget,
          reason: 'a refusal with no sentence of its own gets the plain one');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: never "HTTP 409: {…}"');
      expect(find.textContaining('trip_not_startable'), findsNothing,
          reason: 'no raw codes in the UI');
    });

    testWidgets(
        'Start waits for final e-way bills, with one line per booking that holds it',
        (tester) async {
      Map<String, dynamic> booked(String shipper, Map<String, dynamic>? bill) =>
          bookingOn('trip-a', shipper, shipper: shipper, weightKg: 10, bill: bill);
      final past = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      final server = signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [
            sharma,
            booked('Shipper One', null),
            booked('Shipper Two', {'kind': 'BILL', 'billNumber': '123456789014'}),
            booked('Shipper Three', finalBill(truck: 'KA02XY9999')),
            booked('Shipper Four', {...finalBill(), 'validUntilUtcMs': past}),
            booked('Shipper Five', {
              ...finalBill(),
              'check': {'result': 'PROBLEM', 'problemReason': 'NOT_FOUND', 'checkedAtUtcMs': 1}
            }),
            booked('Shipper Six', {'kind': 'NOT_NEEDED', 'notNeededReason': 'BELOW_THRESHOLD'}),
            {...booked('Shipper Seven', null), 'status': 'PENDING_CARRIER_ACCEPT'},
          ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2400));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(find.text('Waiting for e-way bill.'), findsOneWidget);
      for (final line in [
        'Shipper One has not added the e-way bill yet.',
        'Shipper Two has not added the truck to the e-way bill yet.',
        "Shipper Three's e-way bill has a different truck from this trip. Change the trip's truck, or ask Shipper Three to fix the bill.",
        "The valid-until time on Shipper Four's e-way bill has passed.",
        "NaviG8r found a problem with Shipper Five's e-way bill.",
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      for (final ready in ['Sharma Textiles:', 'Shipper Six:', 'Shipper Seven:']) {
        expect(find.textContaining(ready), findsNothing,
            reason: 'a final bill, a bill not needed, and a booking not yet accepted hold nothing');
      }
      expect(find.text('You can message the shipper from the booking.'),
          findsOneWidget,
          reason: 'one line under the list for the office');
      expect(find.text('Call your office.'), findsNothing);
      expect(find.textContaining("Truck not on Shipper"), findsNothing,
          reason: 'the old start sheet warning is gone');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty);
      expect(find.text('Start Bengaluru to Chennai now?'), findsNothing);
    });

    testWidgets(
        'a server refusal for the e-way bills shows the same lines and holds Start',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma],
          refusesWrites: true,
          refusal: {
            'error': 'eway_bill_not_ready',
            'shipments': [
              {'shipmentId': 'sharma', 'shipperName': 'Sharma Textiles', 'reason': 'expired'},
              {'shipmentId': 'other', 'shipperName': 'Shipper Two', 'reason': 'truck_differs'},
            ],
          }));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull,
          reason: 'by what the screen has, every bill is final');
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(find.text("The valid-until time on Sharma Textiles's e-way bill has passed."), findsOneWidget);
      expect(find.text("Shipper Two's e-way bill has a different truck from this trip. Change the trip's truck, or ask Shipper Two to fix the bill."),
          findsOneWidget);
      expect(find.text('Waiting for e-way bill.'), findsOneWidget);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(find.text('Something went wrong. Please try again.'), findsNothing);
      expect(find.textContaining('eway_bill_not_ready'), findsNothing);
    });

    testWidgets(
        'a refusal for the e-way bills loads the trip and its bookings again, so a truck changed elsewhere shows',
        (tester) async {
      final trips = [tripAt('trip-a', assigned: truckAndDriver)];
      final bookings = [sharma];
      signInWith(Server(
          allowed: ownerAllowed,
          trips: trips,
          bookings: bookings,
          refusesWrites: true,
          refusal: {
            'error': 'eway_bill_not_ready',
            'shipments': [
              {'shipmentId': 'sharma', 'shipperName': 'Sharma Textiles', 'reason': 'truck_differs'},
            ],
          }));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      // Another office phone changed the truck, and a booking was added, after this screen loaded.
      trips[0] = tripAt('trip-a', assigned: {
        ...truckAndDriver,
        'assignedVehicleId': 'vehicle-3',
        'assignedTruckNumber': 'KA05CD9012'
      });
      bookings.add(bookingOn('trip-a', 'lakshmi',
          shipper: 'Lakshmi Foods', weightKg: 20, status: 'PENDING_CARRIER_ACCEPT'));
      expect(find.textContaining('KA05CD9012'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('KA05CD9012'), findsWidgets,
          reason: 'the trip loaded again after the refusal');
      expect(find.textContaining('Lakshmi Foods'), findsWidgets,
          reason: 'the bookings loaded again after the refusal');
      expect(
          find.text(
              "Sharma Textiles's e-way bill has a different truck from this trip. Change the trip's truck, or ask Sharma Textiles to fix the bill."),
          findsOneWidget,
          reason: 'the server line is shown after the reload');
      expect(find.text('You can message the shipper from the booking.'),
          findsOneWidget);
    });

    testWidgets(
        'the 15-second check loads the trip too, so a truck changed elsewhere holds Start',
        (tester) async {
      final trips = [tripAt('trip-a', assigned: truckAndDriver)];
      signInWith(Server(
          allowed: ownerAllowed, trips: trips, bookings: [sharma]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      trips[0] = tripAt('trip-a', assigned: {
        ...truckAndDriver,
        'assignedVehicleId': 'vehicle-3',
        'assignedTruckNumber': 'KA05CD9012'
      });
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(
          find.text(
              "Sharma Textiles's e-way bill has a different truck from this trip. Change the trip's truck, or ask Sharma Textiles to fix the bill."),
          findsOneWidget);
    });

    testWidgets(
        'a trip with no truck says Choose a truck first, not that the truck differs',
        (tester) async {
      final noTruck = {
        'assignedDriverUserId': 'driver-1',
        'assignedDriverName': 'Synthetic Driver One',
      };
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: noTruck)],
          bookings: [
            sharma,
            bookingOn('trip-a', 'mehta', shipper: 'Mehta Hardware', weightKg: 40),
          ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(find.text('Choose a truck first.'), findsOneWidget);
      expect(find.textContaining('different truck'), findsNothing,
          reason: 'with no truck every bill would read as a different truck');
      expect(find.text('Mehta Hardware has not added the e-way bill yet.'),
          findsOneWidget,
          reason: 'what the shipper still has to do is still listed');
    });

    testWidgets(
        'a trip with no truck and every bill marked not needed can start, as on the server',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [
            tripAt('trip-a', assigned: {
              'assignedDriverUserId': 'driver-1',
              'assignedDriverName': 'Synthetic Driver One',
            })
          ],
          bookings: [
            bookingOn('trip-a', 'sharma',
                shipper: 'Sharma Textiles',
                weightKg: 80,
                bill: {'kind': 'NOT_NEEDED', 'notNeededReason': 'BELOW_THRESHOLD'}),
          ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start trip'))
              .onPressed,
          isNotNull);
      expect(find.text('Choose a truck first.'), findsNothing);
    });

    testWidgets(
        'Remind [Shipper] sends one reminder, then reads Reminder sent until the reason changes',
        (tester) async {
      final bookings = [mehta];
      final server = signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: bookings));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      final remind = find.widgetWithText(TextButton, 'Remind Mehta Hardware');
      expect(remind, findsOneWidget,
          reason: 'a quiet button next to the line for the booking that holds Start');
      await tester.tap(remind);
      await tester.pumpAndSettle();
      expect(server.sent.map((request) => request.path),
          ['/v1/pilot/anchor-trips/trip-a/shipments/mehta/eway-bill-reminder']);
      final sent = find.widgetWithText(TextButton, 'Reminder sent');
      expect(sent, findsOneWidget);
      expect(tester.widget<TextButton>(sent).onPressed, isNull,
          reason: 'one reminder per reason');
      await tester.tap(sent);
      await tester.pumpAndSettle();
      expect(server.sent, hasLength(1));

      // The shipper added the truck, but its valid-until time has passed: a new reason.
      bookings[0] = {
        ...mehta,
        'ewayBill': {
          ...finalBill(),
          'validUntilUtcMs': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch
        }
      };
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(
          find.text("The valid-until time on Mehta Hardware's e-way bill has passed."),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Remind Mehta Hardware'),
          findsOneWidget,
          reason: 'a new reason can be sent');
      expect(find.text('Reminder sent'), findsNothing);
    });

    testWidgets(
        'a reminder still unread on the server also reads Reminder sent',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [mehta],
          reminderAnswer: const {'sent': false}));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      await tester.tap(find.widgetWithText(TextButton, 'Remind Mehta Hardware'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Reminder sent'), findsOneWidget);
    });

    testWidgets(
        'with no shipper login that can get notices, the line says so instead of Reminder sent',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [mehta],
          reminderAnswer: const {'sent': false, 'why': 'no_recipient'}));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      await tester.tap(find.widgetWithText(TextButton, 'Remind Mehta Hardware'));
      await tester.pumpAndSettle();
      expect(find.text('No one at Mehta Hardware can get reminders.'),
          findsOneWidget);
      expect(find.text('Reminder sent'), findsNothing,
          reason: 'nothing reached the shipper');
      expect(find.textContaining('Remind Mehta'), findsNothing);
    });

    testWidgets(
        'each booking sends its own reminder, and loading the trip again brings Remind back',
        (tester) async {
      final kumar = bookingOn('trip-a', 'kumar',
          shipper: 'Kumar Traders', weightKg: 100);
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [mehta, kumar]));
      final served = api.dio.httpClientAdapter as MockApiAdapter;
      final mehtaAnswer = Completer<ResponseBody>();
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.path.endsWith('/mehta/eway-bill-reminder')
              ? mehtaAnswer.future
              : served.handle(request));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));

      await tester.tap(find.widgetWithText(TextButton, 'Remind Mehta Hardware'));
      await tester.pump();
      expect(find.text('Sending'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remind Kumar Traders'));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.widgetWithText(TextButton, 'Reminder sent'), findsOneWidget,
          reason: "Kumar Traders' reminder came back");
      expect(find.text('Sending'), findsOneWidget,
          reason: "Mehta Hardware's reminder is still on its way");

      mehtaAnswer.complete(jsonResponse({'sent': true}));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Reminder sent'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Remind Mehta Hardware'),
          findsOneWidget,
          reason: 'loading again asks the server, which answers if a reminder is still with the shipper');
      expect(find.widgetWithText(TextButton, 'Remind Kumar Traders'),
          findsOneWidget);
    });

    testWidgets(
        'no Remind for a login that may not assign trips, or for a different truck while the trip has no truck',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed.where((p) => p != 'trip.assign').toList(),
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [mehta]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      expect(find.text('Mehta Hardware has not added the truck to the e-way bill yet.'),
          findsOneWidget);
      expect(find.textContaining('Remind'), findsNothing);

      signInWith(Server(
          allowed: ownerAllowed,
          trips: [
            tripAt('trip-a', assigned: {
              'assignedDriverUserId': 'driver-1',
              'assignedDriverName': 'Synthetic Driver One',
            })
          ],
          bookings: [sharma]));
      await mount(tester,
          const DriverActiveTripScreen(key: ValueKey(2), tripId: 'trip-a'),
          size: const Size(800, 2000));
      expect(find.text('Choose a truck first.'), findsOneWidget);
      expect(find.textContaining('Remind'), findsNothing,
          reason: 'the office settles it by choosing a truck, so the shipper is not reminded');
    });

    testWidgets(
        'with many bookings holding Start, who to contact stays in sight under the scrolling lines',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [
            for (var i = 1; i <= 8; i++)
              bookingOn('trip-a', 'booking-$i',
                  shipper: 'Shipper $i', weightKg: 10),
          ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      final footer = find.text('You can message the shipper from the booking.');
      expect(footer, findsOneWidget);
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect((Offset.zero & view).contains(tester.getRect(footer).bottomLeft),
          isTrue);
      final before = tester.getRect(footer);
      const firstLine = 'Shipper 1 has not added the e-way bill yet.';
      final lines = find.ancestor(
          of: find.text(firstLine),
          matching: find.byType(SingleChildScrollView));
      await tester.drag(lines, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text(firstLine).hitTestable(), findsNothing,
          reason: 'the lines scrolled');
      expect(tester.getRect(footer), before,
          reason: 'the line under them did not move');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a booking waiting for the office to accept holds Start, listed first, with no Remind',
        (tester) async {
      Map<String, dynamic> waiting(String id, String shipper, bool ready) => {
            ...bookingOn('trip-a', id,
                shipper: shipper, weightKg: 10, status: 'PENDING_CARRIER_ACCEPT'),
            'readyToAccept': ready,
          };
      final server = signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [
            sharma,
            waiting('kumar', 'Kumar Traders', true),
            waiting('unpaid', 'Unpaid Co', false),
          ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(find.text("Kumar Traders's booking is waiting for you to accept."),
          findsOneWidget);
      expect(find.text('Waiting for you to accept a booking.'), findsOneWidget);
      expect(find.textContaining('Unpaid Co'), findsWidgets,
          reason: 'it is still listed with the bookings');
      expect(find.textContaining("Unpaid Co's booking"), findsNothing,
          reason: 'a booking the server says cannot be accepted yet holds nothing, as on the server');
      expect(find.textContaining('Remind'), findsNothing,
          reason: 'the office accepts it; there is nothing to remind the shipper of');
      expect(find.text('You can message the shipper from the booking.'),
          findsNothing,
          reason: 'only a booking to accept holds Start, so there is no shipper to message');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty);

      // With a bill that holds Start too, the booking to accept is listed first and the footer comes back.
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [mehta, waiting('kumar', 'Kumar Traders', true)]));
      await mount(tester,
          const DriverActiveTripScreen(key: ValueKey(2), tripId: 'trip-a'),
          size: const Size(800, 2000));
      final waitingLine =
          find.text("Kumar Traders's booking is waiting for you to accept.");
      final billLine =
          find.text('Mehta Hardware has not added the truck to the e-way bill yet.');
      expect(tester.getTopLeft(waitingLine).dy,
          lessThan(tester.getTopLeft(billLine).dy));
      expect(find.widgetWithText(TextButton, 'Remind Mehta Hardware'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Remind Kumar Traders'),
          findsNothing);
      expect(find.text('You can message the shipper from the booking.'),
          findsOneWidget);
    });

    testWidgets(
        'a server refusal naming a booking to accept shows its line and holds Start',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma],
          refusesWrites: true,
          refusal: {
            'error': 'eway_bill_not_ready',
            'shipments': [
              {'shipmentId': 'kumar', 'shipperName': 'Kumar Traders', 'reason': 'waiting_for_accept'},
            ],
          }));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(find.text("Kumar Traders's booking is waiting for you to accept."),
          findsOneWidget);
      expect(find.text('Waiting for you to accept a booking.'), findsOneWidget);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(find.textContaining('eway_bill_not_ready'), findsNothing);
    });
  });
}

/// [NoLocation] that counts how often the screen asked, which it does only when it means to share.
class CountingLocation extends NoLocation {
  int permissionChecks = 0;

  @override
  Future<LocationPermission> checkPermission() {
    permissionChecks++;
    return super.checkPermission();
  }
}
