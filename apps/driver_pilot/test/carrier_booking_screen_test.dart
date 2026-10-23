// The office's booking screen (ca-booking-new, -truck, -deliver, -owner, -dispatcher; PR 6 of the
// redesign): each step, and who sees the amount.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/plain_error_sentence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/carrier_office_bookings.dart';

/// A dispatcher holds payment.read and is sent the amount, but is not the owner (no bank_account.create_token).
void signInAsDispatcher() {
  signInAsCarrierLogin(office: true, alsoAllowed: officeWork);
  AuthorizationSession.principal = {
    ...AuthorizationSession.principal!,
    'subrole': 'DISPATCHER',
  };
}

Future<void> mountBooking(WidgetTester tester,
    {Size size = const Size(800, 3000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A 72 dp bar and 80 dp of tabs stand in for the shell's header and bottom tabs.
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(
          appBar: PreferredSize(
              preferredSize: Size.fromHeight(72), child: SizedBox()),
          body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'),
          bottomNavigationBar: SizedBox(height: 80))));
  await tester.pumpAndSettle();
}

void main() {
  test('an unpaid booking is refused in words, never "Something went wrong"',
      () {
    api = Api('http://test');
    DioException refusal(String code) => DioException(
          requestOptions: RequestOptions(path: '/v1/pilot/carrier/shipments'),
          response: Response(
            requestOptions: RequestOptions(path: '/v1/pilot/carrier/shipments'),
            statusCode: 400,
            data: {'error': code},
          ),
        );
    expect(plainErrorSentence(refusal('checkout_not_completed_for_accept')),
        'The shipper has not finished paying for this booking yet. You can accept it once they do.',
        reason:
            'an unpaid booking shows as waiting for the office; trying again cannot work until the shipper pays');
    expect(plainErrorSentence(refusal('checkout_not_completed_for_pod')),
        'This booking is not ready for delivery yet. Ask your office.',
        reason: 'a driver can meet this, so it says nothing about payment');
  });

  group('The booking screen', () {
    test('its title is never "Proof of delivery" before delivery', () {
      expect(driverShellTitle('/driver/shipment/shipment-a'),
          isNot('Proof of delivery'),
          reason:
              'PR 6: the booking screen was titled "Proof of delivery" from the start');
    });

    for (final (state, booking) in [
      ('awaiting acceptance', pending()),
      ('accepted', truckMissing()),
      ('in transit', shipmentOnTripA()),
    ]) {
      testWidgets('says BOOKING and the shipper, $state', (tester) async {
        signInAsOwner();
        answer(bookings: [
          {...booking, 'id': 'shipment-a'}
        ], trips: [
          trip(status: state == 'in transit' ? 'IN_PROGRESS' : 'OPEN'),
          trip(id: 'trip-b')
        ]);
        await mountBooking(tester);
        expect(find.text('BOOKING'), findsOneWidget,
            reason: 'copy.md: BOOKING · [Shipper]');
        expect(find.text(booking['customerOrgName'] as String), findsWidgets);
        expect(find.textContaining('Proof of delivery'), findsNothing,
            reason: 'PR 6: never "Proof of delivery" before delivery');
      });
    }

    testWidgets(
        'before acceptance shows the facts, the room left and Accept without scrolling at 360 x 800',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        {
          ...pending(),
          'ewayBill': {'kind': 'NOT_NEEDED', 'notNeededReason': 'GOODS_EXEMPT'}
        }
      ], trips: [
        trip()
      ]);
      await mountBooking(tester, size: const Size(360, 800));
      expect(find.text('Waiting for you to accept'), findsOneWidget);
      for (final fact in ['Pickup', 'Drop', 'Weight', 'E-way bill']) {
        expect(find.text(fact), findsOneWidget,
            reason: 'ca-booking-new fact: $fact');
      }
      expect(find.text('Peenya, Bengaluru'), findsOneWidget,
          reason: 'the booking screen keeps the full pickup address; lists show the town');
      expect(find.text('Not needed (shipper said so).'), findsOneWidget,
          reason: "ca-booking-new shows the shipper's e-way bill answer");
      expect(
          find.text(
              'Your Bengaluru to Chennai trip leaves 18 – 19 Oct. Capacity remaining after this: 25 kg.'),
          findsOneWidget,
          reason: 'copy.md accept panel, from the trip the booking is on');
      final accept = find.widgetWithText(FilledButton, 'Accept');
      expect(accept, findsOneWidget);
      final screen = Offset.zero & tester.view.physicalSize;
      final acceptBox = tester.getRect(accept);
      expect(screen.contains(acceptBox.topLeft) && acceptBox.bottom <= 800 - 80,
          isTrue,
          reason:
              'success criterion: the primary action is visible without scrolling ($acceptBox)');
      expect(find.text('Decline'), findsNothing,
          reason: 'no decline endpoint exists, so no Decline button');
      expect(tester.takeException(), isNull, reason: 'no overflow at 360 dp');
    });

    testWidgets('the truck sheet names the trip by the days it leaves',
        (tester) async {
      signInAsOwner();
      answer(bookings: [pending()], trips: [trip()]);
      await mountBooking(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.textContaining(
                  'Bengaluru to Chennai, leaves 18 – 19 Oct.')),
          findsOneWidget,
          reason: 'the dates are when the truck leaves, never an arrival');
    });

    testWidgets('Accept says why it is disabled for a carrier not yet approved',
        (tester) async {
      signInAsOwner();
      AuthorizationSession.organizations = [
        {...carrierOrganization, 'kycStatus': 'SUBMITTED'}
      ];
      answer(bookings: [pending()], trips: [trip()]);
      await mountBooking(tester);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
              .onPressed,
          isNull);
      expect(find.text('You can accept once NaviG8r approves your company.'),
          findsOneWidget,
          reason: 'a disabled button always says why');
    });

    testWidgets(
        'Accept is off on a trip the office asked NaviG8r to cancel, and says to withdraw first',
        (tester) async {
      signInAsOwner();
      answer(bookings: [pending()], trips: [trip(status: 'CANCEL_REQUESTED')]);
      await mountBooking(tester);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
              .onPressed,
          isNull,
          reason: 'the server refuses it');
      expect(
          find.text(
              'You asked NaviG8r to cancel this trip, so it cannot take this booking. Withdraw the request first.'),
          findsOneWidget);
    });

    test('a refused Accept on such a trip shows the server\'s sentence', () {
      api = Api('http://test');
      const detail =
          "This trip's carrier asked NaviG8r to cancel it, so it cannot take this booking now.";
      final refusal = DioException(
        requestOptions: RequestOptions(path: '/accept'),
        response: Response(
            requestOptions: RequestOptions(path: '/accept'),
            statusCode: 409,
            data: {'error': 'trip_cancel_requested', 'detail': detail}),
      );
      expect(plainErrorSentence(refusal), detail,
          reason:
              'a screen whose trip had not loaded, or was out of date, reads it after tapping');
    });

    const tripStarted =
        'This trip is already on the way, so it cannot take this booking.';
    for (final status in ['IN_PROGRESS', 'COMPLETED']) {
      testWidgets(
          "Accept is off on a trip that is $status, with the server's sentence",
          (tester) async {
        signInAsOwner();
        answer(bookings: [pending()], trips: [trip(status: status)]);
        await mountBooking(tester);
        expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
                .onPressed,
            isNull,
            reason: 'owner, 23 Oct 2026: the server refuses it');
        expect(find.text(tripStarted), findsOneWidget);
      });
    }

    test("a refused Accept on a started trip shows the server's sentence", () {
      api = Api('http://test');
      final refusal = DioException(
        requestOptions: RequestOptions(path: '/accept'),
        response: Response(
            requestOptions: RequestOptions(path: '/accept'),
            statusCode: 409,
            data: {'error': 'trip_already_started', 'detail': tripStarted}),
      );
      expect(plainErrorSentence(refusal), tripStarted);
    });

    testWidgets(
        'a bill without the truck is the shipper\'s to fix: the office reads it, with no form or copy rows',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        {...truckMissing(), 'id': 'shipment-a'}
      ], trips: [
        trip(id: 'trip-b')
      ]);
      await mountBooking(tester);
      expect(find.text('Accepted with KA01AB1234'), findsOneWidget,
          reason: 'ca-booking-truck: the done accept step names the truck');
      expect(find.text('Lakshmi Foods'), findsWidgets,
          reason: 'the step names the shipper as who acts');
      expect(find.text('You · Lakshmi Foods made the bill without it'),
          findsNothing,
          reason: 'the carrier is not asked to add the truck');
      expect(find.text('Lakshmi Foods has not added the truck to the bill yet.'),
          findsOneWidget,
          reason: 'the state in words');
      expect(find.text('2718 4402 1196'), findsOneWidget,
          reason: 'in groups of four, in the mono face');
      for (final words in [
        'E-way bill number',
        'Truck number',
        'Portal field: Vehicle No.',
        'Add truck',
        'Open the government e-way bill portal',
      ]) {
        expect(find.text(words), findsNothing, reason: 'read only: "$words"');
      }
    });

    testWidgets(
        'in transit offers Confirm delivery, which opens the photo step',
        (tester) async {
      signInAsOwner();
      answer(
          bookings: [shipmentOnTripA()],
          trips: [trip(status: 'IN_PROGRESS', driverName: 'Suresh Kumar')]);
      await mountBooking(tester);
      expect(find.text('On the way'), findsOneWidget);
      expect(find.text('You or Suresh Kumar'), findsOneWidget,
          reason: 'ca-booking-deliver: who confirms');
      final confirm = find.widgetWithText(FilledButton, 'Confirm delivery');
      expect(confirm, findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull,
          reason:
              'the photo is added on the next screen, which holds its own Confirm delivery until one is sent');
      expect(find.text('Add a photo first.'), findsNothing);
    });

    testWidgets('before the trip starts, the trip step opens the trip instead',
        (tester) async {
      signInAsOwner();
      answer(bookings: [shipmentOnTripA()], trips: [trip()]);
      await mountBooking(tester);
      expect(find.widgetWithText(OutlinedButton, 'Open trip'), findsOneWidget,
          reason: 'assigning and starting happen on the trip screen');
      expect(find.textContaining('120 kg · Leaves 18 – 19 Oct'), findsOneWidget,
          reason: 'the summary says the days the truck leaves');
      expect(
          find.widgetWithText(FilledButton, 'Confirm delivery'), findsNothing,
          reason:
              'ca-booking-deliver: confirming comes once the trip is on the road');
    });

    testWidgets(
        'after delivery the owner sees the amount the carrier API sends, together',
        (tester) async {
      signInAsOwner();
      answer(bookings: [delivered(netToCarrierPaise: 237600)], trips: [trip()]);
      await mountBooking(tester);
      expect(find.text('Waiting for payment'), findsOneWidget);
      expect(find.text('Delivery confirmed'), findsOneWidget,
          reason: 'the delivery step is done');
      expect(
          find.textContaining(RegExp(r', \d{2}:\d{2} IST$')), findsOneWidget,
          reason: 'when it was confirmed, in India time');
      expect(find.text('You receive ₹2,376'),
          findsOneWidget,
          reason: 'ca-booking-owner: the amount block, Indian grouping, no paise');
      expect(find.textContaining(RegExp(r'fee|commission|%', caseSensitive: false)), findsNothing,
          reason: 'never NaviG8r\'s cut, not even as a rate (owner hard rule, 21 Oct 2026)');
      expect(
          find.text(
              'Only owners see this.'),
          findsOneWidget);
      for (final missing in ['Shipper paid', 'NaviG8r commission']) {
        expect(find.text(missing), findsNothing,
            reason:
                'RECON gaps 20-21: $missing is not sent to carriers, so it is left out, never made up');
      }
    });

    testWidgets(
        'after delivery a dispatcher sees "Delivery confirmed" and no amount, though the server sent it',
        (tester) async {
      signInAsDispatcher();
      answer(bookings: [delivered(netToCarrierPaise: 237600)], trips: [trip()]);
      await mountBooking(tester);
      expect(find.text('Delivery confirmed'), findsNWidgets(2),
          reason: 'ca-booking-dispatcher: the status and the done step');
      expect(find.text('Nothing more to do.'),
          findsOneWidget);
      expect(
          find.text(
              'NaviG8r checks the delivery.'),
          findsOneWidget);
      expect(screenWords(tester), isNot(contains('₹')),
          reason: 'PR 6: no amount anywhere in a dispatcher\'s tree');
      expect(find.textContaining('You receive'), findsNothing);
      expect(find.text('Waiting for payment'), findsNothing);
    });
  });
}
