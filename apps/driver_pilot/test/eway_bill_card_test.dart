// The shipper's e-way bill step (sh-ewb-*). The last test also mounts the carrier's card, because
// both must start clean when a different shipment takes their place. The rest of the carrier's
// card is in eway_bill_carrier_card_test.dart; the truck form, and the shipper adding a truck
// through it, are in eway_bill_truck_form_test.dart; the copy rows, the form's own checks and the
// step on the shipment screen are in shipper_eway_bill_steps_test.dart.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/eway_bill_dates.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

/// The text box inside the NvField labelled [label].
Finder entry(String label) => find.descendant(
    of: find.widgetWithText(NvField, label), matching: find.byType(TextField));

const partOneLead =
    'Make the bill in your billing software or on the e-way bill portal. Copy in these details:';

void main() {
  setUp(signInAsShipper);

  testWidgets(
      'accepted with nothing added: part 1, two equal ways on and no choice made',
      (tester) async {
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    expect(find.text(partOneLead), findsOneWidget,
        reason: 'copy.md step 1: the bill is made on the portal');
    expect(
        find.widgetWithText(
            OutlinedButton, 'Enter the bill details'),
        findsOneWidget,
        reason: 'copy.md step 1: the way to part 2');
    expect(find.widgetWithText(OutlinedButton, 'Say no e-way bill is needed'),
        findsOneWidget,
        reason:
            'the existing not-needed statement stays, as an equal choice, not a lesser one');
    expect(find.text(ewayBillFootnote), findsOneWidget,
        reason: 'copy.md footnote: once, small');
    await tester.tap(find.text('Say no e-way bill is needed'));
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
      'adding a bill sends the four details, then shows the number in groups of four and that the truck is missing',
      (tester) async {
    Map? sent;
    final now = indiaToday();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      expect(request.path, '/shipments/shipment-a/eway-bill');
      sent = request.data as Map;
      return jsonResponse({'shipment': shipment(bill: savedBill)});
    });
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Enter the bill details'));
    await tester.pump();
    expect(find.text("Enter the bill's details"), findsOneWidget,
        reason: 'copy.md step 2 heading');
    expect(find.text('Copy these four from the bill.'), findsOneWidget,
        reason: 'copy.md step 2: all four come from the bill');
    expect(find.text('12 digits, at the top of the bill.'), findsOneWidget,
        reason: 'copy.md step 2: where the number is');
    expect(
        find.text(
            "The GSTIN that made the bill. Not the carrier's transporter ID."),
        findsOneWidget,
        reason: 'testers could not tell the GSTIN from the transporter ID');
    await tester.tap(find.text('Save e-way bill'));
    await tester.pump();
    expect(find.text('Fill in all four details to save.'), findsOneWidget,
        reason: 'nothing is sent until all four are filled');
    expect(sent, isNull, reason: 'no request for an incomplete form');
    await tester.enterText(entry('E-way bill number'), '1234 5678 9012');
    await tester.enterText(entry('Your GSTIN'), '29ABCDE1234F1Z5');
    await tester.enterText(entry('Invoice number'), 'INV/1');
    await tester.tap(find.text('Choose the date'));
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
    expect(find.text('Bill 1234 5678 9012 saved. The truck is not on it yet.'),
        findsOneWidget,
        reason: 'copy.md step 3: number in groups of four, truck missing');
    expect(find.text('Remove e-way bill'), findsOneWidget,
        reason: 'removing is as easy as adding');
  });

  testWidgets(
      "the bill date goes up to India's today when the phone is still on yesterday",
      (tester) async {
    // 9:50 pm on 18 Oct in US Eastern is 7:20 am on 19 Oct in India, as on the recorded run.
    ewayBillNow = () => DateTime.utc(2026, 10, 19, 1, 50);
    addTearDown(() => ewayBillNow = DateTime.now);
    Map? sent;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      sent = request.data as Map;
      return jsonResponse({'shipment': shipment(bill: savedBill)});
    });
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Enter the bill details'));
    await tester.pump();
    await tester.enterText(entry('E-way bill number'), '123456789012');
    await tester.enterText(entry('Your GSTIN'), '29ABCDE1234F1Z5');
    await tester.enterText(entry('Invoice number'), 'INV/1');
    await tester.tap(find.text('Choose the date'));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.lastDate, DateTime(2026, 10, 19),
        reason: 'the bill is dated in India, where it is already 19 Oct');
    expect(picker.initialDate, DateTime(2026, 10, 19),
        reason: "the picker opens on India's today");
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    expect(sent?['billDate'], '2026-10-19',
        reason: 'staff compare this with the date on the bill');
  });

  testWidgets("a refusal shows the server's sentence, never HTTP 400",
      (tester) async {
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'error': 'invalid_eway_bill',
          'detail':
              'The GSTIN is 15 letters and digits, for example 29ABCDE1234F1Z5.',
          'field': 'makerGstin'
        }, 400));
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Enter the bill details'));
    await tester.pump();
    await tester.enterText(entry('E-way bill number'), '123456789012');
    await tester.enterText(entry('Your GSTIN'), 'X');
    await tester.enterText(entry('Invoice number'), 'Y');
    await tester.tap(find.text('Choose the date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The GSTIN is 15 letters and digits, for example 29ABCDE1234F1Z5.'),
        findsOneWidget,
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
          'notNeededNote': 'Sample goods',
          'enteredAtUtcMs':
              DateTime.utc(2026, 10, 19, 6).millisecondsSinceEpoch,
        })
      });
    });
    await mountCard(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Say no e-way bill is needed'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Choose why no e-way bill is needed.'), findsOneWidget,
        reason: 'no reason, no save');
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.enterText(entry('Write the reason'), 'Sample goods');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sent,
        {'kind': 'NOT_NEEDED', 'reason': 'OTHER', 'note': 'Sample goods'});
    expect(find.text('You said so on 19 Oct.'), findsOneWidget,
        reason: 'copy.md not needed: when the shipper said so');
    expect(find.text('Reason: Sample goods'), findsOneWidget,
        reason: 'the statement is shown back');
    expect(find.text('Change'), findsOneWidget,
        reason: 'the statement can be changed');
    expect(find.text(ewayBillFootnote), findsNothing,
        reason: 'no bill is made, so the line about making one is not shown');
  });

  testWidgets(
      'what staff found is worded as what they saw and when, never as a guarantee',
      (tester) async {
    final found = {
      ...withTruck(savedBill),
      'check': {'result': 'FOUND', 'checkedAtUtcMs': 1792000000000}
    };
    await mountCard(tester, EwayBillCard(shipment: shipment(bill: found)));
    expect(
        find.textContaining(RegExp(
            r'^NaviG8r saw this bill on the government portal on 14 Oct( 2026)?\. It may have changed since\.$')),
        findsOneWidget,
        reason:
            'a date and a caveat; copy.md Formats: the year only when it is not this year');
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
    expect(find.text('NaviG8r found a difference'), findsOneWidget,
        reason: 'copy.md step 4 problem: the heading');
    expect(
        find.textContaining(RegExp(
            r'^NaviG8r could not find this bill on the portal on 14 Oct( 2026)?\. Check the details here and on the portal\.$')),
        findsOneWidget,
        reason:
            'no stored note or difference (RECON gap 7), so the reason sentence stands in');
    expect(
        find.text(
            'If the portal is right, fix it here. If the bill itself is wrong, change it in your billing software or on the e-way bill portal first.'),
        findsOneWidget,
        reason: 'copy.md step 4 problem: which side to fix');
    await tester.tap(find.widgetWithText(FilledButton, 'Fix the details'));
    await tester.pump();
    expect(find.text('INV/1'), findsOneWidget,
        reason: 'Fix the details opens the form with what was entered');
  });

  testWidgets('the 15 second refresh never wipes what is half typed',
      (tester) async {
    final current = ValueNotifier(shipment());
    await mountRefreshingCard(tester, current,
        (value) => EwayBillCard(key: const ValueKey('card'), shipment: value));
    await tester.tap(find.text('Enter the bill details'));
    await tester.pump();
    await tester.enterText(entry('Invoice number'), 'HALF-TYPED');
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
    expect(find.text(partOneLead), findsOneWidget, reason: 'still readable');
    expect(find.text('Enter the bill details'), findsNothing,
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
    expect(find.text('Edit the bill'), findsNothing, reason: 'locked once delivered');
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
    expect(find.text(partOneLead), findsOneWidget,
        reason: 'back to part 1, nothing added');
  });

  testWidgets('the portal link opens the government address', (tester) async {
    final launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
    await mountCard(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Open the e-way bill portal'));
    await tester.pump();
    expect(launcher.opened, ['https://ewaybillgst.gov.in'],
        reason: 'one fixed address');
    launcher.opens = false;
    await tester.tap(find.text('Open the e-way bill portal'));
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
    await tester.tap(find.text('Edit the bill'));
    await tester.pump();
    await tester.enterText(entry('Invoice number'), 'TYPED-FOR-A');
    await mountCard(
        tester, EwayBillCard(shipment: {...shipment(), 'id': 'shipment-b'}));
    expect(find.text(partOneLead), findsOneWidget,
        reason: 'the new shipment\'s own state, form closed');
    await tester.tap(find.text('Enter the bill details'));
    await tester.pump();
    expect(find.text('TYPED-FOR-A'), findsNothing,
        reason: 'nothing typed for the old shipment carries over');

    signInAsCarrier(office: true);
    await mountCard(
        tester, EwayBillCarrierCard(shipment: shipment(bill: savedBill)));
    expect(find.text('1234 5678 9012'), findsOneWidget);
    await mountCard(
        tester,
        EwayBillCarrierCard(shipment: {
          ...shipment(bill: {'kind': 'BILL', 'billNumber': '999988887777'}),
          'id': 'shipment-b'
        }));
    expect(find.text('1234 5678 9012'), findsNothing,
        reason: 'the old shipment\'s bill is gone');
    expect(find.text('9999 8888 7777'), findsOneWidget,
        reason: 'the new shipment\'s bill shows');
  });
}
