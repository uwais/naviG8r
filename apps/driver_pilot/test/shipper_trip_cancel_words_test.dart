// The shipper's words around a carrier's trip cancel: a booking still waiting on a trip its carrier asked
// NaviG8r to cancel, money Razorpay collected after the cancel, and how old the e-way bill is.
import 'package:driver_pilot/eway_bill_dates.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shipper_shipment_app.dart';

const _collectedAfterCancel =
    'Your payment came through after this shipment was cancelled. NaviG8r is refunding it; your bank may take 5-7 working days after the refund.';
const _cancelTheBill =
    'If you made an e-way bill for this load, cancel it on the e-way bill portal. The portal allows this only within 24 hours of making the bill.';
const _billTooOld =
    'If you made an e-way bill for this load, it is over 24 hours old, so the portal no longer lets you cancel it.';

/// India's clock at [moment] for the screen's e-way bill dates.
void indiaClockAt(DateTime moment) {
  ewayBillNow = () => moment;
  addTearDown(() => ewayBillNow = DateTime.now);
}

void main() {
  group('Waiting on a trip its carrier asked NaviG8r to cancel', () {
    testWidgets('says the carrier asked, that NaviG8r reviews it, and that the payment is on hold',
        (tester) async {
      await showShipment(tester, booking(status: 'PENDING_CARRIER_ACCEPT'),
          trip: lane(status: 'CANCEL_REQUESTED'));
      expect(
          find.text(
              'Ravi Roadways asked NaviG8r to cancel this trip. NaviG8r reviews it, and you are told if your shipment is cancelled. Your payment is on hold.'),
          findsOneWidget);
      expect(find.textContaining('Waiting for Ravi Roadways to accept'),
          findsNothing,
          reason: 'the carrier cannot accept it now');
      await leave(tester);
    });
  });

  group('Money collected after the cancel', () {
    testWidgets('says the payment came through and NaviG8r is refunding it',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(),
          payment: {'status': 'CAPTURED_AFTER_CANCEL', 'amountPaise': 264000});
      expect(find.text(_collectedAfterCancel), findsOneWidget);
      expect(
          find.text(
              'Refunds reach your account in the time your bank or payment app takes.'),
          findsNothing,
          reason: 'the generic refund line is replaced');
      expect(find.textContaining('CAPTURED_AFTER_CANCEL'), findsNothing,
          reason: 'never the code');
      await leave(tester);
    });

    testWidgets('once Finance marks it refunded, reads as any refund',
        (tester) async {
      await showShipment(tester, booking(status: 'FAILED_CARRIER_REFUNDED'),
          trip: lane(),
          payment: {'status': 'REFUNDED', 'amountPaise': 264000});
      expect(find.text(_collectedAfterCancel), findsNothing);
      expect(
          find.text(
              'If you paid the ₹2,640 for this booking, all of it is refunded.'),
          findsOneWidget);
      await leave(tester);
    });
  });

  group('The e-way bill line on a cancelled shipment', () {
    // billNoTruck is dated 18 Oct 2026; the bill's time of day is not known, so a bill dated yesterday in India
    // may still be inside its 24 hours.
    for (final (day, moment, words) in [
      ('the day it is dated', DateTime.utc(2026, 10, 18, 6, 30), _cancelTheBill),
      ('the next day in India', DateTime.utc(2026, 10, 19, 17, 0), _cancelTheBill),
      ('two days later in India', DateTime.utc(2026, 10, 19, 18, 31), _billTooOld),
    ]) {
      testWidgets('on $day', (tester) async {
        indiaClockAt(moment);
        await showShipment(tester,
            booking(status: 'FAILED_CARRIER_REFUNDED', ewayBill: billNoTruck),
            trip: lane(),
            payment: {'status': 'REFUNDED', 'amountPaise': 264000});
        expect(find.text(words), findsOneWidget);
        expect(find.text(words == _cancelTheBill ? _billTooOld : _cancelTheBill),
            findsNothing);
        await leave(tester);
      });
    }
  });
}
