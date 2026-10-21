// The office's Trips list (ca-trips, PR 7 of the redesign): what each card shows, and that the card is its
// only tap target.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Trips list (ca-trips)', () {
    final trips = [
      tripAt('trip-open',
          assigned: const {'assignedTruckNumber': 'KA01AB1234'}),
      tripAt('trip-full',
          status: 'FULL',
          reservedKg: 1000,
          assigned: truckAndDriver,
          startDay: 19),
      tripAt('trip-new', reservedKg: 0, startDay: 20),
      tripAt('trip-moving', status: 'IN_PROGRESS', assigned: truckAndDriver),
    ];
    final bookings = [
      for (final id in ['a', 'b', 'c'])
        bookingOn('trip-open', id, shipper: 'Shipper $id', weightKg: 100),
    ];

    testWidgets('cards show the trip as the mockup does, under Open first',
        (tester) async {
      signInWith(
          Server(allowed: ownerAllowed, trips: trips, bookings: bookings));
      await mount(tester, const DriverLoadsScreen());
      for (final chip in ['Open', 'On the way', 'Done']) {
        expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget,
            reason: 'copy.md Trips list chips');
      }
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Open'))
              .selected,
          isTrue,
          reason: 'ca-trips opens on Open');
      expect(find.text('Bengaluru to Chennai'), findsNWidgets(3),
          reason: 'the open and full trips, not the one in transit');
      expect(find.text('18 – 19 Oct'), findsOneWidget, reason: 'Leaves fact');
      expect(find.text('Leaves'), findsNWidgets(3),
          reason: 'each card says the days the truck leaves, not an arrival');
      expect(find.text('25 kg'), findsOneWidget,
          reason: 'Room left 1000 - 975');
      expect(find.text('None'), findsOneWidget,
          reason: 'a full trip has no room');
      expect(find.text('3'), findsOneWidget, reason: 'Bookings count');
      expect(find.text('KA01AB1234 · No driver yet'), findsOneWidget);
      expect(find.text('KA01AB1234 · Synthetic Driver One'), findsOneWidget);
      expect(find.text('You choose the truck when you accept the first booking'),
          findsOneWidget,
          reason: 'copy.md: an open trip with no truck yet');
      expect(find.text('Full'), findsOneWidget, reason: 'status word');

      await tester.tap(find.widgetWithText(ChoiceChip, 'On the way'));
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
    });

    testWidgets(
        'trip cards contain no Start or View: the whole card opens the trip',
        (tester) async {
      signInWith(
          Server(allowed: ownerAllowed, trips: trips, bookings: bookings));
      await mount(tester, const DriverLoadsScreen());
      for (final chip in ['Open', 'On the way', 'Done']) {
        await tester.tap(find.widgetWithText(ChoiceChip, chip));
        await tester.pumpAndSettle();
        expect(find.textContaining('Start'), findsNothing,
            reason:
                'spec/decisions.md: a slip on the list started trips ($chip)');
        expect(find.textContaining('View'), findsNothing, reason: chip);
        expect(find.byType(FilledButton), findsNothing, reason: chip);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25 kg'));
      await tester.pumpAndSettle();
      expect(find.text('Opened /driver/trip/trip-open/active'), findsOneWidget,
          reason: 'the card is its only tap target, and it opens the trip');
    });
  });
}
