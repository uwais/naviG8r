// The office's trip screen and its Start sheet (ca-trip, ca-start, PR 7 of the redesign): the trip, its
// bookings, and Start only behind the sheet.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';
import 'support/eway_bill_fixtures.dart' show finalBill;

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
        'Shipper One: no e-way bill yet.',
        'Shipper Two: truck not on the e-way bill.',
        'Shipper Three: truck on the bill differs from the trip.',
        'Shipper Four: valid-until time on the e-way bill has passed.',
        'Shipper Five: e-way bill has a problem.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      for (final ready in ['Sharma Textiles:', 'Shipper Six:', 'Shipper Seven:']) {
        expect(find.textContaining(ready), findsNothing,
            reason: 'a final bill, a bill not needed, and a booking not yet accepted hold nothing');
      }
      expect(find.textContaining("'s e-way bill"), findsNothing,
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
      expect(find.text('Sharma Textiles: valid-until time on the e-way bill has passed.'), findsOneWidget);
      expect(find.text('Shipper Two: truck on the bill differs from the trip.'),
          findsOneWidget);
      expect(find.text('Waiting for e-way bill.'), findsOneWidget);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(find.text('Something went wrong. Please try again.'), findsNothing);
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
