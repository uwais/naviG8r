// Owner, 23 Oct 2026 (O3): a booking waiting for the carrier that the shipper has not finished (readyToAccept
// false) is not the office's to act on. Home gives no Accept a booking task, Accept is off with "Waiting for the
// shipper.", the Bookings list says so, and the start sheet says such bookings close at the start. Dispatchers
// read these screens, so nothing says payment. Also R3: after Start, sharing and the snackbar do not wait for
// the bookings to load again.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_bookings.dart';
import 'support/carrier_office_screens.dart'
    show Server, bookingOn, inSheet, mount, ownerAllowed, signInWith, tripAt,
        truckAndDriver;
import 'support/eway_bill_fixtures.dart' show finalBill;
import 'support/mock_api.dart';

final _paymentWords = RegExp(r'pay|paid|₹', caseSensitive: false);

Map<String, dynamic> waitingForShipper() =>
    {...pending(), 'id': 'shipment-a', 'readyToAccept': false};

/// A location service that is off, and counts the times the trip screen asks about it.
class CountingNoLocation extends GeolocatorPlatform {
  int asked = 0;
  @override
  Future<LocationPermission> checkPermission() async {
    asked++;
    return LocationPermission.deniedForever;
  }
}

void main() {
  setUp(() => GeolocatorPlatform.instance = CountingNoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('O3 a booking waiting for the shipper, office view', () {
    testWidgets('Home gives no Accept a booking task', (tester) async {
      signInAsOwner();
      answer(bookings: [waitingForShipper()], trips: [trip()]);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('Accept a booking'), findsNothing);
      expect(screenWords(tester), isNot(contains(_paymentWords)));
    });

    testWidgets('Accept is off, with Waiting for the shipper.', (tester) async {
      signInAsOwner();
      answer(bookings: [waitingForShipper()], trips: [trip()]);
      await mountRouted(tester,
          const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Waiting for the shipper.'), findsOneWidget);
      final accept = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Accept'));
      expect(accept.onPressed, isNull);
      expect(screenWords(tester), isNot(contains(_paymentWords)));
    });

    testWidgets('the Bookings list says Waiting for the shipper',
        (tester) async {
      signInAsOwner();
      answer(bookings: [waitingForShipper()], trips: [trip()]);
      await mountRouted(tester, const DriverShipmentsScreen());
      expect(find.text('Waiting for the shipper'), findsOneWidget);
      expect(find.text('Waiting for you'), findsNothing);
      expect(screenWords(tester), isNot(contains(_paymentWords)));
    });

    testWidgets('the start sheet says those bookings close at the start',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [
            bookingOn('trip-a', 'sharma',
                shipper: 'Sharma Textiles', weightKg: 80, bill: finalBill()),
            {
              ...bookingOn('trip-a', 'mehta',
                  shipper: 'Mehta Hardware',
                  weightKg: 400,
                  status: 'PENDING_CARRIER_ACCEPT'),
              'readyToAccept': false,
            },
          ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
      await tester.pumpAndSettle();
      expect(
          inSheet(find.text(
              'Bookings still waiting for the shipper close when you start.')),
          findsOneWidget);
      expect(screenWords(tester), isNot(contains(_paymentWords)));
    });
  });

  testWidgets(
      'R3 after Start, sharing starts and the snackbar shows before the bookings load again',
      (tester) async {
    final location = GeolocatorPlatform.instance as CountingNoLocation;
    final bookings = [
      bookingOn('trip-a', 'sharma',
          shipper: 'Sharma Textiles', weightKg: 80, bill: finalBill()),
    ];
    // The owner drives this trip, so this phone is the one in the truck and shares its location.
    final started = tripAt('trip-a',
        assigned: {...truckAndDriver, 'assignedDriverUserId': 'carrier-person'});
    var tripStatus = 'OPEN';
    final refetch = Completer<void>();
    signInWith(Server(
        allowed: ownerAllowed, trips: [started], bookings: bookings));
    final standard = api.dio.httpClientAdapter as MockApiAdapter;
    api.dio.httpClientAdapter = MockApiAdapter((RequestOptions request) async {
      if (request.method == 'POST' && request.path.endsWith('/start')) {
        tripStatus = 'IN_PROGRESS';
        return jsonResponse({
          'trip': {...started, 'status': tripStatus}
        });
      }
      if (request.path == '/v1/pilot/anchor-trips/trip-a') {
        return jsonResponse({
          'trip': {...started, 'status': tripStatus}
        });
      }
      if (request.path == '/v1/pilot/carrier/shipments' &&
          tripStatus == 'IN_PROGRESS') {
        await refetch.future;
      }
      return standard.handle(request);
    });
    await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
        size: const Size(800, 2000));
    await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
    await tester.pumpAndSettle();
    final askedBefore = location.asked;
    await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
        find.text('Trip started. Shippers are told their goods are on the way.'),
        findsOneWidget,
        reason: 'the snackbar does not wait for the bookings');
    expect(location.asked, greaterThan(askedBefore),
        reason: 'sharing starts without waiting for the bookings');
    refetch.complete();
    await tester.pumpAndSettle();
  });
}
