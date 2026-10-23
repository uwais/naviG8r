// Where the shipper's shipments show outside their own screen (sh-shipments, sh-home, sh-notifications;
// PR 5a of the redesign): the Shipments list's Next: line, the Home task, and Updates.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';
import 'support/shipper_screen_checks.dart';
import 'support/shipper_shipment_app.dart';

void main() {
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
      expect(find.text('On the way'), findsOneWidget);
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
              'Waiting for Deccan Movers to accept.'),
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
        'a bill whose truck is not the trip truck is a Home task and a Next: line, since it holds the trip',
        (tester) async {
      final ahead = DateTime.now().add(const Duration(days: 2));
      final holdsTheTrip = booking(ewayBill: {
        ...billWithTruck,
        'validUntilUtcMs': ahead.millisecondsSinceEpoch
      }, extra: {
        'assignedTruckNumber': 'KA02XY9999'
      });
      final server = await showShipperApp(tester, '/customer');
      server.answers['/shipments'] = {
        'shipments': [holdsTheTrip]
      };
      server.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      await tester.pumpAndSettle();
      expect(find.text('Fix the e-way bill'), findsOneWidget,
          reason: 'the shipper was never told their bill holds the trip');
      expect(
          find.text(
              'Bengaluru to Chennai, ${formatDate(laneStart)}. The trip cannot start until the truck and valid-until time on the bill are right.'),
          findsOneWidget);
      expect(find.textContaining('NaviG8r found a problem'), findsNothing,
          reason: 'nobody at NaviG8r flagged this bill');

      await leave(tester);
      final list = await showShipperApp(tester, '/customer/shipments');
      list.answers['/shipments'] = {
        'shipments': [holdsTheTrip]
      };
      list.answers['/anchor-trips'] = {
        'trips': [lane()]
      };
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Next: You check the truck and valid-until time on the e-way bill.'),
          findsOneWidget);
      expect(find.text('Needs you'), findsOneWidget,
          reason: 'the list marks the shipper task; the status word is on the shipment screen');
      await leave(tester);
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
              'Check the goods. Accepting is optional.'),
          findsOneWidget,
          reason:
              "owner's 22 Oct call: Home says it in one line; the hold rule lives on the shipment screen and the Accept confirmation, not on Home");
      expect(find.textContaining('48-hour hold'), findsNothing,
          reason: "owner's 22 Oct call: the hold rule is not on Home");
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
