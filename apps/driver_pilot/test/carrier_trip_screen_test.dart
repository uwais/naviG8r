// The office's trip screen and its Start sheet (ca-trip, ca-start, PR 7 of the redesign): the trip, its
// bookings, and Start only behind the sheet.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';

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
        bill: {
          'kind': 'BILL',
          'billNumber': '123456789013',
          'truckNumber': 'KA01AB1234'
        });

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
                'Shippers see your location while this app is open.'),
            findsNothing);
      });
    }

    testWidgets('Start opens the sheet before any request; the sheet sends it',
        (tester) async {
      final server = signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma, mehta]));
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
        "the missing-truck warning shows only when a booking's bill lacks the truck",
        (tester) async {
      for (final withMissingTruck in [true, false]) {
        signInWith(Server(
            allowed: ownerAllowed,
            trips: [tripAt('trip-a', assigned: truckAndDriver)],
            bookings: [sharma, if (withMissingTruck) mehta]));
        await mount(
            tester,
            DriverActiveTripScreen(
                key: ValueKey(withMissingTruck), tripId: 'trip-a'));
        await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
        await tester.pumpAndSettle();
        const warning =
            "Truck not on Mehta Hardware's e-way bill.";
        expect(find.text(warning),
            withMissingTruck ? findsOneWidget : findsNothing,
            reason: 'decisions.md: warning only when true');
        expect(
            find.text(
                'The goods cannot move until Mehta Hardware adds it.'),
            withMissingTruck ? findsOneWidget : findsNothing,
            reason: 'the carrier is told who adds it, not asked to');
        expect(find.text('Add the truck first'), findsNothing,
            reason: 'owner decision 18 Oct 2026: the shipper adds the truck');
        expect(inSheet(find.textContaining('Sharma Textiles')), findsNothing,
            reason: "Sharma's bill has the truck");
        await tester.tap(find.text('Not yet'));
        await tester.pumpAndSettle();
      }
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
