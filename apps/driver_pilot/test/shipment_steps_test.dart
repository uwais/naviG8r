// The shipper's Home "Needs you" task, from the step mapping in spec/screens.md. Only the rows
// the shipments list can decide; PR 5a adds the rest.
import 'package:driver_pilot/shipment_steps.dart';
import 'package:flutter_test/flutter_test.dart';

String? taskFor(Map<String, dynamic> shipment,
        {bool canWriteBill = true, bool canAddTruck = true}) =>
    shipperTaskFor(shipment,
        canWriteBill: canWriteBill, canAddTruck: canAddTruck);

const bill = {'kind': 'BILL', 'billNumber': '341200987654'};

void main() {
  test('accepted with no bill: the shipper makes the e-way bill', () {
    expect(taskFor({'status': 'BOOKED'}), 'Make the e-way bill',
        reason: 'screens.md row "Accepted, needed, no bill", the nearest row');
  });

  test('a bill without the truck: add the truck', () {
    expect(taskFor({'status': 'BOOKED', 'ewayBill': bill}),
        'Add the truck to the e-way bill',
        reason: 'screens.md row "Accepted, bill, no truck"');
  });

  test('a flagged bill: fix it, even when the truck is also missing', () {
    expect(
        taskFor({
          'status': 'BOOKED',
          'ewayBill': {
            ...bill,
            'check': {'result': 'PROBLEM'}
          }
        }),
        'Fix the e-way bill',
        reason: 'screens.md row "Accepted, ops problem"');
  });

  test('nothing for the shipper while someone else acts', () {
    expect(taskFor({'status': 'PENDING_CARRIER_ACCEPT'}), isNull,
        reason:
            'the step-0 answer has no stored field, so it is not a Home task');
    expect(
        taskFor({
          'status': 'BOOKED',
          'ewayBill': {...bill, 'truckNumber': 'KA01AB1234'}
        }),
        isNull,
        reason: 'bill and truck saved: NaviG8r staff check it');
    expect(
        taskFor({
          'status': 'BOOKED',
          'ewayBill': {'kind': 'NOT_NEEDED'}
        }),
        isNull,
        reason: 'not needed: the carrier starts the trip');
    for (final status in [
      'PENDING_RELEASE',
      'DELIVERED',
      'FAILED_CARRIER_REFUNDED'
    ]) {
      expect(taskFor({'status': status}), isNull,
          reason: '$status needs nothing from the shipper');
    }
  });

  test('a task the login may not do is not offered', () {
    expect(taskFor({'status': 'BOOKED'}, canWriteBill: false), isNull,
        reason: 'no eway_bill.write, no bill to make');
    expect(taskFor({'status': 'BOOKED', 'ewayBill': bill}, canAddTruck: false),
        isNull,
        reason: 'no eway_bill.add_truck, the carrier adds it');
  });
}
