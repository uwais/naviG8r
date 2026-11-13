// The e-way bill steps on the shipper's shipment screen (sh-ewb-*, PR 5b of the redesign): the portal
// copy rows, the bill form and its errors, adding the truck, the saved summary, and a bill ops flagged.
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shipper_screen_checks.dart';
import 'support/shipper_shipment_app.dart';

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
      expect(find.text('You · Step 1 of 2'), findsOneWidget,
          reason: 'sh-ewb-portal: whose step, and which part');
      expect(
          find.text(
              'Make the bill on loading day, in your billing software or on the portal. Copy in these details:'),
          findsOneWidget);
      expect(find.text('Portal field: Vehicle No. (Part B)'), findsOneWidget,
          reason: 'testers could not tell where each value goes on the portal');
      expect(find.text('Portal field: Transporter ID. Not your GSTIN.'),
          findsOneWidget,
          reason: 'testers could not tell GSTIN from transporter ID');
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'the truck in the portal form');
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
              "Leave Transporter ID empty. Then only you, who made the bill, can change the truck."),
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
      await tester.tap(find.text('Enter the bill details'));
      await tester.pumpAndSettle();
      expect(find.text(ewayBillFootnote), findsOneWidget,
          reason: 'still once with the form open');
      await leave(tester);
    });

    testWidgets(
        'before acceptance the carrier step names the trip truck, even with no e-way bill needed',
        (tester) async {
      await showShipment(
          tester,
          booking(
              status: 'PENDING_CARRIER_ACCEPT',
              ewayBill: notNeededBill,
              extra: {'assignedTruckNumber': 'KA01AB1234'}),
          trip: lane());
      expect(find.text('Ravi Roadways · Truck KA01AB1234'), findsOneWidget,
          reason: 'the bill step shows no truck here, so the carrier step does');
      await leave(tester);
    });

    testWidgets(
        'an 11-digit bill number is stopped with its own sentence, before anything is sent',
        (tester) async {
      final announced = watchAnnouncements(tester);
      final server = await showShipment(
          tester, booking(extra: {'carrierTransporterId': '29ABCDE1234F1Z5'}),
          trip: lane());
      await tester.tap(find.text('Enter the bill details'));
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
      await tester.tap(find.text('Enter the bill details'));
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
      await tester.tap(find.text('Enter the bill details'));
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
              'The bill runs one day per 200 km from when the truck is added, to midnight India time.'),
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

    testWidgets('bill and truck saved: a short summary, changes behind one button',
        (tester) async {
      // A passed valid-until time keeps the changes open, so this bill is still valid.
      final validUntil = DateTime.now().toUtc().add(const Duration(days: 2));
      await showShipment(
          tester,
          booking(ewayBill: {
            ...billWithTruck,
            'validUntilUtcMs': validUntil.millisecondsSinceEpoch
          }),
          trip: lane());
      expect(
          find.text(
              'E-way bill saved. Nothing more for you to do until delivery.'),
          findsOneWidget,
          reason: 'copy.md step 4');
      expect(find.textContaining('NaviG8r checks'), findsNothing,
          reason: 'owner, 22 Oct 2026: no one checks a bill by hand before the trip');
      expect(find.text('Edit the bill'), findsNothing,
          reason: 'Uwais, 22 Oct 2026: a saved bill shows only its summary');
      expect(find.text(ewayBillFootnote), findsNothing);
      await tester.ensureVisible(find.text('Change or remove the e-way bill'));
      await tester.tap(find.text('Change or remove the e-way bill'));
      await tester.pumpAndSettle();
      expect(find.text('Edit the bill'), findsOneWidget);
      expect(find.text('Remove e-way bill'), findsOneWidget);
      expect(find.text(ewayBillFootnote), findsOneWidget);
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
      expect(find.text('NaviG8r found a difference'), findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Fix the details'), findsOneWidget,
          reason: 'sh-ewb-problem primary');
      expect(find.text('Ask NaviG8r staff'), findsNothing,
          reason: 'RECON gap 12: no channel known to reach staff');
      await leave(tester);
    });

    // billWithTruck's valid-until time, 19 Oct 2026, has passed.
    for (final (stage, status, trip) in [
      ('on the way', 'BOOKED', lane(status: 'IN_PROGRESS', started: leftAt)),
      ('awaiting release', 'PENDING_RELEASE', lane(status: 'COMPLETED', started: leftAt)),
      ('delivered', 'DELIVERED', lane(status: 'COMPLETED', started: leftAt)),
    ]) {
      testWidgets('a passed valid-until time $stage does not say the trip cannot start',
          (tester) async {
        await showShipment(
            tester,
            booking(status: status, ewayBill: billWithTruck, extra: {
              if (status != 'BOOKED') 'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
            }),
            trip: trip);
        expect(find.text('The valid-until time you entered has passed.'),
            findsOneWidget);
        expect(find.textContaining('so the trip cannot start'), findsNothing,
            reason: 'hunt, 23 Oct 2026: the trip has already started');
        await leave(tester);
      });
    }

    testWidgets('a passed valid-until time before the trip starts still says it cannot start',
        (tester) async {
      await showShipment(tester, booking(ewayBill: billWithTruck), trip: lane());
      expect(
          find.text(
              'The valid-until time you entered has passed, so the trip cannot start. Check the bill on the portal, then enter the new time here.'),
          findsOneWidget);
      await leave(tester);
    });
  });
}
