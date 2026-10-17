// The carrier's e-way bill card, on its own and on the carrier detail screen. The shipper's card is in
// eway_bill_card_test.dart.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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
            "This is the shipper's statement. naviG8r has not checked it."),
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
        find.text(
            'Ops saw on the portal that this bill was cancelled on 14 Oct 2026. The shipper can see this on their shipment.'),
        findsOneWidget,
        reason: 'the carrier is not told to act');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsOneWidget,
        reason: 'says what is not checked');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'read only');
    expect(find.byType(FilledButton), findsNothing, reason: 'read only');
  });

  testWidgets(
      'a carrier owner sees the truck buttons and the portal, and saves on the carrier path',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    final launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    String? path;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      path = request.path;
      return jsonResponse({
        'shipment': shipment(
            bill: withTruck({'kind': 'BILL', 'billNumber': '123456789012'}))
      });
    });
    await mountCard(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(
        find.text(
            'Add the truck on the portal before the goods move, then enter it here.'),
        findsOneWidget,
        reason: 'ca-booking-truck: the carrier is told its part');
    expect(find.text('E-way bill number'), findsOneWidget,
        reason: 'ca-booking-truck: the bill number is a copy row');
    expect(find.text('Portal: Update Part B, find the bill by this number'),
        findsOneWidget,
        reason: 'the copy row says where it goes on the portal');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsOneWidget,
        reason: 'no truck yet, so the original caveat stays');
    expect(find.widgetWithText(FilledButton, 'Add truck'), findsOneWidget,
        reason:
            'owners and dispatchers can add the truck; it is the step\'s primary action');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'the owner gets the portal link');
    await tester.tap(find.text('Open the government e-way bill portal'));
    await tester.pump();
    expect(launcher.opened, ['https://ewaybillgst.gov.in'],
        reason: 'the portal link opens the portal address');
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'KA01AB1234');
    await chooseTodayAtLastMinute(tester);
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(path, '/v1/pilot/carrier/shipments/shipment-a/eway-bill/truck');
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the saved truck shows');
    expect(
        find.text(
            'Shown as entered in naviG8r. naviG8r has not made or changed this bill, and has not checked it against the portal.'),
        findsOneWidget,
        reason: 'with a truck, the caveat names the portal');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsNothing,
        reason: 'the old caveat no longer fits');
    expect(find.widgetWithText(OutlinedButton, 'Change truck'), findsOneWidget,
        reason: 'the truck can be changed');
  });

  testWidgets('the 15 second refresh never wipes a carrier half typed truck',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    final bill = {'kind': 'BILL', 'billNumber': '123456789012'};
    final current = ValueNotifier(shipment(bill: bill));
    await mountRefreshingCard(
        tester,
        current,
        (value) =>
            EwayBillCarrierCard(key: const ValueKey('card'), shipment: value));
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'HALF-TYPED');
    current.value = {...shipment(bill: bill), 'extra': 1};
    await tester.pump();
    expect(find.text('HALF-TYPED'), findsOneWidget,
        reason: 'typed text survives a refresh');
  });

  testWidgets('a carrier owner gets no truck buttons once delivered',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    await mountCard(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                status: 'DELIVERED',
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(find.text('Add truck'), findsNothing,
        reason: 'locked once delivered');
    expect(find.text('Open the government e-way bill portal'), findsNothing,
        reason: 'nothing to do on the portal once delivered');
  });

  testWidgets('a driver sees the truck lines but no buttons and no portal link',
      (tester) async {
    signInAsCarrier(canAddTruck: false);
    await mountCard(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: withTruck(
                    {'kind': 'BILL', 'billNumber': '123456789012'}))));
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the number to quote at a check-post');
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the truck on the bill');
    expect(find.text('Valid until: 16 Oct 2026, 23:59 (India time)'),
        findsOneWidget,
        reason: 'the valid-until time in India');
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
    expect(find.text('Truck not added yet.'), findsOneWidget,
        reason: 'a driver is not told to add it');
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
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
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
      'the carrier detail screen fits a 360 by 640 phone for an owner with a truck on the bill',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
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
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the truck shows');
    expect(find.textContaining('Expires in'), findsOneWidget,
        reason: 'the countdown shows inside the last 12 hours');
    expect(find.textContaining('The details here did not match the portal'),
        findsOneWidget,
        reason: 'the longest check line');
    expect(find.text('Change truck'), findsOneWidget,
        reason: 'the owner can change the truck');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'the owner has the portal link');
    expect(find.text('Truck on the e-way bill'), findsOneWidget,
        reason: 'the bill shows inside its step on the booking screen');
    expect(tester.takeException(), isNull,
        reason: 'no overflow on a small phone');
  });
}
