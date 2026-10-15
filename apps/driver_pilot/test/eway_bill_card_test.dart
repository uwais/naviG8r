// The shipper's e-way bill card. The last test also mounts the carrier's card, because both must start
// clean when a different shipment takes their place. The rest of the carrier's card is in
// eway_bill_carrier_card_test.dart; the truck form, and the shipper adding a truck through it, are in
// eway_bill_truck_form_test.dart.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

void main() {
  setUp(signInAsShipper);

  testWidgets('with nothing added, two equal buttons and no choice made',
      (tester) async {
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'the empty state says nothing is added');
    expect(
        find.widgetWithText(OutlinedButton, 'Add e-way bill'), findsOneWidget,
        reason: 'first equal choice');
    expect(find.widgetWithText(OutlinedButton, 'No e-way bill needed'),
        findsOneWidget,
        reason: 'second equal choice');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'link-out to the portal');
    await tester.tap(find.text('No e-way bill needed'));
    await tester.pump();
    expect(find.text('Why is no e-way bill needed?'), findsOneWidget,
        reason: 'the statement form opens');
    final choices = tester
        .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>));
    expect(choices.length, 3, reason: 'three reasons');
    expect(choices.every((choice) => choice.groupValue == null), isTrue,
        reason: 'no reason is preselected');
  });

  testWidgets(
      'adding a bill sends the four details, then shows the number in groups of four and the unchecked state',
      (tester) async {
    Map? sent;
    final now = DateTime.now();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      expect(request.path, '/shipments/shipment-a/eway-bill');
      sent = request.data as Map;
      return jsonResponse({'shipment': shipment(bill: savedBill)});
    });
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    expect(find.textContaining('All four are needed to save'), findsOneWidget,
        reason: 'says all four are required');
    expect(
        find.text('Used only by naviG8r ops to find the bill on the portal.'),
        findsNWidgets(2),
        reason: 'says why GSTIN and invoice number are asked');
    await tester.tap(find.text('Save e-way bill'));
    await tester.pump();
    expect(find.text('Fill in all four details to save.'), findsOneWidget,
        reason: 'nothing is sent until all four are filled');
    expect(sent, isNull, reason: 'no request for an incomplete form');
    await tester.enterText(
        field('E-way bill number (12 digits)'), '1234 5678 9012');
    await tester.enterText(
        field('GSTIN of whoever made the bill'), '29ABCDE1234F1Z5');
    await tester.enterText(field('Invoice number'), 'INV/1');
    await tester.tap(find.text('Bill date: choose the date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    expect(sent, {
      'kind': 'BILL',
      'billNumber': '1234 5678 9012',
      'billDate': '${now.year}-$month-$day',
      'makerGstin': '29ABCDE1234F1Z5',
      'invoiceNumber': 'INV/1',
    });
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'number in groups of four');
    expect(find.text('Entered by you. Not checked yet.'), findsOneWidget,
        reason: 'a saved bill starts unchecked');
    expect(find.text('Remove e-way bill'), findsOneWidget,
        reason: 'removing is as easy as adding');
  });

  testWidgets("a refusal shows the server's sentence, never HTTP 400",
      (tester) async {
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'error': 'invalid_eway_bill',
          'detail': 'The e-way bill number is 12 digits.',
          'field': 'billNumber'
        }, 400));
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    await tester.enterText(field('E-way bill number (12 digits)'), '1');
    await tester.enterText(field('GSTIN of whoever made the bill'), 'X');
    await tester.enterText(field('Invoice number'), 'Y');
    await tester.tap(find.text('Bill date: choose the date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    expect(find.text('The e-way bill number is 12 digits.'), findsOneWidget,
        reason: 'the server sentence is shown');
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw status text');
    expect(find.text('Save e-way bill'), findsOneWidget,
        reason: 'the form stays open with what was typed');
  });

  testWidgets('saying no bill is needed needs a reason, and Other needs words',
      (tester) async {
    Map? sent;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      sent = request.data as Map;
      return jsonResponse({
        'shipment': shipment(bill: {
          'kind': 'NOT_NEEDED',
          'notNeededReason': 'OTHER',
          'notNeededNote': 'Sample goods'
        })
      });
    });
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('No e-way bill needed'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Choose why no e-way bill is needed.'), findsOneWidget,
        reason: 'no reason, no save');
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.enterText(field('Write the reason'), 'Sample goods');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sent,
        {'kind': 'NOT_NEEDED', 'reason': 'OTHER', 'note': 'Sample goods'});
    expect(find.text('You said no e-way bill is needed: Sample goods.'),
        findsOneWidget,
        reason: 'the statement is shown back');
    expect(find.text('Change'), findsOneWidget,
        reason: 'the statement can be changed');
  });

  testWidgets(
      'ops findings are worded as what ops saw and when, never as a guarantee',
      (tester) async {
    final found = {
      ...savedBill,
      'check': {'result': 'FOUND', 'checkedAtUtcMs': 1792000000000}
    };
    await mountCard(tester, EwayBillCard(shipment: shipment(bill: found)));
    expect(
        find.text(
            'Ops saw this bill on the government portal on 14 Oct 2026. It may have changed since.'),
        findsOneWidget,
        reason: 'a date and a caveat');
    expect(find.textContaining('verified'), findsNothing,
        reason: 'the app never says verified');
    final problem = {
      ...savedBill,
      'check': {
        'result': 'PROBLEM',
        'problemReason': 'NOT_FOUND',
        'checkedAtUtcMs': 1792000000000
      }
    };
    await mountCard(tester,
        EwayBillCard(key: UniqueKey(), shipment: shipment(bill: problem)));
    expect(
        find.text(
            'Ops could not find this bill on the portal on 14 Oct 2026. Check the details here and on the portal.'),
        findsOneWidget,
        reason: 'the shipper is told what to do next');
  });

  testWidgets('the 15 second refresh never wipes what is half typed',
      (tester) async {
    final current = ValueNotifier(shipment());
    await mountRefreshingCard(tester, current,
        (value) => EwayBillCard(key: const ValueKey('card'), shipment: value));
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    await tester.enterText(field('Invoice number'), 'HALF-TYPED');
    current.value = {...shipment(), 'status': 'BOOKED', 'extra': 1};
    await tester.pump();
    expect(find.text('HALF-TYPED'), findsOneWidget,
        reason: 'typed text survives a refresh');
  });

  testWidgets('without permission, or after delivery, the card only reads',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': <String>[]
    };
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'still readable');
    expect(find.text('Add e-way bill'), findsNothing,
        reason: 'no write button without permission');
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write']
    };
    await mountCard(
        tester,
        EwayBillCard(
            key: UniqueKey(),
            shipment: shipment(bill: savedBill, status: 'DELIVERED')));
    expect(find.text('Edit'), findsNothing, reason: 'locked once delivered');
    expect(find.text('Remove e-way bill'), findsNothing,
        reason: 'locked once delivered');
  });

  testWidgets('removing sends the remove request and returns to nothing added',
      (tester) async {
    String? path;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      path = request.path;
      return jsonResponse({'shipment': shipment()});
    });
    await mountCard(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Remove e-way bill'));
    await tester.pumpAndSettle();
    expect(path, '/shipments/shipment-a/eway-bill/remove');
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'back to nothing added');
  });

  testWidgets('the portal link opens the government address', (tester) async {
    final launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Open the government e-way bill portal'));
    await tester.pump();
    expect(launcher.opened, ['https://ewaybillgst.gov.in'],
        reason: 'one fixed address');
    launcher.opens = false;
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    await tester.tap(find.text('Open the government e-way bill portal'));
    await tester.pump();
    expect(
        find.text(
            'Could not open the portal from here. Its address is ewaybillgst.gov.in.'),
        findsOneWidget,
        reason: 'the address shown is the one this build opens');
  });

  testWidgets('a different shipment in the same place starts clean',
      (tester) async {
    await mountCard(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.enterText(field('Invoice number'), 'TYPED-FOR-A');
    await mountCard(
        tester, EwayBillCard(shipment: {...shipment(), 'id': 'shipment-b'}));
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'the new shipment\'s own state, form closed');
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    expect(find.text('TYPED-FOR-A'), findsNothing,
        reason: 'nothing typed for the old shipment carries over');

    signInAsCarrier(canAddTruck: true);
    await mountCard(
        tester, EwayBillCarrierCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    expect(find.text('Save truck'), findsOneWidget, reason: 'form open');
    await mountCard(
        tester,
        EwayBillCarrierCard(shipment: {
          ...shipment(bill: {'kind': 'BILL', 'billNumber': '999988887777'}),
          'id': 'shipment-b'
        }));
    expect(find.text('Save truck'), findsNothing,
        reason: 'the old shipment\'s truck form closed');
    expect(find.text('9999 8888 7777'), findsOneWidget,
        reason: 'the new shipment\'s bill shows');
  });
}
