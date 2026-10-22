// PR 8 of the redesign: a driver's Today (dr-today), trip (dr-trip, dr-done), e-way bills (dr-ewb), confirm
// delivery (dr-confirm) and Profile (dr-profile), run through the real routes and shell.
import 'dart:io';

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart' show carrierOrganization;
import 'support/mock_api.dart';

/// 23:59 India time tomorrow, as a shipper types a bill's valid-until.
final validUntil = DateTime.parse(windowAt(1, hourInIndia: 23))
    .add(const Duration(minutes: 59));

Map<String, dynamic> billWith(String number, {String? truck}) => {
      'kind': 'BILL',
      'billNumber': number,
      if (truck != null) 'truckNumber': truck,
      'validUntilUtcMs': validUntil.millisecondsSinceEpoch,
    };

/// Three drops in Chennai; the third bill was made without the truck.
List<Map<String, dynamic>> threeDrops() => [
      carrierBooking('trip-today', 'guindy',
          shipper: 'Sharma Textiles',
          drop: 'Guindy, Chennai',
          bill: billWith('341200987654', truck: 'KA01AB1234')),
      carrierBooking('trip-today', 'ambattur',
          shipper: 'Lakshmi Foods',
          drop: 'Ambattur, Chennai',
          weightKg: 400,
          bill: billWith('271844021196', truck: 'KA01AB1234')),
      carrierBooking('trip-today', 'tambaram',
          shipper: 'Mehta Hardware',
          drop: 'Tambaram, Chennai',
          weightKg: 120,
          bill: billWith('190477315520')),
    ];

CarrierServer signInAsDriver(
        {String todayStatus = 'OPEN',
        bool withTrips = true,
        List<Map<String, dynamic>>? bookings}) =>
    signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: withTrips
          ? [
              carrierTrip('trip-today', status: todayStatus),
              carrierTrip('trip-later',
                  from: 'Chennai', to: 'Bengaluru', startsInDays: 2),
            ]
          : [],
      bookings: bookings ?? threeDrops(),
    ));

double heightOf(WidgetTester tester, Finder finder) =>
    tester.getSize(finder).height;

/// The top edge of the bottom tabs: a primary action above it is on screen without scrolling.
double tabsTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(NavigationBar)).dy;

void main() {
  group('Today (dr-today)', () {
    testWidgets(
        "shows today's trip with its facts and one 56 dp button, then the next trips",
        (tester) async {
      signInAsDriver();
      await mountCarrierApp(tester, '/driver');
      final india =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      expect(find.text('Home'), findsWidgets,
          reason: 'the screen title and the tab, the same word as the office');
      expect(
          find.text('${weekdays[india.weekday - 1]} ${formatDate(DateTime.now())}'),
          findsOneWidget,
          reason: 'copy.md: [weekday] [date] under the title');
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: "dr-today: today's trip by its route");
      expect(find.text('Ready to start'), findsOneWidget,
          reason: 'dr-today: a trip with accepted bookings, not started yet');
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'dr-today: the truck, in the mono face');
      expect(find.text('3 pickups, all in Bengaluru'), findsOneWidget,
          reason: 'the bookings still to pick up, all at the same town');
      expect(find.text('3 drops, all in Chennai'), findsOneWidget,
          reason: 'dr-today: drops');
      final open = find.widgetWithText(FilledButton, "Open today's trip");
      expect(heightOf(tester, open), NvSpace.targetDriver,
          reason: 'spec: 56 dp driver primaries');
      expect(tester.getRect(open).bottom, lessThanOrEqualTo(tabsTop(tester)),
          reason: 'spec: the primary action is visible without scrolling');
      expect(find.text('Other trips'), findsOneWidget,
          reason: 'the other trips follow, in plain words');
      expect(find.text('Chennai to Bengaluru'), findsOneWidget);
      final later = carrierTrip('trip-later', startsInDays: 2);
      expect(
          find.text(
              'Leaves ${formatDateRange(DateTime.parse(later['windowStart'] as String), DateTime.parse(later['windowEnd'] as String))} · KA01AB1234'),
          findsOneWidget,
          reason: 'dr-today: a later trip says the days it leaves and its truck');
      expect(find.text('Sign in with phone'), findsNothing,
          reason: 'the signed-in home has no sign-in or developer links');

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('Show e-way bills'), findsOneWidget,
          reason: "Open today's trip opens it");
    });

    testWidgets('says so when there is no trip today', (tester) async {
      signInAsDriver(withTrips: false, bookings: []);
      await mountCarrierApp(tester, '/driver');
      expect(find.text('No trip today.'), findsOneWidget,
          reason: 'copy.md: the empty Today');
      expect(find.text('Your office gives you trips. They show here.'),
          findsOneWidget);
    });

    testWidgets(
        'the card counts only bookings still to pick up, and names a town only when every one is there',
        (tester) async {
      signInAsDriver(bookings: [
        carrierBooking('trip-today', 'guindy',
            shipper: 'Sharma Textiles', drop: 'Guindy, Chennai'),
        carrierBooking('trip-today', 'vellore',
            shipper: 'Lakshmi Foods', drop: 'Katpadi, Vellore'),
        carrierBooking('trip-today', 'done',
            shipper: 'Mehta Hardware',
            drop: 'Tambaram, Chennai',
            status: 'DELIVERED'),
        carrierBooking('trip-today', 'released',
            shipper: 'Ravi Stores',
            drop: 'Adyar, Chennai',
            status: 'PENDING_RELEASE'),
      ]);
      await mountCarrierApp(tester, '/driver');
      expect(find.text('2 pickups, all in Bengaluru'), findsOneWidget,
          reason: 'delivered bookings are not pickups to come');
      expect(find.text('2 drops'), findsOneWidget,
          reason: 'Chennai and Vellore: no one town, and not the trip\'s To city');
      expect(find.textContaining('all in Chennai'), findsNothing);
    });

    testWidgets(
        'on the way the card counts only drops, and a town written in two cases is one town',
        (tester) async {
      signInAsDriver(todayStatus: 'IN_PROGRESS', bookings: [
        carrierBooking('trip-today', 'guindy',
            shipper: 'Sharma Textiles', drop: 'Guindy, Chennai'),
        carrierBooking('trip-today', 'ambattur',
            shipper: 'Lakshmi Foods', drop: 'Ambattur, chennai'),
      ]);
      await mountCarrierApp(tester, '/driver');
      expect(find.text('2 drops, all in Chennai'), findsOneWidget,
          reason: 'the first town as it was written');
      expect(find.textContaining('pickup'), findsNothing,
          reason: 'review: on the way, a booking does not say whether it was picked up');
    });

    testWidgets('a second trip due today is listed under Other trips, earliest first',
        (tester) async {
      signInToCarrierApp(CarrierServer(
        allowed: driverAllowed,
        subrole: 'DRIVER',
        trips: [
          carrierTrip('trip-later', from: 'Salem', to: 'Madurai', startsInDays: 3),
          carrierTrip('trip-today', from: 'Hoskote', to: 'Kolar'),
          carrierTrip('trip-also-today', from: 'Hosur', to: 'Vellore'),
        ],
      ));
      await mountCarrierApp(tester, '/driver');
      final otherTrips = find.text('Other trips');
      expect(otherTrips, findsOneWidget);
      final onCard = find.text('Hoskote to Kolar').evaluate().isNotEmpty;
      final [card, second] = onCard
          ? ['Hoskote to Kolar', 'Hosur to Vellore']
          : ['Hosur to Vellore', 'Hoskote to Kolar'];
      expect(find.text(card), findsOneWidget, reason: "one trip due today is on today's card");
      expect(find.text(second), findsOneWidget,
          reason: 'owner run: the other trip due today showed nowhere');
      final secondTop = tester.getTopLeft(find.text(second)).dy;
      expect(secondTop, greaterThan(tester.getTopLeft(otherTrips).dy));
      expect(secondTop, lessThan(tester.getTopLeft(find.text('Salem to Madurai')).dy),
          reason: 'earliest first');
    });
  });

  group('Trip (dr-trip)', () {
    testWidgets(
        'in transit: e-way bills one tap away, then the next stop and its 56 dp button, then every stop',
        (tester) async {
      signInAsDriver(todayStatus: 'IN_PROGRESS');
      await mountCarrierApp(tester, '/driver/trip/trip-today/active');
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'dr-trip: the route names the screen');
      expect(find.text('On the way'), findsWidgets,
          reason: 'dr-trip: the trip, and each stop on the truck, says In transit');
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'dr-trip: the truck beside the status');
      final bills = find.widgetWithText(OutlinedButton, 'Show e-way bills');
      expect(heightOf(tester, bills), NvSpace.targetDriver);
      expect(find.text('NEXT STOP'), findsOneWidget);
      final confirm =
          find.widgetWithText(FilledButton, 'I am here: confirm delivery');
      expect(heightOf(tester, confirm), NvSpace.targetDriver,
          reason: 'spec: 56 dp driver primaries');
      expect(tester.getRect(confirm).bottom,
          lessThanOrEqualTo(tabsTop(tester)),
          reason: 'spec: the primary action is visible without scrolling');
      expect(find.text('Guindy, Chennai'), findsOneWidget,
          reason: 'the next stop keeps the full address the driver goes to');
      expect(find.text('Directions'), findsNothing,
          reason:
              'RECON gap 32: no maps hand-off exists, so no Directions button');
      expect(find.textContaining(RegExp(r'Drop \d+ of')), findsNothing,
          reason: 'RECON gap 33: no stop order, so no "Drop 1 of 3"');
      await tester.scrollUntilVisible(find.text('All stops'), 200);
      expect(find.text('All stops'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Mehta Hardware'), 200);
      expect(find.textContaining('Mehta Hardware'), findsOneWidget,
          reason: 'every stop is listed, in the order the server sends them');
      expect(find.text('Tambaram, Chennai'), findsNothing,
          reason: 'a row under All stops shows only the town');
      expect(find.text('Chennai'), findsWidgets,
          reason: 'a row under All stops shows only the town');
      await tester.scrollUntilVisible(bills, -200);

      await tester.tap(bills);
      await tester.pumpAndSettle();
      expect(find.text('E-way bills'), findsOneWidget,
          reason: 'screens.md: "Show e-way bills" is one tap from the trip');
    });

    testWidgets(
        'before the trip starts: Start trip in a 56 dp bar above the tabs, behind the confirm sheet',
        (tester) async {
      final server = signInAsDriver();
      await mountCarrierApp(tester, '/driver/trip/trip-today/active');
      expect(find.text('Ready to start'), findsOneWidget);
      final start = find.widgetWithText(FilledButton, 'Start trip');
      expect(heightOf(tester, start), NvSpace.targetDriver);
      expect(tester.getRect(start).bottom, lessThanOrEqualTo(tabsTop(tester)),
          reason: 'spec: Start is visible without scrolling at 360 x 800');
      expect(find.text('NEXT STOP'), findsNothing,
          reason: 'the next stop shows once the trip is on the road');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.text('Start Bengaluru to Chennai now?'), findsOneWidget,
          reason: 'screens.md: the driver Start opens the same confirm sheet');
      expect(server.sent, isEmpty);
    });

    testWidgets(
        'confirming a delivery comes back saying so, with the next stop, and reads both out (dr-done)',
        (tester) async {
      final heard = listenForAnnouncements(tester);
      final semantics = tester.ensureSemantics();
      final server = signInAsDriver(todayStatus: 'IN_PROGRESS');
      await mountCarrierApp(tester, '/driver/trip/trip-today/active');
      await tester.tap(find.text('I am here: confirm delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      expect(server.sent.single.path, '/shipments/guindy/driver-pod');
      final at = formatTimeIst(DateTime.fromMillisecondsSinceEpoch(
          CarrierServer.deliveredAtUtcMs,
          isUtc: true));
      expect(
          find.bySemanticsLabel(
              'Delivery confirmed. Guindy, Chennai · Sharma Textiles · $at'),
          findsOneWidget,
          reason: 'copy.md Done: [place] · [Shipper] · [time] IST');
      expect(heard,
          contains('Delivery confirmed at Guindy, Chennai. Next stop: Ambattur, Chennai.'),
          reason: 'accessibility.md: Confirm delivery is announced with the next stop');
      expect(find.text('Ambattur, Chennai'), findsWidgets,
          reason: 'dr-done: the next stop follows');
      semantics.dispose();
    });
  });

  group('E-way bills (dr-ewb)', () {
    testWidgets(
        'each bill large in the mono face with its valid-until; a bill without the truck says to call the office',
        (tester) async {
      final semantics = tester.ensureSemantics();
      signInAsDriver(todayStatus: 'IN_PROGRESS');
      await mountCarrierApp(tester, '/driver/trip/trip-today/eway-bills',
          size: const Size(360, 1600));
      expect(find.text('Truck KA01AB1234'), findsOneWidget,
          reason: 'dr-ewb: the truck beside the title');
      final numbers = {
        for (final text
            in tester.widgetList<SelectableText>(find.byType(SelectableText)))
          text.data: text.style
      };
      for (final number in ['3412 0098 7654', '2718 4402 1196', '1904 7731 5520']) {
        expect(numbers[number], NvText.idDisplay,
            reason: 'PR 8: bill numbers in NvText.idDisplay ($number)');
      }
      expect(
          find.text(
              'Valid until ${formatDate(validUntil)}, ${formatTimeIst(validUntil)}'),
          findsNWidgets(3),
          reason: 'copy.md: Valid until [date], [time] IST');
      expect(find.text('SHARMA TEXTILES'), findsOneWidget);
      expect(
          find.text(
              'This truck is not on this bill. Call your office now. The shipper must add it to the bill.'),
          findsOneWidget,
          reason: 'dr-ewb: a missing truck is shown as a problem');
      expect(
          find.descendant(
              of: find.byType(ListView),
              matching: find.byWidgetPredicate((widget) =>
                  widget is ButtonStyleButton || widget is InkWell)),
          findsNothing,
          reason:
              'RECON gap 31: no carrier phone, so no Call button; nothing here is tappable');
      expect(find.bySemanticsLabel('E-way bill for Mehta Hardware'),
          findsOneWidget,
          reason: 'accessibility.md: each bill is a region named for its shipper');
      semantics.dispose();
    });
  });

  group('Confirm delivery (dr-confirm)', () {
    testWidgets(
        'names the drop, asks for no photo, and holds Confirm delivery in a 56 dp bar',
        (tester) async {
      signInAsDriver(todayStatus: 'IN_PROGRESS');
      await mountCarrierApp(tester, '/driver/shipment/guindy/pod');
      expect(find.text('Guindy, Chennai · Sharma Textiles · 80 kg'),
          findsOneWidget,
          reason: 'dr-confirm: which drop this is');
      expect(find.text('Confirm the goods are handed over'), findsOneWidget,
          reason: 'copy.md Confirm, step 2');
      expect(find.textContaining(RegExp('photo', caseSensitive: false)),
          findsNothing,
          reason:
              'RECON gap 30: the app takes no photo, so nothing asks for or promises one');
      final confirm = find.widgetWithText(FilledButton, 'Confirm delivery');
      expect(heightOf(tester, confirm), NvSpace.targetDriver);
      expect(tester.getRect(confirm).bottom,
          lessThanOrEqualTo(tabsTop(tester)));
    });

    testWidgets('with no signal it says so in copy.md words and stays',
        (tester) async {
      final server = signInAsDriver(todayStatus: 'IN_PROGRESS');
      await mountCarrierApp(tester, '/driver/shipment/guindy/pod');
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.method == 'POST'
              ? throw const SocketException('no signal')
              : server.answer(request));
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      expect(
          find.text('Could not confirm: no signal. Try again when you have one.'),
          findsOneWidget,
          reason: 'copy.md Offline');
      expect(find.text('Confirm the goods are handed over'), findsOneWidget,
          reason: 'the screen stays so the driver can try again');
    });
  });

  group('Profile (dr-profile)', () {
    testWidgets('a driver with no truck is told who adds one', (tester) async {
      signInToCarrierApp(CarrierServer(
          allowed: driverAllowed,
          subrole: 'DRIVER',
          extraAnswers: {
            '/v1/pilot/me': {
              'organizations': [carrierOrganization],
              'vehicles': <Object>[],
            },
          }));
      await mountCarrierApp(tester, '/driver/profile');
      expect(find.text('No truck yet. Ask your office to add your truck.'),
          findsOneWidget,
          reason: 'a driver cannot add a company truck, so the next step is to ask');
      expect(find.text('You have no trucks yet.'), findsNothing);
    });

    testWidgets('who the driver is and Sign out, with no bank, earnings or payouts',
        (tester) async {
      signInAsDriver();
      await mountCarrierApp(tester, '/driver/profile');
      for (final (label, value) in [
        ('Name', 'Prakash Naidu'),
        ('Phone', '+91 99001 22334'),
        ('Company', 'Synthetic Carrier A'),
        ('Role', 'Driver'),
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'dr-profile: $label');
        expect(find.text(value), findsWidgets, reason: 'dr-profile: $value');
      }
      final signOut = find.ancestor(
          of: find.text('Sign out'), matching: find.byType(InkWell));
      expect(heightOf(tester, signOut),
          greaterThanOrEqualTo(NvSpace.targetDriver));
      for (final owners in ['Bank details', 'Earnings and payments']) {
        expect(find.text(owners), findsNothing, reason: 'dr-profile: $owners');
      }

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(AuthorizationSession.signedIn, isFalse,
          reason: 'the row signs out, as the account menu does');
      expect(find.text('Start page'), findsOneWidget);
    });
  });

  group("A driver's booking", () {
    testWidgets(
        'shows the bill number large and Confirm delivery in a 56 dp bar',
        (tester) async {
      signInAsDriver(todayStatus: 'IN_PROGRESS');
      await mountCarrierApp(tester, '/driver/shipment/guindy');
      final number = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .singleWhere((text) => text.data == '3412 0098 7654');
      expect(number.style, NvText.idDisplay,
          reason: 'PR 8: a driver reads the number out at a check post');
      final confirm = find.widgetWithText(FilledButton, 'Confirm delivery');
      expect(heightOf(tester, confirm), NvSpace.targetDriver);
      expect(tester.getRect(confirm).bottom,
          lessThanOrEqualTo(tabsTop(tester)));
    });
  });
}
