import 'package:dio/dio.dart';

import 'eway_bill_words.dart';

// A trip starts only once every accepted booking has a final e-way bill (owner, 23 Oct 2026, after tester
// Uwais). The server decides, in ewayBillStartGate.ts; this mirrors it so Start trip is not offered when it
// would be refused. Change both together. NaviG8r does not check every bill by hand: this reads what was typed
// in, and a problem NaviG8r found on the portal also holds the trip. A booking still waiting for the carrier to
// accept holds it too, ahead of the bills (owner, 23 Oct 2026), unless the server says it cannot be accepted yet.

/// Why one booking holds the trip, in the order the server checks. waitingForAccept is not about a bill; it sits
/// here because the server sends it in the same list.
enum EwayBillStartBlock {
  waitingForAccept,
  noBill,
  truckMissing,
  truckDiffers,
  expired,
  problem
}

/// Who reads the lines: the office can change the trip's truck, a driver can only call the office.
enum StartGateReader { carrierOffice, driver }

/// One booking that holds the trip, with its shipper's name. [shipmentId] is empty when none came.
typedef EwayBillStartHold = ({
  String shipmentId,
  String shipperName,
  EwayBillStartBlock block
});

/// Null when the booking does not hold the trip: an accepted one whose bill is final, a waiting one the server
/// says cannot be accepted yet (readyToAccept false, or missing from an older server), or any other status.
/// A trip with no truck differs from any truck. The truck and its valid-until time are saved together, so a
/// bill with no valid-until time has no truck yet. [now] is the phone's clock, which can be minutes off the
/// server's; the server decides at Start.
EwayBillStartBlock? ewayBillStartBlock(
    Map<String, dynamic> booking, String? tripTruckNumber, DateTime now) {
  if (booking['status'] == 'PENDING_CARRIER_ACCEPT') {
    return booking['readyToAccept'] == true
        ? EwayBillStartBlock.waitingForAccept
        : null;
  }
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
    EwayBillStartBlock.waitingForAccept => switch (reader) {
        StartGateReader.carrierOffice =>
          "$shipper's booking is waiting for you to accept.",
        StartGateReader.driver =>
          "$shipper's booking is waiting for your office to accept.",
      },
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
      "The valid-until time on $shipper's e-way bill has passed.",
    EwayBillStartBlock.problem =>
      "NaviG8r found a problem with $shipper's e-way bill.",
  };
}

/// The one line under [holds]. None for the office when only bookings to accept hold the trip: the office
/// accepts them, so there is no shipper to message.
String? ewayBillStartBlockFooter(
        StartGateReader reader, List<EwayBillStartHold> holds) =>
    switch (reader) {
      StartGateReader.carrierOffice => holds.any(
              (hold) => hold.block != EwayBillStartBlock.waitingForAccept)
          ? 'You can message the shipper from the booking.'
          : null,
      StartGateReader.driver => 'Call your office.',
    };

String _shipperName(Object? name) =>
    name is String && name.isNotEmpty ? name : 'The shipper';

String _shipmentId(Object? id) => id is String ? id : '';

/// Every booking on [trip] that holds it, empty when the trip may start. Those waiting to be accepted come
/// first, as in the server's list.
List<EwayBillStartHold> ewayBillStartHolds(
    Map<String, dynamic> trip, List<Map<String, dynamic>> bookings,
    {required DateTime now}) {
  final tripTruck = trip['assignedTruckNumber'];
  final holds = [
    for (final booking in bookings)
      if (ewayBillStartBlock(
              booking, tripTruck is String ? tripTruck : null, now)
          case final block?)
        (
          shipmentId: _shipmentId(booking['id']),
          shipperName: _shipperName(booking['customerOrgName']),
          block: block
        ),
  ];
  bool waiting(EwayBillStartHold hold) =>
      hold.block == EwayBillStartBlock.waitingForAccept;
  return [...holds.where(waiting), ...holds.where((hold) => !waiting(hold))];
}

const _blockByServerReason = {
  'waiting_for_accept': EwayBillStartBlock.waitingForAccept,
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
          (
            shipmentId: _shipmentId(shipment['shipmentId']),
            shipperName: _shipperName(shipment['shipperName']),
            block: block
          ),
  ];
  return holds.isEmpty ? null : holds;
}
