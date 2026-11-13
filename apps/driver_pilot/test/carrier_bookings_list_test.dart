// The office's Bookings list (ca-bookings, PR 6 of the redesign): the groups, and what each card says.
import 'package:driver_pilot/driver_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/carrier_office_bookings.dart';

void main() {
  group('The Bookings list', () {
    final active = {
      ...shipmentOnTripA(),
      'id': 'shipment-c',
      'customerOrgName': 'Active Shipper',
      'ewayBill': {
        'kind': 'BILL',
        'billNumber': '341200987654',
        'truckNumber': 'KA01AB1234'
      },
    };

    testWidgets(
        'groups bookings under Needs you, Active and Done, with no Accept on any card',
        (tester) async {
      signInAsOwner();
      answer(
          bookings: [pending(), truckMissing(), active, delivered()],
          trips: [trip()]);
      await mountRouted(tester, const DriverShipmentsScreen());
      expect(find.text('Needs you (1)'), findsOneWidget,
          reason:
              'copy.md: Needs you ([n]); a missing truck is the shipper\'s to add, so it is not counted');
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Synthetic Shipper A'), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget,
          reason: 'ca-bookings: status word, never PENDING_CARRIER_ACCEPT');
      expect(find.text('Bengaluru to Hosur'), findsOneWidget,
          reason: '[pickup] to [drop]');
      expect(find.text('Leaves 18 – 19 Oct · 120 kg'), findsOneWidget,
          reason:
              'the days the truck can leave and the weight; no e-way bill answer is stored yet');
      final nextLines = screenWords(tester);
      expect(nextLines, contains('Next: accept and choose the truck.'));
      expect(find.byType(FilledButton), findsNothing,
          reason:
              'ca-bookings: the whole card opens; Accept is on the booking');
      expect(find.text('Active Shipper'), findsNothing,
          reason: 'only Needs you shows at first');

      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(find.text('Active Shipper'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Synthetic Shipper A'), findsNothing);
      expect(find.text('Lakshmi Foods'), findsOneWidget,
          reason: 'a booking whose bill lacks the truck is active, not waiting on the carrier');
      expect(find.text('Truck not on bill'), findsOneWidget,
          reason: 'the carrier pays check-post fines, so it still sees the state');
      expect(find.text('120 kg'), findsOneWidget,
          reason:
              'the status and Next: already say the truck is missing, so the card adds no bill words');
      expect(find.text('Leaves 18 – 19 Oct · 120 kg · Truck on the e-way bill'),
          findsOneWidget,
          reason: "the booking's own step words for a bill with the truck");
      expect(find.textContaining('E-way bill: needed'), findsNothing,
          reason: 'owner run: a saved bill is not "needed"');
      final activeNextLines = screenWords(tester);
      expect(activeNextLines,
          contains('Next: Lakshmi Foods adds the truck to the e-way bill.'),
          reason: 'the carrier is told who acts, not asked to');
      expect(activeNextLines,
          isNot(contains('Next: add the truck to the e-way bill.')));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for payment'), findsOneWidget,
          reason: 'the owner reads the payment status');

      await tester.tap(find.text('Synthetic Shipper A'));
      await tester.pumpAndSettle();
      expect(find.text('Booking page shipment-a'), findsOneWidget,
          reason: 'the card opens its booking');
    });
  });

  testWidgets(
      "a Done card says the shipper's bill and truck are on it, never \"needed\"",
      (tester) async {
    signInAsOwner();
    answer(bookings: [
      {
        ...delivered(),
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987654',
          'truckNumber': 'KA01AB1234',
          'check': {'result': 'FOUND'},
        },
      },
      {
        ...delivered(),
        'id': 'shipment-d',
        'customerOrgName': 'Mehta Hardware',
        'status': 'DELIVERED',
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987655',
          'truckNumber': 'KA01AB1234',
        },
      },
    ], trips: [
      trip()
    ]);
    await mountRouted(tester, const DriverShipmentsScreen());
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Leaves 18 – 19 Oct · 120 kg · E-way bill checked'),
        findsOneWidget,
        reason: "owner run: the booking's own steps say the bill was checked");
    expect(find.text('Leaves 18 – 19 Oct · 120 kg · Truck on the e-way bill'),
        findsOneWidget,
        reason: 'a bill with the truck, not checked yet');
    expect(find.textContaining('E-way bill: needed'), findsNothing,
        reason: 'owner run: a delivered booking with a saved bill read "needed"');

    await mountRouted(tester, const DriverShipmentsScreen(key: ValueKey(2)),
        size: const Size(360, 800), textScale: 2);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'spec: works at 360 dp and 200% text');
  });

  testWidgets(
      'a card never says "Truck on the e-way bill" while the booking shows a problem with the bill',
      (tester) async {
    signInAsOwner();
    answer(bookings: [
      {
        ...shipmentOnTripA(),
        'id': 'shipment-f',
        'customerOrgName': 'Flagged Shipper',
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987654',
          'truckNumber': 'KA01AB1234',
          'check': {'result': 'PROBLEM'},
        },
      },
      {
        ...shipmentOnTripA(),
        'id': 'shipment-w',
        'customerOrgName': 'Wrong Truck Shipper',
        'assignedTruckNumber': 'KA05CD5678',
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987655',
          'truckNumber': 'KA01AB1234',
        },
      },
    ], trips: [
      trip()
    ]);
    await mountRouted(tester, const DriverShipmentsScreen());
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('Flagged Shipper'), findsOneWidget);
    expect(find.text('Wrong Truck Shipper'), findsOneWidget);
    expect(find.textContaining('Truck on the e-way bill'), findsNothing,
        reason: 'review: ops flagged one bill and the other names another truck');
    expect(find.text('Leaves 18 – 19 Oct · 120 kg · E-way bill has a problem'),
        findsNWidgets(2),
        reason: "the booking's own steps show a problem for both");

    await mountRouted(tester, const DriverShipmentsScreen(key: ValueKey(2)),
        size: const Size(360, 800), textScale: 2);
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'spec: works at 360 dp and 200% text');
  });

  testWidgets(
      'a card says the e-way bill time has passed once its valid-until time has gone, until the booking closes',
      (tester) async {
    signInAsOwner();
    final gone = DateTime.utc(2020).millisecondsSinceEpoch;
    answer(bookings: [
      {
        ...shipmentOnTripA(),
        'id': 'shipment-l',
        'customerOrgName': 'Lapsed Shipper',
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987654',
          'truckNumber': 'KA01AB1234',
          'check': {'result': 'FOUND'},
          'validUntilUtcMs': gone,
        },
      },
      {
        ...delivered(),
        'status': 'DELIVERED',
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987655',
          'truckNumber': 'KA01AB1234',
          'check': {'result': 'FOUND'},
          'validUntilUtcMs': gone,
        },
      },
    ], trips: [
      trip()
    ]);
    await mountRouted(tester, const DriverShipmentsScreen());
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('Leaves 18 – 19 Oct · 120 kg · E-way bill time has passed'),
        findsOneWidget,
        reason: 'review: the card said "E-way bill checked" after the valid-until time');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Leaves 18 – 19 Oct · 120 kg · E-way bill checked'),
        findsOneWidget,
        reason: 'a delivered booking needs the bill no more');
  });
}
