// PRs 5a and 5b of the redesign: the shipment screen as numbered steps, the e-way bill steps with
// copy rows, the shipments list "Next:" line, the Home card and Updates (sh-ship-*, sh-ewb-*,
// sh-shipments, sh-notifications). Names, places and amounts are the mockups' synthetic ones.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

final bookedAt = DateTime.utc(2026, 10, 17, 3, 30);
final laneStart = DateTime.utc(2026, 10, 18, 3, 30);
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

/// A phone 360 dp wide, signed in as a Sharma Textiles shipper who may write the bill and add
/// the truck. [height] is 800 for "visible without scrolling" checks; taller elsewhere, because the
/// test font draws every letter a full square wide.
Future<FakeServer> showShipperApp(WidgetTester tester, String start,
    {double height = 3000}) async {
  tester.view.physicalSize = Size(360, height);
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
    return jsonResponse(answer ?? {});
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

/// Opens [shipment]'s screen with the trip the tracking call returns.
Future<FakeServer> showShipment(
    WidgetTester tester, Map<String, dynamic> shipment,
    {Map<String, dynamic>? trip,
    Map<String, dynamic>? payment,
    double height = 3000}) async {
  final server = await showShipperApp(
      tester, '/customer/shipments/${shipment['id']}',
      height: height);
  server.answers['/shipments/${shipment['id']}'] = {
    'shipment': shipment,
    if (payment != null) 'payment': payment,
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

/// Records what a screen reader is told.
List<String> watchAnnouncements(WidgetTester tester) {
  final announced = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (message) async {
    if ((message as Map)['type'] == 'announce') {
      announced.add((message['data'] as Map)['message'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, null));
  return announced;
}

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
              'Nothing for you to do now. Ravi Roadways starts the trip on ${formatDate(laneStart)}.'),
          findsOneWidget,
          reason: 'sh-ship-noewb: who acts next, and when');
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
      expect(find.text('Refunded'), findsOneWidget,
          reason: 'the payment says it was refunded');
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
              'Make the bill on the government portal. Copy these two in:'),
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
      expect(find.text('You or Ravi Roadways'), findsOneWidget,
          reason: 'screens.md: either may add the truck');
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
              'NaviG8r staff check the bill on the portal by hand. We will tell you if anything needs fixing.'),
          findsOneWidget,
          reason: 'copy.md step 4: who checks, and how');
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
      expect(find.textContaining('shp_'), findsNothing, reason: 'never an ID');
      server.answers['/shipments/shp_waiting'] = {
        'shipment': (server.answers['/shipments'] as Map)['shipments'][2]
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
