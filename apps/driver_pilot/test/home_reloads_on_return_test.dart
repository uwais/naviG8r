// The tabs are child routes of /driver, so Home stays built under them. Owner run, 21 Oct 2026: a booking
// accepted under Bookings still showed "Accept a booking" on Home, with no Refresh to fix it on the web.
import 'dart:async';

import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_refresh_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';
import 'support/mock_api.dart';

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

  testWidgets('opened first on another tab, Home still loads again when its tab is tapped',
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
    await mountCarrierApp(tester, '/driver/shipments');
    server.bookings.single['status'] = 'BOOKED';
    await tester.tap(tab('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Accept a booking'), findsNothing,
        reason: 'review: Home took itself to be on screen from the start');
  });

  testWidgets('Home shown again during a load loads once more when that load ends',
      (tester) async {
    final server = CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-a')],
      bookings: [
        carrierBooking('trip-a', 'pending',
            shipper: 'Sharma Textiles',
            drop: 'Guindy, Chennai',
            status: 'PENDING_CARRIER_ACCEPT'),
      ],
    );
    signInToCarrierApp(server);
    Completer<void>? held;
    var heldBookingsAsked = false;
    // A held answer is the one the server had when asked, so a later change is not in it.
    api.dio.httpClientAdapter = MockApiAdapter((request) async {
      final answer = server.answer(request);
      if (held != null) {
        if (request.path == '/v1/pilot/carrier/shipments') heldBookingsAsked = true;
        await held.future;
      }
      return answer;
    });
    await mountCarrierApp(tester, '/driver');
    await tester.tap(tab('Bookings'));
    await tester.pumpAndSettle();
    held = Completer<void>();
    await tester.tap(tab('Home'));
    for (var frame = 0; frame < 50 && !heldBookingsAsked; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(heldBookingsAsked, isTrue, reason: 'Home asked for the bookings before they changed');
    server.bookings.single['status'] = 'BOOKED';
    await tester.tap(tab('Bookings'));
    await tester.pump();
    await tester.tap(tab('Home'));
    await tester.pump();
    final release = held;
    held = null;
    release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Accept a booking'), findsNothing,
        reason: 'the load that was running had the old answer; one more load has the new');
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
