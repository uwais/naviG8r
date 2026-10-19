// The carrier's e-way bill card, on its own and on the carrier detail screen. The shipper's card is in
// eway_bill_card_test.dart.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

void main() {
  setUp(signInAsShipper);

  testWidgets('the carrier card shows each state read only, with no buttons',
      (tester) async {
    await mountCard(tester, EwayBillCarrierCard(shipment: shipment()));
    expect(
        find.text(
            'Synthetic Shipper A has not added an e-way bill or said none is needed.'),
        findsOneWidget,
        reason: 'neutral, no pressure');
    await mountCard(
        tester,
        EwayBillCarrierCard(
            key: UniqueKey(),
            shipment: shipment(bill: {
              'kind': 'NOT_NEEDED',
              'notNeededReason': 'GOODS_EXEMPT'
            })));
    expect(
        find.textContaining(
            "This is the shipper's statement. NaviG8r has not checked it."),
        findsOneWidget,
        reason: 'the statement is the shipper\'s');
    await mountCard(
        tester,
        EwayBillCarrierCard(
            key: UniqueKey(),
            shipment: shipment(bill: {
              'kind': 'BILL',
              'billNumber': '123456789012',
              'check': {
                'result': 'PROBLEM',
                'problemReason': 'CANCELLED',
                'checkedAtUtcMs': 1792000000000
              }
            })));
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'number in groups of four');
    expect(
        find.textContaining(RegExp(
            r'^Ops saw on the portal that this bill was cancelled on 14 Oct( 2026)?\. The shipper can see this on their shipment\.$')),
        findsOneWidget,
        reason:
            'the carrier is not told to act; copy.md Formats: the year only when it is not this year');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsOneWidget,
        reason: 'says what is not checked');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'read only');
    expect(find.byType(FilledButton), findsNothing, reason: 'read only');
  });

  testWidgets(
      'a carrier office reads a bill without the truck: the shipper adds it, no form, no pickers, no portal',
      (tester) async {
    signInAsCarrier(office: true);
    final requests = <String>[];
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      requests.add(request.path);
      return jsonResponse({});
    });
    await mountCard(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the carrier still sees which bill it is');
    expect(
        find.text('Synthetic Shipper A has not added the truck to the bill yet.'),
        findsOneWidget,
        reason:
            'owner decision 18 Oct 2026: the shipper adds the truck; the carrier is told, not asked');
    expect(find.text('Not checked yet.'), findsOneWidget,
        reason: 'the ops check state shows');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsOneWidget,
        reason: 'no truck yet, so the original caveat stays');
    for (final words in [
      'Add truck',
      'Change truck',
      'Save truck',
      'Add the truck on the portal before the goods move, then enter it here.',
      'Portal: Update Part B, find the bill by this number',
      'Open the government e-way bill portal',
      'Valid until, date in India: choose the date',
      'Time in India: choose the time',
    ]) {
      expect(find.text(words), findsNothing, reason: 'read only: "$words"');
    }
    expect(find.byType(TextField), findsNothing, reason: 'no truck form');
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'no date or time picker buttons');
    expect(find.byType(FilledButton), findsNothing, reason: 'read only');
    expect(find.byType(TextButton), findsNothing, reason: 'read only');
    expect(requests, isEmpty, reason: 'the card never writes to the server');
  });

  testWidgets(
      'a carrier office reads the truck and valid-until on the bill, with nothing to change',
      (tester) async {
    signInAsCarrier(office: true);
    await mountCard(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: withTruck(
                    {'kind': 'BILL', 'billNumber': '123456789012'}))));
    expect(find.text('Truck on the bill: KA01AB1234'), findsOneWidget,
        reason: 'the truck the shipper put on the bill');
    expect(
        find.textContaining(
            RegExp(r'^Valid until: 16 Oct( 2026)?, 23:59 IST$')),
        findsOneWidget,
        reason: 'the valid-until time the shipper entered');
    expect(
        find.text(
            'Shown as entered in NaviG8r. NaviG8r has not made or changed this bill, and has not checked it against the portal.'),
        findsOneWidget,
        reason: 'with a truck, the caveat names the portal');
    expect(find.text('Change truck'), findsNothing, reason: 'read only');
    expect(find.text('Open the government e-way bill portal'), findsNothing,
        reason: 'nothing for the carrier to do on the portal');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'read only');
  });

  testWidgets('the 15 second refresh shows the truck once the shipper adds it',
      (tester) async {
    signInAsCarrier(office: true);
    final bill = {'kind': 'BILL', 'billNumber': '123456789012'};
    final current = ValueNotifier(shipment(bill: bill));
    await mountRefreshingCard(
        tester,
        current,
        (value) =>
            EwayBillCarrierCard(key: const ValueKey('card'), shipment: value));
    expect(
        find.text('Synthetic Shipper A has not added the truck to the bill yet.'),
        findsOneWidget);
    current.value = shipment(bill: withTruck(bill));
    await tester.pump();
    expect(find.text('Truck on the bill: KA01AB1234'), findsOneWidget,
        reason: 'the card shows what the server now holds');
    expect(
        find.text('Synthetic Shipper A has not added the truck to the bill yet.'),
        findsNothing);
  });

  testWidgets('a driver sees the truck lines but no buttons and no portal link',
      (tester) async {
    signInAsCarrier(office: false);
    await mountCard(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: withTruck(
                    {'kind': 'BILL', 'billNumber': '123456789012'}))));
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the number to quote at a check-post');
    expect(find.text('Truck on the bill: KA01AB1234'), findsOneWidget,
        reason: 'the truck on the bill');
    expect(
        find.textContaining(
            RegExp(r'^Valid until: 16 Oct( 2026)?, 23:59 IST$')),
        findsOneWidget,
        reason:
            'the valid-until time in India; copy.md Formats: time as 16:40 IST, the year only when it is not this year');
    expect(find.textContaining('has not checked it against the portal'),
        findsOneWidget,
        reason: 'the caveat for a bill with a truck');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'read only');
    expect(find.byType(FilledButton), findsNothing, reason: 'read only');
    expect(find.text('Open the government e-way bill portal'), findsNothing,
        reason: 'a driver has nothing to do on the portal');
    await mountCard(
        tester,
        EwayBillCarrierCard(
            key: UniqueKey(),
            shipment: shipment(
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(
        find.text('Synthetic Shipper A has not added the truck to the bill yet.'),
        findsOneWidget,
        reason: 'a driver is told who adds it, not asked to');
  });

  testWidgets(
      'the carrier detail screen fits a 360 by 640 phone with the card on it',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': [
        'load.read',
        'carrier.offer_accept',
        'pod.upload',
        'conversation.read'
      ]
    };
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'shipments': [
            {
              // Accepted: before acceptance the booking screen shows the bill only as a fact.
              ...shipment(),
              'pickupAddress': 'Synthetic pickup address, Bengaluru',
              'dropAddress': 'Synthetic drop address, Chennai',
              'netToCarrierPaise': 250000,
              'ewayBill': {
                'kind': 'BILL',
                'billNumber': '123456789012',
                'truckNumber': 'KA01AB1234',
                'validUntilUtcMs': 1792000000000,
                'check': {
                  'result': 'PROBLEM',
                  'problemReason': 'DETAILS_DO_NOT_MATCH',
                  'checkedAtUtcMs': 1792000000000
                }
              }
            }
          ]
        }));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
    await tester.pumpAndSettle();
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the bill shows on the detail screen');
    expect(find.text('Truck on the bill: KA01AB1234'), findsOneWidget,
        reason: 'the driver sees the truck');
    expect(
        find.text('The valid-until time entered has passed. Check the portal.'),
        findsOneWidget,
        reason: 'a past valid-until time is reported as typed, not as expired');
    expect(find.text('Change truck'), findsNothing,
        reason: 'a driver cannot change the truck');
    expect(find.text('Truck on the e-way bill'), findsOneWidget,
        reason: 'the bill shows inside its step on the booking screen');
    expect(tester.takeException(), isNull,
        reason: 'no overflow on a small phone');
  });

  testWidgets(
      'the carrier detail screen fits a 360 by 640 phone for an owner with a truck on the bill, read only',
      (tester) async {
    signInAsCarrier(office: true);
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'shipments': [
            {
              // Accepted: before acceptance the booking screen shows the bill only as a fact.
              ...shipment(),
              'customerOrgName':
                  'Synthetic Shipper With A Very Long Registered Business Name Private Limited',
              'pickupAddress': 'Synthetic pickup address, Bengaluru',
              'dropAddress': 'Synthetic drop address, Chennai',
              'netToCarrierPaise': 250000,
              'ewayBill': {
                'kind': 'BILL',
                'billNumber': '123456789012',
                'truckNumber': 'KA01AB1234',
                // Inside the last 12 hours, so the countdown line shows too.
                'validUntilUtcMs': DateTime.now()
                    .add(const Duration(hours: 11))
                    .millisecondsSinceEpoch,
                'check': {
                  'result': 'PROBLEM',
                  'problemReason': 'DETAILS_DO_NOT_MATCH',
                  'checkedAtUtcMs': 1792000000000
                }
              }
            }
          ]
        }));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
    await tester.pumpAndSettle();
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the bill shows on the detail screen');
    expect(find.text('Truck on the bill: KA01AB1234'), findsOneWidget,
        reason: 'the truck shows');
    expect(find.textContaining('Expires in'), findsOneWidget,
        reason: 'the countdown shows inside the last 12 hours');
    expect(find.textContaining('The details here did not match the portal'),
        findsOneWidget,
        reason: 'the longest check line');
    expect(find.text('Change truck'), findsNothing,
        reason: 'the shipper changes the truck on the bill, not the carrier');
    expect(find.text('Open the government e-way bill portal'), findsNothing,
        reason: 'nothing for the carrier to do on the portal');
    expect(find.text('Truck on the e-way bill'), findsOneWidget,
        reason: 'the bill shows inside its step on the booking screen');
    expect(tester.takeException(), isNull,
        reason: 'no overflow on a small phone');
  });
}
