// The app's copy of the start rule (owner, 23 Oct 2026): the same reasons as ewayBillStartGate.ts, in the same
// order, and the server's 409 read into the same holds.
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
    expect(reason(booked(bill()..remove('validUntilUtcMs'))),
        EwayBillStartBlock.truckMissing,
        reason: 'a truck with no valid-until time is not added yet, as on the server');
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

  test('holds name the shipper, and say the shipper when no name came', () {
    final trip = {'assignedTruckNumber': 'KA01AB1234'};
    expect(
        ewayBillStartHolds(
            trip,
            [
              booked(null),
              {...booked(bill(truck: null)), 'customerOrgName': ''},
              booked(bill()),
            ],
            now: now),
        [
          (shipmentId: '', shipperName: 'Synthetic Shipper A', block: EwayBillStartBlock.noBill),
          (shipmentId: '', shipperName: 'The shipper', block: EwayBillStartBlock.truckMissing),
        ]);
  });

  test('each line says who acts, for the office and for the driver', () {
    String line(EwayBillStartBlock block, StartGateReader reader) =>
        ewayBillStartBlockLine((shipmentId: 'a', shipperName: 'Shipper One', block: block),
            reader: reader);
    const office = StartGateReader.carrierOffice;
    const driver = StartGateReader.driver;
    expect(line(EwayBillStartBlock.noBill, office),
        'Shipper One has not added the e-way bill yet.');
    expect(line(EwayBillStartBlock.truckMissing, office),
        'Shipper One has not added the truck to the e-way bill yet.');
    expect(line(EwayBillStartBlock.truckDiffers, office),
        "Shipper One's e-way bill has a different truck from this trip. Change the trip's truck, or ask Shipper One to fix the bill.");
    expect(line(EwayBillStartBlock.truckDiffers, driver),
        "Shipper One's e-way bill has a different truck from this trip.",
        reason: 'a driver cannot change the trip truck');
    expect(line(EwayBillStartBlock.expired, office),
        "The valid-until time on Shipper One's e-way bill has passed.");
    expect(line(EwayBillStartBlock.problem, office),
        "NaviG8r found a problem with Shipper One's e-way bill.");
    for (final block in EwayBillStartBlock.values) {
      if (block == EwayBillStartBlock.truckDiffers) continue;
      expect(line(block, driver), line(block, office),
          reason: 'only the truck line differs by reader');
    }
    expect(ewayBillStartBlockFooter(office),
        'You can message the shipper from the booking.');
    expect(ewayBillStartBlockFooter(driver), 'Call your office.');
  });

  DioException refusal(int status, Object body) => DioException(
      requestOptions: RequestOptions(path: '/start'),
      response: Response(
          requestOptions: RequestOptions(path: '/start'),
          statusCode: status,
          data: body));

  test('the server refusal reads into the same holds; anything else is not this', () {
    expect(
        ewayBillNotReadyHolds(refusal(409, {
          'error': 'eway_bill_not_ready',
          'shipments': [
            {'shipmentId': 'a', 'shipperName': 'Shipper One', 'reason': 'no_bill'},
            {'shipmentId': 'b', 'shipperName': 'Shipper Two', 'reason': 'truck_missing'},
            {'shipmentId': 'c', 'shipperName': 'Shipper Three', 'reason': 'truck_differs'},
            {'shipmentId': 'd', 'shipperName': 'Shipper Four', 'reason': 'expired'},
            {'shipmentId': 'e', 'shipperName': '', 'reason': 'problem'},
            {'shipmentId': 'f', 'shipperName': 'Shipper Six', 'reason': 'something_new'},
          ],
        })),
        [
          (shipmentId: 'a', shipperName: 'Shipper One', block: EwayBillStartBlock.noBill),
          (shipmentId: 'b', shipperName: 'Shipper Two', block: EwayBillStartBlock.truckMissing),
          (shipmentId: 'c', shipperName: 'Shipper Three', block: EwayBillStartBlock.truckDiffers),
          (shipmentId: 'd', shipperName: 'Shipper Four', block: EwayBillStartBlock.expired),
          (shipmentId: 'e', shipperName: 'The shipper', block: EwayBillStartBlock.problem),
        ]);
    expect(ewayBillNotReadyHolds(refusal(409, {'error': 'trip_not_startable'})),
        isNull);
    expect(
        ewayBillNotReadyHolds(
            refusal(409, {'error': 'eway_bill_not_ready', 'shipments': []})),
        isNull,
        reason: 'no line to show, so the usual sentence is shown instead');
    expect(ewayBillNotReadyHolds(refusal(400, {'error': 'eway_bill_not_ready'})),
        isNull);
    expect(ewayBillNotReadyHolds(StateError('not a server answer')), isNull);
  });
}
