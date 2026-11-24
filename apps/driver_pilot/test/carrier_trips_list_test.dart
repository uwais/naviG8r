// The office's Trips list (ca-trips, PR 7 of the redesign): what each card shows, that the card is its
// only tap target, where past trips go, and the town search.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:driver_pilot/ui/tokens.dart';
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
      // Tall enough that the lazy list builds all three open cards under the search box and Add trip button.
      await mount(tester, const DriverLoadsScreen(),
          size: const Size(360, 1400));
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

  group('Trips whose last leaving day has passed', () {
    // The server marks the trip; the app does no date sums of its own.
    Map<String, dynamic> ended(Map<String, dynamic> trip) =>
        {...trip, 'leaveWindowEnded': true};
    final trips = [
      tripAt('trip-bookable', reservedKg: 0, startDay: 20),
      ended(tripAt('trip-past', reservedKg: 0, startDay: 10)),
      ended(tripAt('trip-ended-booked', reservedKg: 100, startDay: 12)),
      tripAt('trip-done', status: 'COMPLETED', startDay: 2),
    ];

    testWidgets(
        'an open trip with nothing booked leaves Open for Done, as Past; one with bookings stays under Open',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: trips));
      await mount(tester, const DriverLoadsScreen(),
          size: const Size(360, 1400));
      expect(find.text('20 – 21 Oct'), findsOneWidget,
          reason: 'a trip shippers can still book');
      expect(find.text('12 – 13 Oct'), findsOneWidget,
          reason: 'a trip with a booking still has to run');
      expect(find.text('10 – 11 Oct'), findsNothing,
          reason: 'Open leaves out a trip nobody can book any more');
      expect(find.text('Past'), findsNothing);
      expect(find.text('Show past trips'), findsNothing,
          reason: 'the switch is for Done, where past trips go');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('2 – 3 Oct'), findsOneWidget,
          reason: 'finished trips stay in Done');
      expect(find.text('10 – 11 Oct'), findsNothing,
          reason: 'past trips are hidden until asked for');
      expect(
          tester
              .widget<SwitchListTile>(
                  find.widgetWithText(SwitchListTile, 'Show past trips'))
              .value,
          isFalse);

      await tester.tap(find.text('Show past trips'));
      await tester.pumpAndSettle();
      expect(find.text('10 – 11 Oct'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget, reason: 'its status word');
      expect(find.text('2 – 3 Oct'), findsOneWidget);
    });

    testWidgets(
        'with only past trips in Done, the empty line says they are hidden and how to see them',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [ended(tripAt('trip-past', reservedKg: 0, startDay: 10))]));
      await mount(tester, const DriverLoadsScreen());
      await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Past trips are hidden. Turn on Show past trips to see them.'),
          findsOneWidget);
    });
  });

  group('Search towns on Trips', () {
    final trips = [
      tripAt('trip-chennai', reservedKg: 0, startDay: 18),
      {
        ...tripAt('trip-mysuru', reservedKg: 0, startDay: 20),
        'originCity': 'Mysuru',
        'destCity': 'Hassan',
      },
    ];

    testWidgets(
        'matches the town a trip leaves from or goes to, in any case, and says when none match',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: trips));
      await mount(tester, const DriverLoadsScreen(),
          size: const Size(360, 1400));
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
      expect(find.text('Mysuru to Hassan'), findsOneWidget);

      final search = find.descendant(
          of: find.widgetWithText(NvField, 'Search towns'),
          matching: find.byType(TextField));
      await tester.enterText(search, 'hass');
      await tester.pumpAndSettle();
      expect(find.text('Mysuru to Hassan'), findsOneWidget,
          reason: 'the town it goes to');
      expect(find.text('Bengaluru to Chennai'), findsNothing);

      await tester.enterText(search, 'BENGALURU');
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'the town it leaves from');
      expect(find.text('Mysuru to Hassan'), findsNothing);

      await tester.enterText(search, 'Pune');
      await tester.pumpAndSettle();
      expect(find.text('No trips match these towns.'), findsOneWidget);
      expect(find.text('Check the town name, or look under another group.'),
          findsOneWidget);
    });

    testWidgets(
        'on a 360 x 640 phone at 200% text the search, the switch and the cards fit, with 48 dp targets',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: [
        ...trips,
        {...tripAt('trip-past', reservedKg: 0, startDay: 10), 'leaveWindowEnded': true},
      ]));
      await mount(tester, const DriverLoadsScreen(),
          size: const Size(360, 640), textScale: 2);
      expect(tester.takeException(), isNull);
      final search = find.descendant(
          of: find.widgetWithText(NvField, 'Search towns'),
          matching: find.byType(TextField));
      expect(tester.getSize(search).height,
          greaterThanOrEqualTo(NvSpace.targetMin));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final toggle = find.widgetWithText(SwitchListTile, 'Show past trips');
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(toggle).height,
          greaterThanOrEqualTo(NvSpace.targetMin));
      expect(tester.getSize(toggle).width, lessThanOrEqualTo(360));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Past'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Past'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
