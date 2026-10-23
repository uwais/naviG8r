// The office's Home, Bookings list and booking screens at 360 dp wide and 200% text (PR 6 of the redesign).
import 'package:driver_pilot/driver_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_office_bookings.dart';

void main() {
  group('At 360 dp wide and 200% text nothing overflows', () {
    final bookings = [
      {
        ...pending(),
        'customerOrgName':
            'Synthetic Shipper With A Very Long Registered Business Name Private Limited',
        'ewayBill': {'kind': 'NOT_NEEDED', 'notNeededReason': 'GOODS_EXEMPT'},
      },
      truckMissing(),
      delivered(netToCarrierPaise: 237600),
    ];
    final trips = [
      trip(),
      trip(id: 'trip-b', from: 'Hosur', to: 'Coimbatore'),
      trip(
          id: 'trip-c',
          status: 'IN_PROGRESS',
          truck: 'KA01AB5678',
          driverName: 'Suresh Kumar'),
    ];
    for (final (name, screen) in [
      ('Home', const DriverWelcomeScreen()),
      ('Bookings', const DriverShipmentsScreen()),
      (
        'a booking awaiting acceptance',
        const DriverShipmentDetailScreen(shipmentId: 'shipment-a')
      ),
      (
        'a booking missing its truck',
        const DriverShipmentDetailScreen(shipmentId: 'shipment-b')
      ),
    ]) {
      testWidgets(name, (tester) async {
        signInAsOwner();
        answer(bookings: bookings, trips: trips);
        await mountRouted(tester, screen,
            size: const Size(360, 800), textScale: 2);
        expect(tester.takeException(), isNull,
            reason: 'spec: works at 360 dp and 200% text ($name)');
      });
    }
  });
}
