import 'package:driver_pilot/eway_bill_words.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> shipmentWith(Object? ewayBill,
        {String status = 'BOOKED'}) =>
    {
      'id': 'load-1',
      'status': status,
      if (ewayBill != null) 'ewayBill': ewayBill
    };

void main() {
  test('no record reads as a fact, not a to-do, while one can still be added',
      () {
    expect(ewayBillRowSummary(shipmentWith(null)), 'E-way bill: none added');
    expect(
        ewayBillRowSummary(
            shipmentWith(null, status: 'PENDING_CARRIER_ACCEPT')),
        'E-way bill: none added');
  });

  test('no record says nothing once the shipment is past booking', () {
    for (final status in [
      'IN_TRANSIT',
      'PENDING_RELEASE',
      'DELIVERED',
      'FAILED_CARRIER_REFUNDED'
    ]) {
      expect(ewayBillRowSummary(shipmentWith(null, status: status)), '',
          reason: status);
    }
    expect(ewayBillRowSummary({'id': 'load-1'}), '', reason: 'no status');
  });

  test('the shipper saying none is needed reads as their statement', () {
    expect(
        ewayBillRowSummary(shipmentWith(
            {'kind': 'NOT_NEEDED', 'notNeededReason': 'BELOW_THRESHOLD'},
            status: 'DELIVERED')),
        'No e-way bill needed (the shipper says so)');
  });

  test('a bill without a truck says the truck is not added', () {
    expect(
        ewayBillRowSummary(
            shipmentWith({'kind': 'BILL', 'billNumber': '123456789012'})),
        'E-way bill 1234 5678 9012, truck not added');
  });

  test('a bill with a truck names the truck', () {
    expect(
        ewayBillRowSummary(shipmentWith({
          'kind': 'BILL',
          'billNumber': '234567890123',
          'truckNumber': 'KA01AB1234',
          'validUntilUtcMs': 1800000000000,
        })),
        'E-way bill 2345 6789 0123, truck KA01AB1234');
  });

  test(
      'a problem ops found is a flag to open, never a claim the bill is wrong; a found check adds nothing',
      () {
    final flagged = ewayBillRowSummary(shipmentWith({
      'kind': 'BILL',
      'billNumber': '123456789012',
      'check': {'result': 'PROBLEM', 'problemReason': 'NOT_FOUND'},
    }));
    expect(flagged,
        'E-way bill 1234 5678 9012, truck not added. Ops flagged this bill. Open it to see why.');
    for (final word in ['wrong', 'invalid', 'fake', 'problem']) {
      expect(flagged.toLowerCase(), isNot(contains(word)));
    }
    final found = ewayBillRowSummary(shipmentWith({
      'kind': 'BILL',
      'billNumber': '123456789012',
      'truckNumber': 'KA01AB1234',
      'check': {'result': 'FOUND'},
    }));
    expect(found, 'E-way bill 1234 5678 9012, truck KA01AB1234');
    for (final word in ['verified', 'valid', 'found', 'ok']) {
      expect(found.toLowerCase(), isNot(contains(word)));
    }
  });

  test('malformed values never throw and never claim more than they know', () {
    expect(ewayBillRowSummary(shipmentWith('BILL')), 'E-way bill: none added');
    expect(ewayBillRowSummary(shipmentWith(42)), 'E-way bill: none added');
    expect(
        ewayBillRowSummary({'id': 'load-1', 'status': 7, 'ewayBill': 42}), '');
    expect(ewayBillRowSummary(shipmentWith({})),
        'E-way bill: open the shipment to see it');
    expect(ewayBillRowSummary(shipmentWith({'kind': 7})),
        'E-way bill: open the shipment to see it');
    expect(ewayBillRowSummary(shipmentWith({'kind': 'BILL'})),
        'E-way bill, truck not added');
    expect(
        ewayBillRowSummary(shipmentWith({
          'kind': 'BILL',
          'billNumber': 123456789012,
          'truckNumber': 99,
          'check': 'PROBLEM',
        })),
        'E-way bill, truck not added');
    expect(
        ewayBillRowSummary(shipmentWith({
          'kind': 'BILL',
          'billNumber': '',
          'truckNumber': '',
          'check': {'result': 3},
        })),
        'E-way bill, truck not added');
  });
}
