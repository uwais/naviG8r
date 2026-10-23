// The app's copy of the start rule (owner, 23 Oct 2026): the same reasons as ewayBillStartGate.ts, in the same
// order, and the server's 409 read into the same lines.
import 'package:dio/dio.dart';
import 'package:driver_pilot/eway_bill_start_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 6);
  final later = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
  Map<String, dynamic> booked(Map<String, dynamic>? bill,
          {String status = 'BOOKED'}) =>
      {
        'status': status,
        'customerOrgName': 'Synthetic Shipper A',
        if (bill != null) 'ewayBill': bill,
      };
  Map<String, dynamic> bill({String? truck = 'KA01AB1234', int? validUntil}) => {
        'kind': 'BILL',
        'billNumber': '123456789012',
        if (truck != null) 'truckNumber': truck,
        'validUntilUtcMs': validUntil ?? later,
      };

  test('each reason, in the order the server checks', () {
    EwayBillStartBlock? reason(Map<String, dynamic> booking,
            [String? tripTruck = 'KA01AB1234']) =>
        ewayBillStartBlock(booking, tripTruck, now);
    expect(reason(booked(null)), EwayBillStartBlock.noBill);
    expect(reason(booked(bill(truck: null))), EwayBillStartBlock.truckMissing);
    expect(reason(booked(bill(truck: 'KA02XY9999'))),
        EwayBillStartBlock.truckDiffers);
    expect(reason(booked(bill()), null), EwayBillStartBlock.truckDiffers,
        reason: 'a trip with no truck matches no bill');
    expect(
        reason(booked(bill(validUntil: now.millisecondsSinceEpoch))),
        EwayBillStartBlock.expired);
    expect(
        reason(booked({
          ...bill(),
          'check': {'result': 'PROBLEM', 'problemReason': 'CANCELLED'}
        })),
        EwayBillStartBlock.problem);
    expect(reason(booked(bill())), isNull);
    expect(reason(booked(bill(truck: 'ka 01 ab 1234'))), isNull,
        reason: 'compared in the portal form');
    expect(
        reason(booked({'kind': 'NOT_NEEDED', 'notNeededReason': 'OTHER'}), null),
        isNull);
    expect(reason(booked(null, status: 'PENDING_CARRIER_ACCEPT')), isNull,
        reason: 'only accepted bookings hold a trip');
  });

  test('lines name the shipper, and say the shipper when no name came', () {
    final trip = {'assignedTruckNumber': 'KA01AB1234'};
    expect(
        ewayBillStartBlockLines(
            trip,
            [
              booked(null),
              {...booked(bill(truck: null)), 'customerOrgName': ''},
              booked(bill()),
            ],
            now: now),
        [
          'Synthetic Shipper A: no e-way bill yet.',
          'The shipper: truck not on the e-way bill.',
        ]);
  });

  DioException refusal(int status, Object body) => DioException(
      requestOptions: RequestOptions(path: '/start'),
      response: Response(
          requestOptions: RequestOptions(path: '/start'),
          statusCode: status,
          data: body));

  test('the server refusal reads into the same lines; anything else is not this', () {
    expect(
        ewayBillNotReadyLines(refusal(409, {
          'error': 'eway_bill_not_ready',
          'shipments': [
            {'shipmentId': 'a', 'shipperName': 'Shipper One', 'reason': 'no_bill'},
            {'shipmentId': 'b', 'shipperName': 'Shipper Two', 'reason': 'truck_missing'},
            {'shipmentId': 'c', 'shipperName': 'Shipper Three', 'reason': 'truck_differs'},
            {'shipmentId': 'd', 'shipperName': 'Shipper Four', 'reason': 'expired'},
            {'shipmentId': 'e', 'shipperName': 'Shipper Five', 'reason': 'problem'},
            {'shipmentId': 'f', 'shipperName': 'Shipper Six', 'reason': 'something_new'},
          ],
        })),
        [
          'Shipper One: no e-way bill yet.',
          'Shipper Two: truck not on the e-way bill.',
          'Shipper Three: truck on the bill differs from the trip.',
          'Shipper Four: valid-until time on the e-way bill has passed.',
          'Shipper Five: e-way bill has a problem.',
        ]);
    expect(ewayBillNotReadyLines(refusal(409, {'error': 'trip_not_startable'})),
        isNull);
    expect(
        ewayBillNotReadyLines(
            refusal(409, {'error': 'eway_bill_not_ready', 'shipments': []})),
        isNull,
        reason: 'no line to show, so the usual sentence is shown instead');
    expect(ewayBillNotReadyLines(refusal(400, {'error': 'eway_bill_not_ready'})),
        isNull);
    expect(ewayBillNotReadyLines(StateError('not a server answer')), isNull);
  });
}
