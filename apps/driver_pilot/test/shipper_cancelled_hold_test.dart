// The shipper's cancelled shipment when the payment was only held (owner decision, 19 Oct 2026): nothing was
// taken, so nothing is said to be refunded, and Razorpay releases the hold by itself.
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shipper_shipment_app.dart';

const _held =
    'Your payment was only held, never taken. Razorpay releases it within 3 days of when you paid; your bank may take 5-7 working days after that.';
const _cancelTheBill =
    'If you made an e-way bill for this load, cancel it on the e-way bill portal.';

void main() {
  group('Cancelled with the hold released', () {
    testWidgets('says the money was only held, and claims no payment or refund',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(),
          payment: {'status': 'HOLD_RELEASED', 'amountPaise': 264000});
      expect(find.text('This shipment was cancelled'), findsOneWidget);
      expect(find.text(_held), findsOneWidget);
      expect(find.text('You paid'), findsNothing, reason: 'nothing was taken');
      expect(find.textContaining('refunded'), findsNothing);
      expect(
          find.text(
              'Refunds reach your account in the time your bank or payment app takes.'),
          findsNothing);
      expect(
          find.text(
              'Questions about this payment? Contact ${PendingCopy.changeOrCancelContact}.'),
          findsOneWidget);
      expect(find.textContaining('HOLD_RELEASED'), findsNothing,
          reason: 'never the code');
      expect(find.text(_cancelTheBill), findsNothing,
          reason: 'no bill was made for this booking');
      await leave(tester);
    });

    testWidgets(
        'a booking with an e-way bill is told to cancel it on the portal, with no deadline',
        (tester) async {
      await showShipment(tester,
          booking(status: 'FAILED_CARRIER_REFUNDED', ewayBill: billNoTruck),
          trip: lane(),
          payment: {'status': 'HOLD_RELEASED', 'amountPaise': 264000});
      expect(find.text(_cancelTheBill), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
        'a shipper who said no bill is needed is not told to cancel one',
        (tester) async {
      await showShipment(
          tester,
          booking(status: 'FAILED_CARRIER_REFUNDED', ewayBill: const {
            'kind': 'NOT_NEEDED',
            'notNeededReason': 'GOODS_EXEMPT'
          }),
          trip: lane(),
          payment: {'status': 'REFUNDED', 'amountPaise': 264000});
      expect(find.text(_cancelTheBill), findsNothing);
      expect(find.text(_held), findsNothing, reason: 'a refund is not a hold');
      await leave(tester);
    });

    testWidgets('fits at 360 dp and 200% text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showShipment(tester,
          booking(status: 'FAILED_CARRIER_REFUNDED', ewayBill: billNoTruck),
          trip: lane(),
          payment: {'status': 'HOLD_RELEASED', 'amountPaise': 264000},
          height: 800);
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(find.text(_cancelTheBill),
          find.byType(Scrollable).first, const Offset(0, -200));
      expect(tester.takeException(), isNull);
      await leave(tester);
    });
  });
}
