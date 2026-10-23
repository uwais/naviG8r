// The app's copy of the start rule (owner, 23 Oct 2026): the same reasons as the server (ewayBillStartGate.ts,
// and a booking waiting to be accepted from services.ts), in the same order, and its 409 read into the same holds.
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
    expect(
        reason({...booked(null, status: 'PENDING_CARRIER_ACCEPT'), 'readyToAccept': true}),
        EwayBillStartBlock.waitingForAccept,
        reason: 'a booking waiting for the carrier holds the trip');
    expect(
        reason({...booked(null, status: 'PENDING_CARRIER_ACCEPT'), 'readyToAccept': false}),
        isNull,
        reason: 'one that cannot be accepted yet does not, as on the server');
    expect(reason(booked(null, status: 'PENDING_CARRIER_ACCEPT')), isNull,
        reason: 'an older server sends no readyToAccept and does not hold the trip for it');
    expect(reason(booked(null, status: 'DELIVERED')), isNull);
  });

  test('bookings waiting to be accepted are listed first, as the server lists them', () {
    final trip = {'assignedTruckNumber': 'KA01AB1234'};
    expect(
        ewayBillStartHolds(
            trip,
            [
              {...booked(null), 'id': 'billless'},
              {
                ...booked(null, status: 'PENDING_CARRIER_ACCEPT'),
                'id': 'waiting',
                'customerOrgName': 'Shipper Two',
                'readyToAccept': true
              },
            ],
            now: now),
        [
          (shipmentId: 'waiting', shipperName: 'Shipper Two', block: EwayBillStartBlock.waitingForAccept),
          (shipmentId: 'billless', shipperName: 'Synthetic Shipper A', block: EwayBillStartBlock.noBill),
        ]);
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
    expect(line(EwayBillStartBlock.waitingForAccept, office),
        "Shipper One's booking is waiting for you to accept.");
    expect(line(EwayBillStartBlock.waitingForAccept, driver),
        "Shipper One's booking is waiting for your office to accept.",
        reason: 'a driver does not accept for the office');
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
      if (block == EwayBillStartBlock.truckDiffers ||
          block == EwayBillStartBlock.waitingForAccept) {
        continue;
      }
      expect(line(block, driver), line(block, office),
          reason: 'only the truck and accept lines differ by reader');
    }
    EwayBillStartHold hold(EwayBillStartBlock block) =>
        (shipmentId: 'a', shipperName: 'Shipper One', block: block);
    final waiting = [hold(EwayBillStartBlock.waitingForAccept)];
    final both = [...waiting, hold(EwayBillStartBlock.noBill)];
    expect(ewayBillStartBlockFooter(office, both),
        'You can message the shipper from the booking.');
    expect(ewayBillStartBlockFooter(office, waiting), isNull,
        reason: 'the office accepts it; there is no shipper to message');
    expect(ewayBillStartBlockFooter(driver, waiting), 'Call your office.');
    expect(ewayBillStartBlockFooter(driver, both), 'Call your office.');
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
            {'shipmentId': 'w', 'shipperName': 'Shipper Zero', 'reason': 'waiting_for_accept'},
            {'shipmentId': 'a', 'shipperName': 'Shipper One', 'reason': 'no_bill'},
            {'shipmentId': 'b', 'shipperName': 'Shipper Two', 'reason': 'truck_missing'},
            {'shipmentId': 'c', 'shipperName': 'Shipper Three', 'reason': 'truck_differs'},
            {'shipmentId': 'd', 'shipperName': 'Shipper Four', 'reason': 'expired'},
            {'shipmentId': 'e', 'shipperName': '', 'reason': 'problem'},
            {'shipmentId': 'f', 'shipperName': 'Shipper Six', 'reason': 'something_new'},
          ],
        })),
        [
          (shipmentId: 'w', shipperName: 'Shipper Zero', block: EwayBillStartBlock.waitingForAccept),
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
