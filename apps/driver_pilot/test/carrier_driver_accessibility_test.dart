// PR 10 items 3 and 4, for the carrier office and driver screens: each main screen at 200% text on a 360 dp
// phone, and what accessibility.md says a screen reader hears after loading a list or starting a trip.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';

final bills = {
  'kind': 'BILL',
  'billNumber': '341200987654',
  'validUntilUtcMs': 1760900000000,
};

List<Map<String, dynamic>> bookingsOnTwoTrips() => [
      carrierBooking('trip-moving', 'guindy',
          shipper: 'Sharma Textiles Private Limited',
          drop: 'Plot 14, Industrial Estate, Guindy, Chennai',
          bill: {...bills, 'truckNumber': 'KA01AB1234'}),
      carrierBooking('trip-moving', 'tambaram',
          shipper: 'Mehta Hardware', drop: 'Tambaram, Chennai', bill: bills),
      carrierBooking('trip-open', 'pending',
          shipper: 'Lakshmi Foods',
          drop: 'Ambattur, Chennai',
          status: 'PENDING_CARRIER_ACCEPT'),
      carrierBooking('trip-open', 'accepted',
          shipper: 'Ravi Traders', drop: 'Hosur', bill: bills),
      {
        ...carrierBooking('trip-open', 'delivered',
            shipper: 'Kumar Stores', drop: 'Vellore', status: 'PENDING_RELEASE'),
        'podAtUtcMs': 1760800000000,
        'netToCarrierPaise': 237600,
      },
    ];

List<Map<String, dynamic>> twoTrips() => [
      carrierTrip('trip-moving', status: 'IN_PROGRESS'),
      carrierTrip('trip-open', from: 'Hosur', to: 'Coimbatore'),
    ];

/// Opens each of [paths] at 360 x 800 and 200% text, and expects no overflow or other error on any.
Future<void> expectEachFits(WidgetTester tester, List<String> paths) async {
  final router = await mountCarrierApp(tester, '/', textScale: 2);
  for (final path in paths) {
    await openPath(tester, router, '/');
    await openPath(tester, router, path);
    expect(tester.takeException(), isNull,
        reason: 'brief 7: 200% text at 360 dp, $path');
  }
}

void main() {
  testWidgets('every main driver screen fits 360 dp at 200% text',
      (tester) async {
    signInToCarrierApp(CarrierServer(
        allowed: driverAllowed,
        subrole: 'DRIVER',
        trips: twoTrips(),
        bookings: bookingsOnTwoTrips()));
    await expectEachFits(tester, [
      '/driver',
      '/driver/loads',
      '/driver/trip/trip-moving/active',
      '/driver/trip/trip-open/active',
      '/driver/trip/trip-moving/eway-bills',
      '/driver/shipment/guindy',
      '/driver/shipment/pending',
      '/driver/shipment/guindy/pod',
      '/driver/profile',
    ]);
  });

  testWidgets('every main carrier office screen fits 360 dp at 200% text',
      (tester) async {
    signInToCarrierApp(CarrierServer(
        allowed: ownerAllowed,
        subrole: 'OWNER',
        trips: twoTrips(),
        bookings: bookingsOnTwoTrips()));
    await expectEachFits(tester, [
      '/driver',
      '/driver/shipments',
      '/driver/shipment/pending',
      '/driver/shipment/tambaram',
      '/driver/shipment/delivered',
      '/driver/loads',
      '/driver/trip/trip-moving/active',
      '/driver/trip/trip-open/active',
      '/driver/publish',
      '/driver/profile',
    ]);
  });

  group('A screen reader hears', () {
    testWidgets('how many bookings and trips a list holds once it loads',
        (tester) async {
      final heard = listenForAnnouncements(tester);
      signInToCarrierApp(CarrierServer(
          allowed: ownerAllowed,
          subrole: 'OWNER',
          trips: twoTrips(),
          bookings: bookingsOnTwoTrips()));
      final router = await mountCarrierApp(tester, '/driver/shipments');
      expect(heard, contains('5 bookings.'),
          reason: 'accessibility.md: "Loading bookings." once, then the count');
      await openPath(tester, router, '/driver/loads');
      expect(heard, contains('2 trips.'),
          reason: 'accessibility.md: "Loading trips." once, then the count');
    });

    testWidgets('"Trip started" in a live region after Start trip',
        (tester) async {
      signInToCarrierApp(CarrierServer(
          allowed: ownerAllowed,
          subrole: 'OWNER',
          trips: twoTrips(),
          bookings: bookingsOnTwoTrips()));
      await mountCarrierApp(tester, '/driver/trip/trip-open/active');
      await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      final started = find.text(
          'Trip started. Shippers are told their goods are on the way.');
      expect(
          find.ancestor(
              of: started,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Semantics && widget.properties.liveRegion == true)),
          findsWidgets,
          reason: 'accessibility.md: Start trip is announced');
    });
  });
}
