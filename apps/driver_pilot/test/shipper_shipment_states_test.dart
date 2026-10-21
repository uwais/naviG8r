// The shipper's shipment screen in each state (sh-ship-*, PRs 5a and 10 of the redesign): what its steps
// say from booking to delivery or cancel, where focus lands, and failures in plain words.
import 'package:driver_pilot/shipper/shipment_screen.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';
import 'support/shipper_shipment_app.dart';

void main() {
  stepPanelTests();
  paymentHoldTests();
  focusTests();
  plainErrorTests();

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
              'Waiting for Ravi Roadways to accept. Your payment is on hold. It is collected after delivery.'),
          findsOneWidget,
          reason: 'brief A.3: the shipper is told the money is held');
      expect(find.text('Waiting for carrier'), findsOneWidget,
          reason: 'copy.md status word');
      expect(
          find.text(
              'You cannot cancel a booked shipment in the app. To change it, contact ${PendingCopy.changeOrCancelContact}.'),
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
      expect(find.textContaining('· $laneLeaves ·'), findsOneWidget,
          reason: 'the summary says when the truck leaves, never an arrival');
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
              'Nothing for you to do now. Ravi Roadways starts the trip. The truck ${laneLeaves.replaceFirst('Leaves', 'leaves')}.'),
          findsOneWidget,
          reason: 'sh-ship-noewb: who acts next, and the days the truck can leave');
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
      expect(
          find.text(
              'If you paid the ₹2,640 for this booking, all of it is refunded.'),
          findsOneWidget,
          reason:
              'a never-paid booking is also marked refunded on cancel, so the refund is told without claiming a payment');
      expect(find.text('You paid'), findsNothing,
          reason: 'the payment record cannot say whether it was ever paid');
      expect(
          find.text(
              'Refunds reach your account in the time your bank or payment app takes.'),
          findsOneWidget);
      expect(
          find.text(
              'Questions about this refund? Contact ${PendingCopy.changeOrCancelContact}.'),
          findsOneWidget,
          reason: 'copy.md cancelled: the contact placeholder');
      expect(find.widgetWithText(FilledButton, 'Book a trip'), findsOneWidget,
          reason: 'screens.md: the primary action on a cancelled shipment');
      expect(find.text('Steps for this shipment'), findsNothing);
      await leave(tester);
    });

    testWidgets('cancelled with the payment still held: says what was paid',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane());
      expect(find.text('You paid'), findsOneWidget,
          reason: 'an authorized payment is money the shipper paid');
      expect(find.text('₹2,640'), findsOneWidget);
      expect(
          find.text(
              'Refunds reach your account in the time your bank or payment app takes.'),
          findsOneWidget);
      await leave(tester);
    });

    testWidgets('cancelled before any payment: says nothing was paid',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(), payment: {'status': 'CREATED', 'amountPaise': 264000});
      expect(find.text('Nothing was paid for this booking.'), findsOneWidget,
          reason: 'checkout never finished, so no money was taken');
      expect(find.text('You paid'), findsNothing,
          reason: 'no payment was taken, so none is claimed');
      expect(find.textContaining('refunded'), findsNothing,
          reason: 'nothing to refund');
      expect(
          find.text(
              'Questions about this booking? Contact ${PendingCopy.changeOrCancelContact}.'),
          findsOneWidget,
          reason: 'the contact stays, about the booking, not a refund');
      await leave(tester);
    });

    for (final (paymentStatus, opening) in [
      ('CREATED', ''),
      ('FAILED', 'Payment did not go through. '),
    ]) {
      testWidgets(
          'payment $paymentStatus: booked, not paid, and nothing said to be held',
          (tester) async {
        await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
            trip: lane(),
            payment: {'status': paymentStatus, 'amountPaise': 264000});
        expect(find.text('Booked, not paid'), findsOneWidget,
            reason: 'checkout did not finish, so the first step is not "paid"');
        expect(find.text('Booked and paid'), findsNothing,
            reason: 'never claim a payment that was not taken');
        expect(find.text('Not paid'), findsOneWidget,
            reason: 'the status word says what is wrong');
        expect(
            find.text(
                '${opening}This booking is not paid, so Ravi Roadways cannot accept it yet. '
                'To pay or cancel it, contact ${PendingCopy.changeOrCancelContact}.'),
            findsOneWidget,
            reason:
                'what it means and who to contact; there is no way to pay again in the app');
        expect(find.textContaining('held until delivery'), findsNothing,
            reason: 'no money is held');
        expect(find.textContaining('Your payment is on hold'), findsNothing,
            reason: 'no money is held');
        expect(find.text('Ravi Roadways can accept once this booking is paid.'),
            findsOneWidget,
            reason: 'the carrier step says why it waits');
        await leave(tester);
      });
    }
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

void focusTests() {
  group('Focus moves (PR 10)', () {
    testWidgets("after Pay and book, focus starts on the new shipment's title",
        (tester) async {
      lastBookedShipmentId = 'shp_9f2c41';
      addTearDown(() => lastBookedShipmentId = null);
      await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      expect(
          Focus.of(tester.element(find.text('Bengaluru to Chennai')))
              .hasPrimaryFocus,
          isTrue,
          reason:
              "accessibility.md: after Pay and book, focus moves to the shipment's H1");
      expect(lastBookedShipmentId, isNull,
          reason: 'only the first opening after booking moves focus');
      await leave(tester);
    });

    testWidgets('a failed bill save moves focus to the error summary',
        (tester) async {
      await showShipment(tester, needsBill, trip: lane());
      await tester.tap(find.text('I have made it. Enter the details'));
      await tester.pumpAndSettle();
      await tester.enterText(entry('E-way bill number'), '34120098765');
      await tester.tap(find.text('Save e-way bill'));
      await tester.pumpAndSettle();
      expect(
          Focus.of(tester.element(
                  find.text('1 detail needs fixing before you can save.')))
              .hasPrimaryFocus,
          isTrue,
          reason:
              'accessibility.md: on a failed save, focus moves to the error summary');
      await leave(tester);
    });
  });
}

void plainErrorTests() {
  group('No HTTP text (PR 10)', () {
    testWidgets('a refused Accept delivery says so in words', (tester) async {
      final server = await showShipment(
          tester,
          booking(status: 'PENDING_RELEASE', ewayBill: billWithTruck, extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          }),
          trip: lane(status: 'COMPLETED', started: leftAt));
      server.answers['/shipments/shp_9f2c41/accept-pod'] =
          jsonResponse({'error': 'boom'}, 500);
      await tester.tap(find.text('Accept delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Accept delivery')));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Could not accept delivery. Check your connection, then try again.'),
          findsOneWidget,
          reason: 'a failure is a plain sentence');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no "HTTP 500" in the app');
      await leave(tester);
    });

    testWidgets('messages that fail to load say so in words', (tester) async {
      final server = await showShipment(
          tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane());
      server.answers['/v1/shipments/shp_9f2c41/conversation/timeline'] =
          jsonResponse({'error': 'boom'}, 500);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Could not load messages. Check your connection, then try again.'),
          findsOneWidget,
          reason: 'a failure is a plain sentence');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no raw codes');
      await leave(tester);
    });
  });
}
