// The office's four screens as a set (PR 7 of the redesign): each fits 360 dp at 200% text, and each is
// titled as its mockup is.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  testWidgets('the four screens and both sheets fit 360 dp at 200% text',
      (tester) async {
    final server = signInWith(Server(allowed: ownerAllowed, trips: [
      tripAt('trip-a', assigned: truckAndDriver)
    ], bookings: [
      bookingOn('trip-a', 'mehta',
          shipper: 'Mehta Hardware',
          weightKg: 400,
          bill: {'kind': 'BILL', 'billNumber': '123456789012'})
    ]));
    Future<void> expectNoOverflow(String where) async {
      expect(tester.takeException(), isNull,
          reason: 'brief 7: 200% text, $where');
    }

    await mount(tester, const DriverLoadsScreen(key: ValueKey('trips')),
        textScale: 2);
    await expectNoOverflow('Trips');
    await mount(tester,
        const DriverActiveTripScreen(key: ValueKey('trip'), tripId: 'trip-a'),
        textScale: 2);
    await expectNoOverflow('Trip');
    await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
    await tester.pumpAndSettle();
    await expectNoOverflow('Start sheet');
    expect(server.sent, isEmpty);
    await tester.ensureVisible(find.text('Not yet'));
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Assign driver'), 200);
    await tester.tap(find.text('Assign driver'));
    await tester.pumpAndSettle();
    await expectNoOverflow('Assign sheet');
    await mount(tester, const DriverPublishTripScreen(key: ValueKey('publish')),
        textScale: 2);
    await expectNoOverflow('Publish');
    await mount(tester, const DriverProfileScreen(key: ValueKey('profile')),
        textScale: 2);
    await expectNoOverflow('Profile');
  });

  test(
      'screen titles: the office trip names itself, Publish and Company as in the mockups',
      () {
    expect(driverShellTitle('/driver/trip/t/active'), '',
        reason: 'ca-trip: TRIP over the route, no shell title');
    expect(driverShellTitle('/driver/trip/t/active', forDriver: true), '',
        reason: 'PR 8, dr-trip: the route names the driver trip screen');
    expect(driverShellTitle('/driver/trip/t/eway-bills', forDriver: true), '',
        reason: 'PR 8, dr-ewb: "E-way bills" beside the truck names the screen');
    expect(driverShellTitle('/driver/publish'), 'Publish a trip');
    expect(driverShellTitle('/driver/profile'), 'Company');
    expect(driverShellTitle('/driver/profile', forDriver: true), 'Profile');
  });
}
