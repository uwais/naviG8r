// The shipper's cancelled shipment when the payment was only held (owner decision, 19 Oct 2026): NaviG8r never
// collected it, so nothing is said to be refunded, and Razorpay returns it by itself. The shipper's bank may already
// show the debit (UPI, netbanking), so the words never say nothing was taken.
import 'package:driver_pilot/eway_bill_dates.dart';
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shipper_shipment_app.dart';

const _held =
    'NaviG8r never collected this payment. Razorpay returns it within 3 days of when you paid; your bank may take 5-7 working days after that.';
const _cancelTheBill =
    'If you made an e-way bill for this load, cancel it on the e-way bill portal. The portal allows this only within 24 hours of making the bill.';

/// Noon in India on 18 Oct 2026, the day billNoTruck is dated, so the bill can still be cancelled.
void _onTheBillsDay() {
  ewayBillNow = () => DateTime.utc(2026, 10, 18, 6, 30);
  addTearDown(() => ewayBillNow = DateTime.now);
}

void main() {
  group('Cancelled with the hold released', () {
    testWidgets(
        'says NaviG8r never collected the money, and claims no payment or refund',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(),
          payment: {'status': 'HOLD_RELEASED', 'amountPaise': 264000});
      expect(find.text('This shipment was cancelled'), findsOneWidget);
      expect(find.text(_held), findsOneWidget);
      expect(find.text('You paid'), findsNothing,
          reason: 'NaviG8r collected nothing');
      expect(find.textContaining('never taken'), findsNothing,
          reason: 'the bank may already show the debit');
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
        'a booking with an e-way bill is told to cancel it on the portal, within its 24 hours',
        (tester) async {
      _onTheBillsDay();
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
      _onTheBillsDay();
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
