import 'package:dio/dio.dart';

import 'eway_bill_words.dart';

// A trip starts only once every accepted booking has a final e-way bill (owner, 23 Oct 2026, after tester
// Uwais). The server decides, in ewayBillStartGate.ts; this mirrors it so Start trip is not offered when it
// would be refused. Change both together. It reads only what was typed in: nobody at NaviG8r checks bills.

/// Why one booking holds the trip, in the order the server checks.
enum EwayBillStartBlock { noBill, truckMissing, truckDiffers, expired, problem }

/// Null when the booking is not accepted or its bill is final. A trip with no truck differs from any truck.
EwayBillStartBlock? ewayBillStartBlock(
    Map<String, dynamic> booking, String? tripTruckNumber, DateTime now) {
  if (booking['status'] != 'BOOKED') return null;
  final bill = booking['ewayBill'];
  if (bill is! Map) return EwayBillStartBlock.noBill;
  if (bill['kind'] == 'NOT_NEEDED') return null;
  final onBill = bill['truckNumber'];
  if (onBill is! String || onBill.isEmpty) {
    return EwayBillStartBlock.truckMissing;
  }
  final onTrip = portalTruckNumber(tripTruckNumber ?? '');
  if (onTrip.isEmpty || portalTruckNumber(onBill) != onTrip) {
    return EwayBillStartBlock.truckDiffers;
  }
  final validUntil = bill['validUntilUtcMs'];
  if (validUntil is! num || validUntil <= now.millisecondsSinceEpoch) {
    return EwayBillStartBlock.expired;
  }
  final check = bill['check'];
  if (check is Map && check['result'] == 'PROBLEM') {
    return EwayBillStartBlock.problem;
  }
  return null;
}

/// One short line for a booking that holds the trip.
String ewayBillStartBlockLine(String shipperName, EwayBillStartBlock block) =>
    switch (block) {
      EwayBillStartBlock.noBill => '$shipperName: no e-way bill yet.',
      EwayBillStartBlock.truckMissing =>
        '$shipperName: truck not on the e-way bill.',
      EwayBillStartBlock.truckDiffers =>
        '$shipperName: truck on the bill differs from the trip.',
      EwayBillStartBlock.expired => '$shipperName: valid-until time on the e-way bill has passed.',
      EwayBillStartBlock.problem => '$shipperName: e-way bill has a problem.',
    };

String _shipperName(Object? name) =>
    name is String && name.isNotEmpty ? name : 'The shipper';

/// The lines for every accepted booking on [trip] that holds it, empty when the trip may start.
List<String> ewayBillStartBlockLines(
    Map<String, dynamic> trip, List<Map<String, dynamic>> bookings,
    {required DateTime now}) {
  final tripTruck = trip['assignedTruckNumber'];
  return [
    for (final booking in bookings)
      if (ewayBillStartBlock(
              booking, tripTruck is String ? tripTruck : null, now)
          case final block?)
        ewayBillStartBlockLine(_shipperName(booking['customerOrgName']), block),
  ];
}

const _blockByServerReason = {
  'no_bill': EwayBillStartBlock.noBill,
  'truck_missing': EwayBillStartBlock.truckMissing,
  'truck_differs': EwayBillStartBlock.truckDiffers,
  'expired': EwayBillStartBlock.expired,
  'problem': EwayBillStartBlock.problem,
};

/// The same lines from the server refusal `409 eway_bill_not_ready`, or null for any other error. A bill can
/// change between the screen loading and the tap, so the server may refuse what this screen allowed.
List<String>? ewayBillNotReadyLines(Object error) {
  if (error is! DioException) return null;
  final body = error.response?.data;
  if (error.response?.statusCode != 409 ||
      body is! Map ||
      body['error'] != 'eway_bill_not_ready') {
    return null;
  }
  final shipments = body['shipments'];
  final lines = [
    if (shipments is List)
      for (final shipment in shipments.whereType<Map>())
        if (_blockByServerReason[shipment['reason']] case final block?)
          ewayBillStartBlockLine(_shipperName(shipment['shipperName']), block),
  ];
  return lines.isEmpty ? null : lines;
}
