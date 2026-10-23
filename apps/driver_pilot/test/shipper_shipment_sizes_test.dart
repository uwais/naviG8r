// The shipper's shipment screens at other sizes (PRs 9 and 10 of the redesign): every state at 200% text
// on a 360 dp phone, and the desktop layout at 1280.
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_list_card.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shipper_screen_checks.dart';
import 'support/shipper_shipment_app.dart';

const noCancelLine =
    'To change or cancel, email ${PendingCopy.changeOrCancelContact}.';

void main() {
  textSizeTests();
  desktopTests();
  doubleTextAt800Tests();
}

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
      await tester.tap(find.text('Enter the bill details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: the bill form fits at 200% text');
      await leave(tester);
    });
  });
}

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
              'Waiting for Deccan Movers to accept.'),
          findsOneWidget,
          reason: 'the route link opens the shipment');
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
      await scrollTo(tester, find.text('Enter the bill details'));
      await tester.tap(find.text('Enter the bill details'));
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
