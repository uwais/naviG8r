// PRs 5a and 5b of the redesign: the shipment screen as numbered steps, the e-way bill steps with
// copy rows, the shipments list "Next:" line, the Home card and Updates (sh-ship-*, sh-ewb-*,
// sh-shipments, sh-notifications). Names, places and amounts are the mockups' synthetic ones.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/shipper/shipment_screen.dart';
import 'package:driver_pilot/shipper/shipments_list.dart';
import 'package:driver_pilot/shipper/shipper_home.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:driver_pilot/ui/nv_list_card.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';
import 'support/shipper_screen_checks.dart';

final bookedAt = DateTime.utc(2026, 10, 17, 3, 30);
final laneStart = DateTime.utc(2026, 10, 18, 3, 30);

/// The lane's dates as every screen shows them: the days the truck can leave.
final laneLeaves =
    'Leaves ${formatDateRange(laneStart, DateTime.parse('2026-10-19T12:00:00.000Z'))}';
final leftAt = DateTime.utc(2026, 10, 18, 0, 40);
final deliveredAt = DateTime.utc(2026, 10, 19, 8, 50);

/// A booking as GET /shipments returns it to the shipper. The ID starts the way real ones do.
Map<String, dynamic> booking(
        {String id = 'shp_9f2c41',
        String status = 'BOOKED',
        Map<String, dynamic>? ewayBill,
        String carrier = 'Ravi Roadways',
        Map<String, dynamic> extra = const {}}) =>
    {
      'id': id,
      'anchorTripId': 'lane-1',
      'customerOrgId': 'org-sharma',
      'carrierDisplayName': carrier,
      'status': status,
      'weightKg': 80,
      'grossPaise': 264000,
      'createdAtUtcMs': bookedAt.millisecondsSinceEpoch,
      'updatedAtUtcMs': 1,
      'pickupAddress': 'Bommasandra, Bengaluru',
      'dropAddress': 'Guindy, Chennai',
      if (ewayBill != null) 'ewayBill': ewayBill,
      ...extra,
    };

Map<String, dynamic> lane({String status = 'OPEN', DateTime? started}) => {
      'id': 'lane-1',
      'originCity': 'Bengaluru',
      'destCity': 'Chennai',
      'carrierDisplayName': 'Ravi Roadways',
      'windowStart': laneStart.toIso8601String(),
      'windowEnd': '2026-10-19T12:00:00.000Z',
      'status': status,
      if (started != null) 'startedAtUtcMs': started.millisecondsSinceEpoch,
    };

const billNoTruck = {
  'kind': 'BILL',
  'billNumber': '341200987654',
  'billDate': '2026-10-18',
  'makerGstin': '33AAACS7781L1ZQ',
  'invoiceNumber': 'ST/2026/0418',
};

/// 23:59 on 19 Oct 2026 in India.
final validUntil = DateTime.utc(2026, 10, 19, 18, 29);

Map<String, dynamic> get billWithTruck => {
      ...billNoTruck,
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs': validUntil.millisecondsSinceEpoch,
    };

class FakeServer {
  final requests = <RequestOptions>[];
  final answers = <String, Object>{};
}

/// A phone 360 dp wide, or [width] for the desktop layout, signed in as a Sharma Textiles shipper
/// who may write the bill and add the truck. [height] is 800 for "visible without scrolling"
/// checks; taller elsewhere, because the test font draws every letter a full square wide.
Future<FakeServer> showShipperApp(WidgetTester tester, String start,
    {double height = 3000, double width = 360}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('http://test');
  CustomerSession.skipRefreshInTests = true;
  addTearDown(() => CustomerSession.skipRefreshInTests = false);
  CustomerSession.applyForTest(
      userFullName: 'Priya Raman',
      userPhone: '9845012345',
      customerOrgId: 'org-sharma',
      customerOrgName: 'Sharma Textiles',
      customerRole: 'CUSTOMER_MEMBER');
  AuthorizationSession.principal!['permissions'] = [
    ...AuthorizationSession.principal!['permissions'] as List,
    'eway_bill.write',
    'eway_bill.add_truck',
    'notification.read',
    'conversation.read',
  ];
  api.selectOrganization('org-sharma');
  final server = FakeServer();
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    server.requests.add(request);
    final answer = server.answers[request.uri.path];
    // A refusal is given as its own jsonResponse with a status code.
    return answer is ResponseBody ? answer : jsonResponse(answer ?? {});
  });
  final router = GoRouter(initialLocation: start, routes: [
    GoRoute(
        path: '/customer',
        builder: (_, __) => const CustomerHomeScreen(),
        routes: [
          GoRoute(
              path: 'trips', builder: (_, __) => const Text('Lanes screen')),
          GoRoute(
              path: 'shipments',
              builder: (_, __) => const CustomerShipmentsScreen()),
          GoRoute(
              path: 'shipments/:id',
              builder: (_, state) => CustomerShipmentDetailScreen(
                  shipmentId: state.pathParameters['id']!)),
        ]),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  return server;
}

/// A paid booking's payment: checkout finished, the money held until delivery.
const heldPayment = {'status': 'AUTHORIZED', 'amountPaise': 264000};

/// Opens [shipment]'s screen with the trip the tracking call returns, and [heldPayment] unless
/// [payment] says otherwise.
Future<FakeServer> showShipment(
    WidgetTester tester, Map<String, dynamic> shipment,
    {Map<String, dynamic>? trip,
    Map<String, dynamic>? payment,
    double height = 3000,
    double width = 360}) async {
  final server = await showShipperApp(
      tester, '/customer/shipments/${shipment['id']}',
      height: height, width: width);
  server.answers['/shipments/${shipment['id']}'] = {
    'shipment': shipment,
    'payment': payment ?? heldPayment,
  };
  server.answers['/shipments/${shipment['id']}/tracking'] = {
    if (trip != null) 'trip': trip
  };
  await tester.pumpAndSettle();
  return server;
}

/// Leaves the screen, so its 15 second refresh stops before the test ends.
Future<void> leave(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Finder entry(String label) => find.descendant(
    of: find.widgetWithText(NvField, label), matching: find.byType(TextField));

List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

void main() {
  textSizeTests();
  stepPanelTests();
  paymentHoldTests();
  desktopTests();
  focusTests();
  plainErrorTests();
  doubleTextAt800Tests();

  group('Shipment screen (5a)', () {
    testWidgets('the title is the route, never the carrier name',
        (tester) async {
      await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'copy.md: the title is the route, not the carrier');
      final title = tester.widget<Text>(find.text('Bengaluru to Chennai'));
      expect(title.style?.fontSize, 26, reason: 'it is the screen heading');
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Text &&
              widget.data == 'Ravi Roadways' &&
              (widget.style?.fontSize ?? 0) >= 26),
          findsNothing,
          reason: 'the carrier name is never the title');
      await leave(tester);
    });

    testWidgets(
        'waiting for the carrier: the payment hold sentence, and no way to cancel but the contact',
        (tester) async {
      await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      expect(
          find.text(
              'Waiting for Ravi Roadways to accept. Your payment is on hold; it is collected after delivery.'),
          findsOneWidget,
          reason: 'brief A.3: the shipper is told the money is held');
      expect(find.text('Waiting for carrier'), findsOneWidget,
          reason: 'copy.md status word');
      expect(
          find.text(
              'Booked shipments cannot be cancelled in the app; to change one, contact ${PendingCopy.changeOrCancelContact}.'),
          findsOneWidget,
          reason:
              'owner decision: shippers cannot cancel; the contact is shown');
      expect(find.textContaining('Cancel booking'), findsNothing,
          reason: 'no cancel action exists');
      expect(find.text('${formatDate(bookedAt)} · ₹2,640 held until delivery'),
          findsOneWidget,
          reason: 'sh-ship-waiting: when it was booked and what is held');
      expect(find.text('Messages'), findsOneWidget,
          reason: 'copy.md summary: Messages');
      expect(find.textContaining('· $laneLeaves ·'), findsOneWidget,
          reason: 'the summary says when the truck leaves, never an arrival');
      await leave(tester);
    });

    testWidgets(
        'the e-way bill step before acceptance: no question built, the existing choices kept',
        (tester) async {
      await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      expect(
          find.text(
              'You can make the bill once the carrier accepts and names the truck. We will send you an update.'),
          findsOneWidget,
          reason: 'copy.md before acceptance');
      expect(find.text('Does this load need an e-way bill?'), findsNothing,
          reason:
              'RECON gap 1: no stored "needed" answer, so the step-0 question is not built');
      expect(find.text('Yes, make one'), findsNothing,
          reason: 'RECON gap 2: no endpoint saves a yes');
      expect(find.text('No e-way bill needed'), findsOneWidget,
          reason: 'the existing not-needed statement can still be given');
      expect(find.text('Open the e-way bill portal'), findsNothing,
          reason: 'the portal is not the next thing to do before acceptance');
      await leave(tester);
    });

    testWidgets('in transit: when it left, and who confirms delivery',
        (tester) async {
      await showShipment(tester, booking(ewayBill: notNeededBill),
          trip: lane(status: 'IN_PROGRESS', started: leftAt));
      expect(find.text('In transit'), findsOneWidget,
          reason: 'copy.md status word');
      expect(
          find.text(
              'Left Bommasandra, Bengaluru on ${formatDate(leftAt)} at ${formatTimeIst(leftAt)}. Ravi Roadways confirms when it is delivered.'),
          findsOneWidget,
          reason: 'copy.md on the way');
      expect(find.textContaining('Driver'), findsNothing,
          reason: 'RECON gap 5: the driver name is not sent to shippers');
      await leave(tester);
    });

    testWidgets(
        'not needed: the step says so and the carrier starts the trip next',
        (tester) async {
      await showShipment(tester, booking(ewayBill: notNeededBill),
          trip: lane());
      expect(find.text('E-way bill: not needed'), findsOneWidget,
          reason: 'copy.md not needed');
      expect(
          find.text(
              'Nothing for you to do now. Ravi Roadways starts the trip. The truck ${laneLeaves.replaceFirst('Leaves', 'leaves')}.'),
          findsOneWidget,
          reason: 'sh-ship-noewb: who acts next, and the days the truck can leave');
      await leave(tester);
    });

    testWidgets('delivered: who confirmed, what is collected, book another',
        (tester) async {
      await showShipment(
          tester,
          booking(status: 'DELIVERED', ewayBill: {
            ...billWithTruck,
            'check': {'result': 'FOUND'}
          }, extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
            'podAcceptedAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          }),
          trip: lane(status: 'COMPLETED', started: leftAt),
          payment: {'status': 'CAPTURED', 'amountPaise': 264000});
      expect(find.text('Delivered'), findsWidgets,
          reason: 'copy.md status word and the last step');
      expect(
          find.text(
              'Ravi Roadways confirmed delivery and added proof of delivery. Your payment of ₹2,640 is collected now.'),
          findsOneWidget,
          reason: 'copy.md delivered');
      expect(find.text('Book another shipment'), findsOneWidget,
          reason: 'copy.md delivered: the way on');
      expect(find.text('View proof of delivery'), findsNothing,
          reason: 'RECON gap 6: there is no proof-of-delivery photo to view');
      expect(
          find.text('Booked shipments cannot be cancelled in the app; '
              'to change one, contact ${PendingCopy.changeOrCancelContact}.'),
          findsNothing,
          reason: 'nothing left to change once delivered');
      await leave(tester);
    });

    testWidgets('cancelled shows words, not a code', (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(), payment: {'status': 'REFUNDED', 'amountPaise': 264000});
      expect(find.text('Cancelled'), findsOneWidget,
          reason: 'copy.md: the status is a word');
      expect(find.text('This shipment was cancelled'), findsOneWidget,
          reason: 'copy.md cancelled');
      expect(find.textContaining('FAILED_CARRIER_REFUNDED'), findsNothing,
          reason: 'decisions.md guardrail 7: never the system code');
      expect(
          find.text(
              'If you paid the ₹2,640 for this booking, all of it is refunded.'),
          findsOneWidget,
          reason:
              'a never-paid booking is also marked refunded on cancel, so the refund is told without claiming a payment');
      expect(find.text('You paid'), findsNothing,
          reason: 'the payment record cannot say whether it was ever paid');
      expect(
          find.text(
              'Refunds reach your account in the time your bank or payment app takes.'),
          findsOneWidget);
      expect(
          find.text(
              'Questions about this refund? Contact ${PendingCopy.changeOrCancelContact}.'),
          findsOneWidget,
          reason: 'copy.md cancelled: the contact placeholder');
      expect(find.widgetWithText(FilledButton, 'Find a lane'), findsOneWidget,
          reason: 'screens.md: the primary action on a cancelled shipment');
      expect(find.text('Steps for this shipment'), findsNothing);
      await leave(tester);
    });

    testWidgets('cancelled with the payment still held: says what was paid',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane());
      expect(find.text('You paid'), findsOneWidget,
          reason: 'an authorized payment is money the shipper paid');
      expect(find.text('₹2,640'), findsOneWidget);
      expect(
          find.text(
              'Refunds reach your account in the time your bank or payment app takes.'),
          findsOneWidget);
      await leave(tester);
    });

    testWidgets('cancelled before any payment: says nothing was paid',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(), payment: {'status': 'CREATED', 'amountPaise': 264000});
      expect(find.text('Nothing was paid for this booking.'), findsOneWidget,
          reason: 'checkout never finished, so no money was taken');
      expect(find.text('You paid'), findsNothing,
          reason: 'no payment was taken, so none is claimed');
      expect(find.textContaining('refunded'), findsNothing,
          reason: 'nothing to refund');
      expect(
          find.text(
              'Questions about this booking? Contact ${PendingCopy.changeOrCancelContact}.'),
          findsOneWidget,
          reason: 'the contact stays, about the booking, not a refund');
      await leave(tester);
    });

    for (final (paymentStatus, opening) in [
      ('CREATED', ''),
      ('FAILED', 'Payment did not go through. '),
    ]) {
      testWidgets(
          'payment $paymentStatus: booked, not paid, and nothing said to be held',
          (tester) async {
        await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
            trip: lane(),
            payment: {'status': paymentStatus, 'amountPaise': 264000});
        expect(find.text('Booked, not paid'), findsOneWidget,
            reason: 'checkout did not finish, so the first step is not "paid"');
        expect(find.text('Booked and paid'), findsNothing,
            reason: 'never claim a payment that was not taken');
        expect(find.text('Not paid'), findsOneWidget,
            reason: 'the status word says what is wrong');
        expect(
            find.text(
                '${opening}This booking is not paid, so Ravi Roadways cannot accept it yet. '
                'To pay or cancel it, contact ${PendingCopy.changeOrCancelContact}.'),
            findsOneWidget,
            reason:
                'what it means and who to contact; there is no way to pay again in the app');
        expect(find.textContaining('held until delivery'), findsNothing,
            reason: 'no money is held');
        expect(find.textContaining('Your payment is on hold'), findsNothing,
            reason: 'no money is held');
        expect(find.text('Ravi Roadways can accept once this booking is paid.'),
            findsOneWidget,
            reason: 'the carrier step says why it waits');
        await leave(tester);
      });
    }
  });

  group('E-way bill steps (5b)', () {
    testWidgets(
        'Open the e-way bill portal is fully on screen at 360 x 800 without scrolling',
        (tester) async {
      await showShipment(
          tester,
          booking(extra: {
            'assignedTruckNumber': 'KA01AB1234',
            'carrierTransporterId': '29ABCDE1234F1Z5',
          }),
          trip: lane(),
          height: 800);
      final portal = find.text('Open the e-way bill portal');
      expect(portal, findsOneWidget);
      final button =
          find.ancestor(of: portal, matching: find.byType(FilledButton));
      const view = Rect.fromLTWH(0, 0, 360, 800);
      final rect = tester.getRect(button);
      expect(view.contains(rect.topLeft) && view.contains(rect.bottomRight),
          isTrue,
          reason:
              'success criterion: primary action visible without scrolling (was $rect)');
      await leave(tester);
    });

    testWidgets(
        'part 1 copy rows name the portal fields, copy without spaces and announce',
        (tester) async {
      final copied = watchClipboard(tester);
      final announced = watchAnnouncements(tester);
      await showShipment(
          tester,
          booking(extra: {
            'assignedTruckNumber': 'KA 01 AB 1234',
            'carrierTransporterId': '29ABCDE1234F1Z5',
          }),
          trip: lane());
      expect(find.text('You · Part 1 of 2'), findsOneWidget,
          reason: 'sh-ewb-portal: whose step, and which part');
      expect(
          find.text(
              'Make the bill in your billing software or on the e-way bill site. Copy these in:'),
          findsOneWidget);
      expect(find.text('Portal field: Vehicle No. (Part B)'), findsOneWidget,
          reason: 'testers could not tell where each value goes on the portal');
      expect(find.text('Portal field: Transporter ID. Not your GSTIN.'),
          findsOneWidget,
          reason: 'testers could not tell GSTIN from transporter ID');
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'the truck in the portal form');
      expect(
          find.text(
              'Make it on loading day, before the goods move: the bill is valid from when the truck is entered.'),
          findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Copy truck number KA01AB1234'));
      await tester.pump();
      await tester.tap(find
          .bySemanticsLabel("Copy carrier's transporter ID 29ABCDE1234F1Z5"));
      await tester.pump();
      expect(copied, ['KA01AB1234', '29ABCDE1234F1Z5'],
          reason: 'the values go to the clipboard alone, with no spaces');
      expect(
          announced,
          containsAll(
              ['Truck number copied.', "Carrier's transporter ID copied."]),
          reason: 'accessibility.md: a copy is announced');
      await tester.pump(const Duration(seconds: 3));
      await leave(tester);
    });

    testWidgets('with no transporter ID, part 1 says to leave the field empty',
        (tester) async {
      await showShipment(
          tester, booking(extra: {'assignedTruckNumber': 'KA01AB1234'}),
          trip: lane());
      expect(find.text('Ravi Roadways has not added one.'), findsOneWidget,
          reason: 'cp-copy empty state');
      expect(
          find.text(
              "Leave Transporter ID empty. Only you, the bill's maker, can then change the truck."),
          findsOneWidget,
          reason: 'copy.md step 1: what to do without one');
      await leave(tester);
    });

    testWidgets('the footnote appears exactly once on the screen',
        (tester) async {
      await showShipment(
          tester, booking(extra: {'assignedTruckNumber': 'KA01AB1234'}),
          trip: lane());
      expect(find.text(ewayBillFootnote), findsOneWidget,
          reason: 'copy.md: once per screen, small');
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      expect(find.text(ewayBillFootnote), findsOneWidget,
          reason: 'still once with the form open');
      await leave(tester);
    });

    testWidgets(
        'an 11-digit bill number is stopped with its own sentence, before anything is sent',
        (tester) async {
      final announced = watchAnnouncements(tester);
      final server = await showShipment(
          tester, booking(extra: {'carrierTransporterId': '29ABCDE1234F1Z5'}),
          trip: lane());
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      await tester.enterText(entry('E-way bill number'), '34120098765');
      await tester.enterText(entry('Your GSTIN'), '33AAACS7781L1ZQ');
      await tester.enterText(entry('Invoice number'), 'ST/2026/0418');
      await tester.tap(find.text('Save e-way bill'));
      await tester.pumpAndSettle();
      expect(find.text('This has 11 digits. An e-way bill number has 12.'),
          findsOneWidget,
          reason: 'copy.md step 2 errors');
      expect(find.text('1 detail needs fixing before you can save.'),
          findsOneWidget,
          reason: 'copy.md: the error summary above the fields');
      expect(announced, contains('1 detail needs fixing before you can save.'),
          reason: 'accessibility.md: errors are announced');
      expect(
          server.requests.where((request) => request.method == 'POST').isEmpty,
          isTrue,
          reason: 'nothing is sent while a detail is wrong');
      await leave(tester);
    });

    testWidgets(
        "the carrier's transporter ID typed as the GSTIN is an error when the ID is on screen",
        (tester) async {
      await showShipment(
          tester,
          booking(extra: {
            'assignedTruckNumber': 'KA01AB1234',
            'carrierTransporterId': '29ABCDE1234F1Z5',
          }),
          trip: lane());
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      await tester.enterText(entry('E-way bill number'), '341200987654');
      await tester.enterText(entry('Your GSTIN'), '29abcde1234f1z5');
      await tester.enterText(entry('Invoice number'), 'ST/2026/0418');
      await tester.tap(find.text('Save e-way bill'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              "This is the carrier's transporter ID. Enter the GSTIN that made the bill."),
          findsOneWidget,
          reason: 'sh-ewb-details-error: testers typed the wrong ID');
      await leave(tester);
    });

    testWidgets(
        'without the transporter ID on screen the GSTIN is not compared',
        (tester) async {
      await showShipment(tester, booking(), trip: lane());
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      await tester.enterText(entry('Your GSTIN'), '29ABCDE1234F1Z5');
      await tester.tap(find.text('Save e-way bill'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining("carrier's transporter ID. Enter"), findsNothing,
          reason: 'nothing to compare with, so no error is guessed');
      await leave(tester);
    });

    testWidgets('a bill without the truck: add it, with the portal field named',
        (tester) async {
      await showShipment(
          tester,
          booking(
              ewayBill: billNoTruck,
              extra: {'assignedTruckNumber': 'KA01AB1234'}),
          trip: lane());
      expect(find.text('You or Ravi Roadways'), findsNothing,
          reason:
              'owner decision 18 Oct 2026: the shipper adds the truck, the carrier only reads the bill');
      expect(
          find.text('Bill 3412 0098 7654 saved. The truck is not on it yet.'),
          findsOneWidget,
          reason: 'copy.md step 3');
      expect(find.text('Portal: Update Part B, Vehicle No.'), findsOneWidget,
          reason: 'copy.md step 3: where the truck goes');
      expect(
          find.text(
              "The bill's validity starts when the truck is added: one day per 200 km, ending at midnight India time."),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add truck'), findsOneWidget,
          reason: 'sh-ewb-truck primary');
      await tester.tap(find.widgetWithText(FilledButton, 'Add truck'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Truck number'))
              .controller!
              .text,
          'KA01AB1234',
          reason: 'filled in from the truck the carrier named at acceptance');
      expect(find.text('Valid until, date in India: choose the date'),
          findsOneWidget,
          reason: 'the shipper enters the valid-until printed on their bill');
      await leave(tester);
    });

    testWidgets('bill and truck saved: NaviG8r staff check it', (tester) async {
      await showShipment(tester, booking(ewayBill: billWithTruck),
          trip: lane());
      expect(
          find.text(
              'E-way bill saved. Nothing more for you to do until delivery.'),
          findsOneWidget,
          reason: 'copy.md step 4');
      expect(
          find.text(
              'NaviG8r staff check the bill on the portal by hand. If they find a problem, this shipment and your Home screen show what to fix.'),
          findsOneWidget,
          reason:
              'copy.md step 4: who checks, and how; no message is sent about a problem, so none is promised');
      expect(find.text('3412 0098 7654'), findsOneWidget,
          reason: 'the bill number in groups of four');
      expect(
          find.text('${formatDate(validUntil)}, ${formatTimeIst(validUntil)}'),
          findsOneWidget,
          reason: 'sh-ewb-checking: valid until, in India time');
      await leave(tester);
    });

    testWidgets('a flagged bill: the status and the step say it needs a fix',
        (tester) async {
      await showShipment(
          tester,
          booking(ewayBill: {
            ...billWithTruck,
            'check': {'result': 'PROBLEM', 'problemReason': 'NOT_FOUND'}
          }),
          trip: lane());
      expect(find.text('E-way bill needs a fix'), findsOneWidget,
          reason: 'sh-ewb-problem status word');
      expect(find.text('NaviG8r staff found a difference'), findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Fix the details'), findsOneWidget,
          reason: 'sh-ewb-problem primary');
      expect(find.text('Ask NaviG8r staff'), findsNothing,
          reason: 'RECON gap 12: no channel known to reach staff');
      await leave(tester);
    });
  });

  group('Shipments list and Home', () {
    testWidgets('each card is the route with a Next: line from the steps',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/shipments');
      server.answers['/shipments'] = {
        'shipments': [
          booking(
              id: 'shp_needs', extra: {'assignedTruckNumber': 'KA01AB1234'}),
          booking(
              id: 'shp_moving',
              ewayBill: notNeededBill,
              extra: {'anchorTripId': 'lane-2'}),
          booking(
              id: 'shp_waiting',
              status: 'PENDING_CARRIER_ACCEPT',
              carrier: 'Deccan Movers',
              extra: {'anchorTripId': 'lane-3'}),
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [
          lane(),
          {...lane(status: 'IN_PROGRESS'), 'id': 'lane-2'},
          {...lane(), 'id': 'lane-3', 'destCity': 'Mysuru'},
        ]
      };
      await tester.pumpAndSettle();
      expect(find.text('Shipments'), findsWidgets);
      expect(find.text('Active (3)'), findsOneWidget);
      expect(find.text('Next: You make the e-way bill.'), findsOneWidget,
          reason:
              'screens.md: the list Next: line comes from the step mapping');
      expect(find.text('Needs you'), findsOneWidget,
          reason: 'sh-shipments: the card waiting on the shipper says so');
      expect(
          find.text('Next: Ravi Roadways confirms delivery.'), findsOneWidget,
          reason: 'the lane list tells a started trip apart');
      expect(find.text('In transit'), findsOneWidget);
      expect(find.text('Next: Deccan Movers accepts and names the truck.'),
          findsOneWidget);
      expect(find.text('Bengaluru to Mysuru'), findsOneWidget,
          reason: 'copy.md: a shipment is named by its route');
      expect(find.textContaining(RegExp('^$laneLeaves · ')), findsNWidgets(3),
          reason: 'each card says when its truck leaves');
      expect(find.textContaining('shp_'), findsNothing, reason: 'never an ID');
      server.answers['/shipments/shp_waiting'] = {
        'shipment': (server.answers['/shipments'] as Map)['shipments'][2],
        'payment': heldPayment,
      };
      await tester.tap(find.text('Bengaluru to Mysuru'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Waiting for Deccan Movers to accept. Your payment is on hold; it is collected after delivery.'),
          findsOneWidget,
          reason: 'the whole card opens the shipment');
      await leave(tester);
    });

    testWidgets('Home names the task\'s shipment by route and lane date',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answers['/shipments'] = {
        'shipments': [
          booking(extra: {'assignedTruckNumber': 'KA01AB1234'})
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      await tester.pumpAndSettle();
      expect(find.text('Make the e-way bill'), findsOneWidget,
          reason: 'the Home task comes from the step mapping');
      expect(
          find.text(
              'Bengaluru to Chennai, ${formatDate(laneStart)}. Ravi Roadways accepted and named the truck.'),
          findsOneWidget,
          reason: 'copy.md: route, date, who did what');
    });

    testWidgets(
        'a delivery waiting for acceptance is the Home task, ahead of an older e-way bill task',
        (tester) async {
      final delivered = booking(
          id: 'shp_delivered',
          status: 'PENDING_RELEASE',
          ewayBill: billWithTruck,
          extra: {
            'anchorTripId': 'lane-2',
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          });
      final server = await showShipperApp(tester, '/customer');
      server.answers['/shipments'] = {
        'shipments': [booking(), delivered]
      };
      server.answers['/anchor-trips'] = {
        'trips': [
          lane(),
          {...lane(status: 'COMPLETED'), 'id': 'lane-2', 'destCity': 'Mysuru'},
        ]
      };
      server.answers['/shipments/shp_delivered'] = {
        'shipment': delivered,
        'payment': heldPayment,
      };
      await tester.pumpAndSettle();
      expect(find.text('Accept delivery'), findsOneWidget,
          reason: 'seen on the recorded run: Home showed the e-way bill task');
      expect(find.text('Make the e-way bill'), findsNothing,
          reason: 'the 48-hour hold ends on its own, so acceptance comes first');
      expect(
          find.text(
              'Bengaluru to Mysuru, ${formatDate(laneStart)}. Ravi Roadways confirmed delivery on ${formatDate(deliveredAt)}. '
              'Check the goods. Accepting lets payment go before the hold ends; if you do nothing it can go when the hold ends.'),
          findsOneWidget,
          reason: 'review: accepting is optional, and the card says what happens either way');
      await tester.tap(find.text('Open shipment'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Accept delivery'),
          findsOneWidget,
          reason: 'the task opens the shipment that holds the button');
      await leave(tester);
    });

    testWidgets(
        'once the 48-hour hold is over, an e-way bill task is the Home task again',
        (tester) async {
      final holdOver = booking(
          id: 'shp_delivered',
          status: 'PENDING_RELEASE',
          ewayBill: billWithTruck,
          extra: {
            'anchorTripId': 'lane-2',
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
            'paymentReady': true,
          });
      final server = await showShipperApp(tester, '/customer');
      server.answers['/shipments'] = {
        'shipments': [holdOver, booking()]
      };
      server.answers['/anchor-trips'] = {
        'trips': [
          lane(),
          {...lane(status: 'COMPLETED'), 'id': 'lane-2', 'destCity': 'Mysuru'},
        ]
      };
      await tester.pumpAndSettle();
      expect(find.text('Make the e-way bill'), findsOneWidget,
          reason: 'review: accepting changes nothing once payment can be released');
      expect(find.text('Accept delivery'), findsNothing);
    });

    testWidgets('the Accept delivery task fits 360 x 800 at 200% text',
        (tester) async {
      useDoubleTextSize(tester);
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answers['/shipments'] = {
        'shipments': [
          booking(
              status: 'PENDING_RELEASE',
              ewayBill: billWithTruck,
              extra: {'podAtUtcMs': deliveredAt.millisecondsSinceEpoch}),
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane(status: 'COMPLETED')]
      };
      await tester.pumpAndSettle();
      expect(find.text('Accept delivery'), findsOneWidget);
      await expectNoOverflowToTheEnd(tester, 'Home with Accept delivery');
    });

    testWidgets(
        'the list keeps a delivery waiting for acceptance under Active, marked Needs you',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/shipments');
      server.answers['/shipments'] = {
        'shipments': [
          booking(
              status: 'PENDING_RELEASE',
              ewayBill: billWithTruck,
              extra: {'podAtUtcMs': deliveredAt.millisecondsSinceEpoch}),
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane(status: 'COMPLETED')]
      };
      await tester.pumpAndSettle();
      expect(find.text('Active (1)'), findsOneWidget,
          reason: 'it still waits on the shipper, so it is not done');
      expect(find.text('Done'), findsNothing);
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Next: You accept the delivery.'), findsOneWidget);
    });

    testWidgets('the list moves a delivery to Done once its hold is over',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/shipments');
      server.answers['/shipments'] = {
        'shipments': [
          booking(
              status: 'PENDING_RELEASE',
              ewayBill: billWithTruck,
              extra: {
                'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
                'paymentReady': true,
              }),
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane(status: 'COMPLETED')]
      };
      await tester.pumpAndSettle();
      expect(find.text('Needs you'), findsNothing,
          reason: 'review: accepting changes nothing once payment can be released');
      expect(find.text('Next: You accept the delivery.'), findsNothing);
      expect(find.text('Active (1)'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets(
        'Home has no task while the trip is on the way, whatever the bill',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answers['/shipments'] = {
        'shipments': [booking()]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane(status: 'IN_PROGRESS')]
      };
      await tester.pumpAndSettle();
      expect(find.text('NEEDS YOU'), findsNothing,
          reason: 'screens.md: in transit, the carrier acts next');
    });

    testWidgets('Home built while signed out loads its task once sign-in lands',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      CustomerSession.clear();
      await tester.pumpAndSettle();
      server.answers['/shipments'] = {
        'shipments': [
          booking(extra: {'assignedTruckNumber': 'KA01AB1234'})
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      // The sign-in page sits on top of Home, so Home stays built across sign-in.
      CustomerSession.applyForTest(
          userFullName: 'Priya Raman',
          customerOrgId: 'org-sharma',
          customerOrgName: 'Sharma Textiles',
          customerRole: 'CUSTOMER_MEMBER');
      AuthorizationSession.principal!['permissions'] = [
        ...AuthorizationSession.principal!['permissions'] as List,
        'eway_bill.write',
      ];
      AuthorizationSession.revision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Make the e-way bill'), findsOneWidget,
          reason: 'seen on the emulator: Home stayed empty until pulled');
    });

    testWidgets('Home never shows the last account\'s task to the next one',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answers['/shipments'] = {
        'shipments': [
          booking(extra: {'assignedTruckNumber': 'KA01AB1234'})
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      await tester.pumpAndSettle();
      expect(find.text('Make the e-way bill'), findsOneWidget);
      CustomerSession.clear();
      await tester.pumpAndSettle();
      // The next company's load fails, so only stale data could put a task on screen.
      server.answers['/shipments'] =
          jsonResponse({'error': 'internal'}, 500);
      CustomerSession.applyForTest(
          userFullName: 'Anil Kumar',
          customerOrgId: 'org-other',
          customerOrgName: 'Kumar Traders',
          customerRole: 'CUSTOMER_MEMBER');
      AuthorizationSession.principal!['permissions'] = [
        ...AuthorizationSession.principal!['permissions'] as List,
        'eway_bill.write',
      ];
      AuthorizationSession.revision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Make the e-way bill'), findsNothing,
          reason: 'the task belonged to Sharma Textiles');
      expect(find.text('Could not load your shipments.'), findsOneWidget);
    });
  });

  group('Updates', () {
    testWidgets('rows are named by route and date, and no SHP_ string renders',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answers['/v1/notifications/shipments'] = {
        'shipments': [
          {
            'shipmentId': 'shp_9f2c41',
            'shipmentReference': 'SHP_9F2C',
            'latestAtUtcMs': leftAt.millisecondsSinceEpoch,
            'unreadCount': 2
          },
          {
            'shipmentId': 'shp_gone',
            'shipmentReference': 'SHP_GONE',
            'latestAtUtcMs': bookedAt.millisecondsSinceEpoch,
            'unreadCount': 0
          },
        ],
        'unreadCount': 2
      };
      server.answers['/shipments'] = {
        'shipments': [booking()]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(find.text('Updates')),
          containsSemantics(isButton: true, hasTapAction: true),
          reason: 'a screen reader and the browser tests find the row as a button');
      semantics.dispose();
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxScreen), findsOneWidget);
      expect(find.text('Bengaluru to Chennai, ${formatDate(laneStart)}'),
          findsOneWidget,
          reason: 'screens.md: name shipments by route and date');
      expect(find.text('2 new updates'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('EARLIER'), findsOneWidget);
      expect(find.text('${formatDate(leftAt)}, ${formatTimeIst(leftAt)}'),
          findsOneWidget,
          reason: 'copy.md: times are 24-hour IST');
      expect(find.textContaining('SHP_'), findsNothing,
          reason: 'screens.md: never SHP_ in notifications');
      expect(find.text('Shipment update'), findsOneWidget,
          reason: 'a shipment not in the list keeps a plain title, not its ID');
      await tester.pumpWidget(const SizedBox());
    });
  });
}

const notNeededBill = {
  'kind': 'NOT_NEEDED',
  'notNeededReason': 'GOODS_EXEMPT',
};

void textSizeTests() {
  group('200% text at 360 dp', () {
    testWidgets('every shipment state and the bill form fit', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final states = <String, Map<String, dynamic>>{
        'part 1': booking(extra: {
          'assignedTruckNumber': 'KA01AB1234',
          'carrierTransporterId': '29ABCDE1234F1Z5',
        }),
        'waiting': booking(status: 'PENDING_CARRIER_ACCEPT'),
        'bill without truck': booking(
            ewayBill: billNoTruck,
            extra: {'assignedTruckNumber': 'KA01AB1234'}),
        'checking': booking(ewayBill: billWithTruck),
        'problem': booking(ewayBill: {
          ...billWithTruck,
          'check': {'result': 'PROBLEM', 'problemReason': 'NOT_FOUND'}
        }),
        'cancelled': booking(status: 'FAILED_CARRIER_REFUNDED'),
      };
      for (final entry in states.entries) {
        await showShipment(tester, entry.value, trip: lane(), height: 6000);
        expect(tester.takeException(), isNull,
            reason: 'decisions.md 8: ${entry.key} fits at 200% text');
        await leave(tester);
      }
      await showShipment(tester, booking(), trip: lane(), height: 6000);
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: the bill form fits at 200% text');
      await leave(tester);
    });
  });
}

void stepPanelTests() {
  testWidgets(
      'NvStep.panelAlwaysShown shows a done or later panel; without it they stay closed',
      (tester) async {
    Future<void> mount(bool always) => tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: NvStepList(listName: 'Steps for this shipment', steps: [
          NvStep(
              title: 'E-way bill',
              state: NvStepState.done,
              panelAlwaysShown: always,
              panel: const Text('Saved bill facts')),
          NvStep(
              title: 'On the way',
              state: NvStepState.later,
              panelAlwaysShown: always,
              panel: const Text('Before acceptance words')),
        ]))));
    await mount(false);
    expect(find.text('Saved bill facts'), findsNothing,
        reason: 'components.md: a done step has no panel by default');
    expect(find.text('Before acceptance words'), findsNothing);
    await mount(true);
    expect(find.text('Saved bill facts'), findsOneWidget,
        reason: 'sh-ewb-checking: the saved bill shows under its done step');
    expect(find.text('Before acceptance words'), findsOneWidget,
        reason:
            'sh-ewb-ask: the e-way bill step shows its words before acceptance');
  });
}

void paymentHoldTests() {
  testWidgets(
      'delivery confirmed: the hold is written in India time and nothing says collected yet',
      (tester) async {
    final holdEnds = deliveredAt.add(const Duration(hours: 48));
    await showShipment(
        tester,
        booking(status: 'PENDING_RELEASE', ewayBill: billWithTruck, extra: {
          'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          'paymentHoldUntilUtcMs': holdEnds.millisecondsSinceEpoch,
        }),
        trip: lane(status: 'COMPLETED', started: leftAt));
    expect(
        find.text(
            'Payment on hold until ${formatDate(holdEnds)}, ${formatTimeIst(holdEnds)}. Shipper acceptance can end the hold earlier.'),
        findsOneWidget,
        reason: 'copy.md formats: 24-hour IST, never a raw timestamp');
    expect(find.textContaining('.000'), findsNothing);
    expect(
        find.text(
            'Ravi Roadways confirmed delivery and added proof of delivery.'),
        findsOneWidget,
        reason:
            'until the payment is released, the hold line says what happens to it');
    expect(find.text('Accept delivery'), findsOneWidget,
        reason: 'the existing accept-delivery action stays');
    await leave(tester);
  });
}

const noCancelLine =
    'Booked shipments cannot be cancelled in the app; to change one, contact ${PendingCopy.changeOrCancelContact}.';

/// A shipment waiting on the shipper's e-way bill: the carrier accepted and named the truck.
Map<String, dynamic> get needsBill => booking(extra: {
      'assignedTruckNumber': 'KA01AB1234',
      'carrierTransporterId': '29ABCDE1234F1Z5',
    });

void desktopTests() {
  group('Desktop width (PR 9)', () {
    testWidgets(
        'at 1280 the details, Messages and the contact line sit beside the steps, and the portal is in the step',
        (tester) async {
      await showShipment(tester, needsBill,
          trip: lane(), width: 1280, height: 900);
      final steps = tester.getRect(find.byType(NvStepList));
      for (final words in ['Messages', noCancelLine]) {
        expect(tester.getRect(find.text(words)).left, greaterThan(steps.right),
            reason: 'wb-shipment: "$words" sits in the side column');
      }
      final portal = find.text('Open the e-way bill portal');
      expect(find.descendant(of: find.byType(NvStepList), matching: portal),
          findsOneWidget,
          reason: 'wb-shipment: the portal button sits in the e-way bill step');
      expect(tester.getRect(portal).bottom, lessThanOrEqualTo(900),
          reason: 'decisions.md 8: the primary action shows without scrolling');
      expect(find.byType(NvActionBar), findsNothing,
          reason: 'desktop: no bottom action bar');
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'the same title as the phone');
      await leave(tester);
    });

    testWidgets(
        'at 1280 the shipments list is a table inside its own sideways-scrolling box',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/shipments',
          width: 1280, height: 900);
      final waiting = booking(
          id: 'shp_waiting',
          status: 'PENDING_CARRIER_ACCEPT',
          carrier: 'Deccan Movers',
          extra: {'anchorTripId': 'lane-3'});
      server.answers['/shipments'] = {
        'shipments': [needsBill, waiting]
      };
      server.answers['/anchor-trips'] = {
        'trips': [
          lane(),
          {...lane(), 'id': 'lane-3', 'destCity': 'Mysuru'},
        ]
      };
      await tester.pumpAndSettle();
      final table = find.byType(Table);
      for (final column in [
        'Route',
        'Date',
        'Weight',
        'Carrier',
        'Status',
        'Next'
      ]) {
        expect(find.descendant(of: table, matching: find.text(column)),
            findsOneWidget,
            reason: 'wb-shipments: the "$column" column');
      }
      expect(find.descendant(of: table, matching: find.text(laneLeaves)),
          findsNWidgets(2),
          reason: 'each row says when its truck leaves');
      expect(
          find.ancestor(
              of: table,
              matching: find.byWidgetPredicate((widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal)),
          findsOneWidget,
          reason: 'PR 9: the table scrolls sideways inside its own box');
      expect(find.byType(NvListCard), findsNothing,
          reason: 'desktop: rows, not cards');
      expect(find.text('Active (2)'), findsOneWidget,
          reason: 'the same heading as the phone');
      expect(find.text('You make the e-way bill'), findsOneWidget,
          reason: 'screens.md: the Next column comes from the step mapping');
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.textContaining('shp_'), findsNothing, reason: 'never an ID');

      server.answers['/shipments/shp_waiting'] = {
        'shipment': waiting,
        'payment': heldPayment,
      };
      await tester.tap(find.text('Bengaluru to Mysuru'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Waiting for Deccan Movers to accept. Your payment is on hold; it is collected after delivery.'),
          findsOneWidget,
          reason: 'the route link opens the shipment');
      await leave(tester);
    });
  });
}

void focusTests() {
  group('Focus moves (PR 10)', () {
    testWidgets("after Pay and book, focus starts on the new shipment's title",
        (tester) async {
      lastBookedShipmentId = 'shp_9f2c41';
      addTearDown(() => lastBookedShipmentId = null);
      await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      expect(
          Focus.of(tester.element(find.text('Bengaluru to Chennai')))
              .hasPrimaryFocus,
          isTrue,
          reason:
              "accessibility.md: after Pay and book, focus moves to the shipment's H1");
      expect(lastBookedShipmentId, isNull,
          reason: 'only the first opening after booking moves focus');
      await leave(tester);
    });

    testWidgets('a failed bill save moves focus to the error summary',
        (tester) async {
      await showShipment(tester, needsBill, trip: lane());
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      await tester.enterText(entry('E-way bill number'), '34120098765');
      await tester.tap(find.text('Save e-way bill'));
      await tester.pumpAndSettle();
      expect(
          Focus.of(tester.element(
                  find.text('1 detail needs fixing before you can save.')))
              .hasPrimaryFocus,
          isTrue,
          reason:
              'accessibility.md: on a failed save, focus moves to the error summary');
      await leave(tester);
    });
  });
}

void plainErrorTests() {
  group('No HTTP text (PR 10)', () {
    testWidgets('a refused Accept delivery says so in words', (tester) async {
      final server = await showShipment(
          tester,
          booking(status: 'PENDING_RELEASE', ewayBill: billWithTruck, extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          }),
          trip: lane(status: 'COMPLETED', started: leftAt));
      server.answers['/shipments/shp_9f2c41/accept-pod'] =
          jsonResponse({'error': 'boom'}, 500);
      await tester.tap(find.text('Accept delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Accept delivery')));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Could not accept delivery. Check your connection, then try again.'),
          findsOneWidget,
          reason: 'a failure is a plain sentence');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no "HTTP 500" in the app');
      await leave(tester);
    });

    testWidgets('messages that fail to load say so in words', (tester) async {
      final server = await showShipment(
          tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      server.answers['/v1/shipments/shp_9f2c41/conversation/timeline'] =
          jsonResponse({'error': 'boom'}, 500);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Could not load messages. Check your connection, then try again.'),
          findsOneWidget,
          reason: 'a failure is a plain sentence');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no raw codes');
      await leave(tester);
    });
  });
}

void doubleTextAt800Tests() {
  group('200% text at 360 x 800 (PR 10)', () {
    testWidgets('every shipment state fits, scrolled top to bottom',
        (tester) async {
      useDoubleTextSize(tester);
      final states = <String,
          (
        Map<String, dynamic> shipment,
        Map<String, dynamic> trip,
        Map<String, dynamic>? payment
      )>{
        'waiting': (booking(status: 'PENDING_CARRIER_ACCEPT'), lane(), null),
        'part 1': (needsBill, lane(), null),
        'bill without truck': (
          booking(
              ewayBill: billNoTruck,
              extra: {'assignedTruckNumber': 'KA01AB1234'}),
          lane(),
          null
        ),
        'checking': (booking(ewayBill: billWithTruck), lane(), null),
        'problem': (
          booking(ewayBill: {
            ...billWithTruck,
            'check': {'result': 'PROBLEM', 'problemReason': 'NOT_FOUND'}
          }),
          lane(),
          null
        ),
        'not needed': (booking(ewayBill: notNeededBill), lane(), null),
        'in transit': (
          booking(ewayBill: notNeededBill),
          lane(status: 'IN_PROGRESS', started: leftAt),
          null
        ),
        'delivery confirmed': (
          booking(status: 'PENDING_RELEASE', ewayBill: billWithTruck, extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
            'paymentHoldUntilUtcMs': deliveredAt
                .add(const Duration(hours: 48))
                .millisecondsSinceEpoch,
          }),
          lane(status: 'COMPLETED', started: leftAt),
          null
        ),
        'delivered': (
          booking(status: 'DELIVERED', ewayBill: billWithTruck, extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
            'podAcceptedAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          }),
          lane(status: 'COMPLETED', started: leftAt),
          {'status': 'CAPTURED', 'amountPaise': 264000}
        ),
        'cancelled': (
          booking(status: 'FAILED_CARRIER_REFUNDED'),
          lane(),
          {'status': 'REFUNDED', 'amountPaise': 264000}
        ),
      };
      for (final MapEntry(key: name, value: (shipment, trip, payment))
          in states.entries) {
        await showShipment(tester, shipment,
            trip: trip, payment: payment, height: 800);
        await expectNoOverflowToTheEnd(tester, 'the shipment, $name');
        await leave(tester);
      }
    });

    testWidgets('the bill form, the shipments list and Updates fit',
        (tester) async {
      useDoubleTextSize(tester);
      await showShipment(tester, needsBill, trip: lane(), height: 800);
      await scrollTo(tester, find.text('I have made it. Enter the details'));
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'the bill form');
      await leave(tester);

      final server =
          await showShipperApp(tester, '/customer/shipments', height: 800);
      server.answers['/shipments'] = {
        'shipments': [
          needsBill,
          booking(id: 'shp_done', status: 'DELIVERED'),
        ]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      server.answers['/v1/notifications/shipments'] = {
        'shipments': [
          {
            'shipmentId': 'shp_9f2c41',
            'latestAtUtcMs': leftAt.millisecondsSinceEpoch,
            'unreadCount': 2
          },
          {
            'shipmentId': 'shp_gone',
            'latestAtUtcMs': bookedAt.millisecondsSinceEpoch,
            'unreadCount': 0
          },
        ],
        'unreadCount': 2
      };
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Shipments');

      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Updates'));
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxScreen), findsOneWidget);
      await expectNoOverflowToTheEnd(tester, 'Updates');
      // Closes the inbox, whose 30 second poll would otherwise outlive the test.
      await leave(tester);
    });
  });
}
