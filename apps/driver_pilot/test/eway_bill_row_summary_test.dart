import 'package:driver_pilot/eway_bill_words.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> shipmentWith(Object? ewayBill) =>
    {'id': 'load-1', if (ewayBill != null) 'ewayBill': ewayBill};

void main() {
  test('no record reads as not added yet', () {
    expect(ewayBillRowSummary(shipmentWith(null)), 'E-way bill: not added yet');
  });

  test('the shipper saying none is needed reads as their statement', () {
    expect(
        ewayBillRowSummary(shipmentWith(
            {'kind': 'NOT_NEEDED', 'notNeededReason': 'BELOW_THRESHOLD'})),
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

  test('a problem ops found is added; a found check adds nothing', () {
    expect(
        ewayBillRowSummary(shipmentWith({
          'kind': 'BILL',
          'billNumber': '123456789012',
          'check': {'result': 'PROBLEM', 'problemReason': 'NOT_FOUND'},
        })),
        'E-way bill 1234 5678 9012, truck not added. Ops found a problem');
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
    expect(
        ewayBillRowSummary(shipmentWith('BILL')), 'E-way bill: not added yet');
    expect(ewayBillRowSummary(shipmentWith(42)), 'E-way bill: not added yet');
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
