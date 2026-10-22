// The tabs are child routes of /driver, so Home stays built under them. Owner run, 21 Oct 2026: a booking
// accepted under Bookings still showed "Accept a booking" on Home, with no Refresh to fix it on the web.
import 'package:driver_pilot/ui/nv_refresh_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';

Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('a booking accepted under Bookings is gone from Home when the Home tab is tapped',
      (tester) async {
    final server = signInToCarrierApp(CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-a')],
      bookings: [
        carrierBooking('trip-a', 'pending',
            shipper: 'Sharma Textiles',
            drop: 'Guindy, Chennai',
            status: 'PENDING_CARRIER_ACCEPT'),
      ],
    ));
    await mountCarrierApp(tester, '/driver');
    expect(find.text('Accept a booking'), findsOneWidget);

    await tester.tap(tab('Bookings'));
    await tester.pumpAndSettle();
    server.bookings.single['status'] = 'BOOKED';
    await tester.tap(tab('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Accept a booking'), findsNothing,
        reason: 'Home loads again when it is shown again');
  });

  testWidgets("the office's Home has a Refresh button", (tester) async {
    final server = signInToCarrierApp(CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-a')],
      bookings: [
        carrierBooking('trip-a', 'pending',
            shipper: 'Sharma Textiles',
            drop: 'Guindy, Chennai',
            status: 'PENDING_CARRIER_ACCEPT'),
      ],
    ));
    await mountCarrierApp(tester, '/driver');
    expect(find.text('Accept a booking'), findsOneWidget);
    server.bookings.single['status'] = 'BOOKED';
    await tester.tap(find.byType(NvRefreshButton));
    await tester.pumpAndSettle();
    expect(find.text('Accept a booking'), findsNothing,
        reason: 'a web browser cannot pull down to refresh');
  });

  testWidgets("a driver's Home loads again when the Home tab is tapped", (tester) async {
    final server = signInToCarrierApp(CarrierServer(
        allowed: driverAllowed, subrole: 'DRIVER', trips: [carrierTrip('trip-a', startsInDays: 2)]));
    await mountCarrierApp(tester, '/driver');
    expect(find.text('No trip today.'), findsOneWidget);

    await tester.tap(tab('Trips'));
    await tester.pumpAndSettle();
    server.trips.add(carrierTrip('trip-b', from: 'Hosur', to: 'Salem'));
    await tester.tap(tab('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Hosur to Salem'), findsOneWidget,
        reason: 'the trip given while the driver was on Trips shows');
  });
}
