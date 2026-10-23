import 'package:dio/dio.dart';

import 'eway_bill_words.dart';

// A trip starts only once every accepted booking has a final e-way bill (owner, 23 Oct 2026, after tester
// Uwais). The server decides, in ewayBillStartGate.ts; this mirrors it so Start trip is not offered when it
// would be refused. Change both together. NaviG8r does not check every bill by hand: this reads what was typed
// in, and a problem NaviG8r found on the portal also holds the trip.

/// Why one booking holds the trip, in the order the server checks.
enum EwayBillStartBlock { noBill, truckMissing, truckDiffers, expired, problem }

/// Who reads the lines: the office can change the trip's truck, a driver can only call the office.
enum StartGateReader { carrierOffice, driver }

/// One booking that holds the trip, with its shipper's name.
typedef EwayBillStartHold = ({String shipperName, EwayBillStartBlock block});

/// Null when the booking is not accepted or its bill is final. A trip with no truck differs from any truck.
/// The truck and its valid-until time are saved together, so a bill with no valid-until time has no truck yet.
/// [now] is the phone's clock, which can be minutes off the server's; the server decides at Start.
EwayBillStartBlock? ewayBillStartBlock(
    Map<String, dynamic> booking, String? tripTruckNumber, DateTime now) {
  if (booking['status'] != 'BOOKED') return null;
  final bill = booking['ewayBill'];
  if (bill is! Map) return EwayBillStartBlock.noBill;
  if (bill['kind'] == 'NOT_NEEDED') return null;
  final onBill = bill['truckNumber'];
  final validUntil = bill['validUntilUtcMs'];
  if (onBill is! String || onBill.isEmpty || validUntil is! num) {
    return EwayBillStartBlock.truckMissing;
  }
  final onTrip = portalTruckNumber(tripTruckNumber ?? '');
  if (onTrip.isEmpty || portalTruckNumber(onBill) != onTrip) {
    return EwayBillStartBlock.truckDiffers;
  }
  if (validUntil <= now.millisecondsSinceEpoch) {
    return EwayBillStartBlock.expired;
  }
  final check = bill['check'];
  if (check is Map && check['result'] == 'PROBLEM') {
    return EwayBillStartBlock.problem;
  }
  return null;
}

/// One short line for a booking that holds the trip, saying who acts. A driver cannot change the trip's
/// truck, so the driver's truck line stops at the difference; [ewayBillStartBlockFooter] says what to do.
String ewayBillStartBlockLine(EwayBillStartHold hold,
    {required StartGateReader reader}) {
  final shipper = hold.shipperName;
  return switch (hold.block) {
    EwayBillStartBlock.noBill => '$shipper has not added the e-way bill yet.',
    EwayBillStartBlock.truckMissing =>
      '$shipper has not added the truck to the e-way bill yet.',
    EwayBillStartBlock.truckDiffers => switch (reader) {
        StartGateReader.carrierOffice =>
          "$shipper's e-way bill has a different truck from this trip. Change the trip's truck, or ask $shipper to fix the bill.",
        StartGateReader.driver =>
          "$shipper's e-way bill has a different truck from this trip.",
      },
    EwayBillStartBlock.expired =>
      '$shipper: the valid-until time entered here has passed.',
    EwayBillStartBlock.problem =>
      "NaviG8r found a problem with $shipper's e-way bill.",
  };
}

/// The one line under the list.
String ewayBillStartBlockFooter(StartGateReader reader) => switch (reader) {
      StartGateReader.carrierOffice =>
        'You can message the shipper from the booking.',
      StartGateReader.driver => 'Call your office.',
    };

String _shipperName(Object? name) =>
    name is String && name.isNotEmpty ? name : 'The shipper';

/// Every accepted booking on [trip] that holds it, empty when the trip may start.
List<EwayBillStartHold> ewayBillStartHolds(
    Map<String, dynamic> trip, List<Map<String, dynamic>> bookings,
    {required DateTime now}) {
  final tripTruck = trip['assignedTruckNumber'];
  return [
    for (final booking in bookings)
      if (ewayBillStartBlock(
              booking, tripTruck is String ? tripTruck : null, now)
          case final block?)
        (shipperName: _shipperName(booking['customerOrgName']), block: block),
  ];
}

const _blockByServerReason = {
  'no_bill': EwayBillStartBlock.noBill,
  'truck_missing': EwayBillStartBlock.truckMissing,
  'truck_differs': EwayBillStartBlock.truckDiffers,
  'expired': EwayBillStartBlock.expired,
  'problem': EwayBillStartBlock.problem,
};

/// The same holds from the server refusal `409 eway_bill_not_ready`, or null for any other error. A bill can
/// change between the screen loading and the tap, so the server may refuse what this screen allowed.
List<EwayBillStartHold>? ewayBillNotReadyHolds(Object error) {
  if (error is! DioException) return null;
  final body = error.response?.data;
  if (error.response?.statusCode != 409 ||
      body is! Map ||
      body['error'] != 'eway_bill_not_ready') {
    return null;
  }
  final shipments = body['shipments'];
  final holds = [
    if (shipments is List)
      for (final shipment in shipments.whereType<Map>())
        if (_blockByServerReason[shipment['reason']] case final block?)
          (shipperName: _shipperName(shipment['shipperName']), block: block),
  ];
  return holds.isEmpty ? null : holds;
}
