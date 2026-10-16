// The shipper's "For the e-way bill" box (owner decision, 16 Oct 2026): the trip's truck in the portal's form and
// the carrier's transporter ID, ready to copy, from acceptance until the bill has its truck or the driver confirms
// delivery; and the shipper's truck form filled in from the trip.
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';

const withTransporterIdLine =
    'On the portal, enter this transporter ID so your carrier can change the truck later. Validity starts when the truck is entered, so enter it on loading day.';
const withoutTransporterIdLine =
    'Your carrier has not added its transporter ID yet. Without one on the bill, only you can change the truck later. Validity starts when the truck is entered, so enter it on loading day.';

/// An accepted shipment whose trip names a truck, written as a carrier might have typed it.
Map<String, dynamic> acceptedShipment(
        {Map<String, dynamic>? bill,
        String status = 'BOOKED',
        String? transporterId = '29ABCDE1234F1Z5'}) =>
    {
      ...shipment(bill: bill, status: status),
      'assignedTruckNumber': 'UP1345',
      if (transporterId != null) 'carrierTransporterId': transporterId,
    };

/// The Copy button on the line that starts with [label].
Finder copyButtonFor(String label) => find.descendant(
    of: find.ancestor(
        of: find.textContaining('$label: '), matching: find.byType(Row)),
    matching: find.widgetWithText(TextButton, 'Copy'));

void main() {
  setUp(signInAsShipper);

  testWidgets(
      'shows the truck in the portal form and the transporter ID, each with Copy, before any bill is added',
      (tester) async {
    await mountCard(tester, EwayBillCard(shipment: acceptedShipment()));
    expect(find.text('For the e-way bill'), findsOneWidget);
    expect(find.text('Truck: UP010345'), findsOneWidget);
    expect(find.text('Transporter ID: 29ABCDE1234F1Z5'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Copy'), findsNWidgets(2));
    expect(find.text(withTransporterIdLine), findsOneWidget);
    expect(find.text(withoutTransporterIdLine), findsNothing);
  });

  testWidgets(
      'without a transporter ID it shows the truck only and says the carrier has not added one',
      (tester) async {
    await mountCard(tester,
        EwayBillCard(shipment: acceptedShipment(transporterId: null)));
    expect(find.text('Truck: UP010345'), findsOneWidget);
    expect(find.textContaining('Transporter ID:'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Copy'), findsOneWidget);
    expect(find.text(withoutTransporterIdLine), findsOneWidget);
    expect(find.text(withTransporterIdLine), findsNothing);
  });

  testWidgets('Copy puts the value alone on the clipboard', (tester) async {
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
    await mountCard(tester, EwayBillCard(shipment: acceptedShipment()));
    await tester.tap(copyButtonFor('Transporter ID'));
    await tester.pump();
    expect(copied, ['29ABCDE1234F1Z5']);
    expect(find.text('Copied transporter ID'), findsOneWidget);
    await tester.tap(copyButtonFor('Truck'));
    await tester.pump();
    expect(copied, ['29ABCDE1234F1Z5', 'UP010345']);
  });

  testWidgets(
      'stays while the bill has no truck, and goes once it has one, before acceptance, after delivery, or with no bill needed',
      (tester) async {
    final cases = <String, (Map<String, dynamic>, bool)>{
      'a bill with no truck yet': (acceptedShipment(bill: savedBill), true),
      'after the driver confirms delivery': (
        acceptedShipment(status: 'PENDING_RELEASE'),
        false
      ),
      'a bill with its truck': (
        acceptedShipment(bill: withTruck(savedBill)),
        false
      ),
      'not yet accepted': (
        acceptedShipment(status: 'PENDING_CARRIER_ACCEPT'),
        false
      ),
      'delivered': (acceptedShipment(status: 'DELIVERED'), false),
      'no bill needed': (
        acceptedShipment(bill: {
          'kind': 'NOT_NEEDED',
          'notNeededReason': 'BELOW_THRESHOLD'
        }),
        false
      ),
      'a trip that names no truck': (
        {...shipment(), 'carrierTransporterId': '29ABCDE1234F1Z5'},
        false
      ),
    };
    for (final entry in cases.entries) {
      final (shipmentNow, shows) = entry.value;
      await mountCard(tester,
          EwayBillCard(key: ValueKey(entry.key), shipment: shipmentNow));
      expect(find.text('For the e-way bill'),
          shows ? findsOneWidget : findsNothing,
          reason: entry.key);
    }
  });

  testWidgets(
      "the shipper's truck form starts with the trip's truck in the portal form",
      (tester) async {
    signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
    await mountCard(
        tester, EwayBillCard(shipment: acceptedShipment(bill: savedBill)));
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Truck number'))
            .controller!
            .text,
        'UP010345');
    expect(
        find.text(
            'Filled in from the truck on this trip. Change it if the e-way bill shows a different truck.'),
        findsOneWidget);
  });
}
