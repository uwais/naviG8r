import 'eway_bill_dates.dart';
import 'eway_bill_portal_link.dart';

// The words both e-way bill cards and the shipment lists use. They state only what ops saw and when,
// never that a bill is valid now: a bill can change on the government portal and nothing here would
// hear about it.

/// "1234 5678 9012", so it can be read aloud.
String groupedBillNumber(String number) {
  final groups = <String>[];
  for (var start = 0; start < number.length; start += 4) {
    groups.add(number.substring(start, (start + 4).clamp(0, number.length)));
  }
  return groups.join(' ');
}

/// One line for a shipment list row, or '' when the row should say nothing. It says ops flagged a bill,
/// never that a bill is fine or wrong: a row has no room for "when, and it may have changed". A shipment
/// with no bill gets a line only before pickup, while one could still be added. Every value is
/// type-checked so a row cannot throw.
String ewayBillRowSummary(Map<String, dynamic> shipment) {
  final bill = shipment['ewayBill'];
  if (bill is! Map) {
    final status = shipment['status'];
    return status == 'PENDING_CARRIER_ACCEPT' || status == 'BOOKED'
        ? 'E-way bill: none added'
        : '';
  }
  if (bill['kind'] == 'NOT_NEEDED') {
    return 'No e-way bill needed (the shipper says so)';
  }
  if (bill['kind'] != 'BILL') return 'E-way bill: open the shipment to see it';
  final number = bill['billNumber'];
  final truck = bill['truckNumber'];
  final check = bill['check'];
  final numberWords = number is String && number.isNotEmpty
      ? 'E-way bill ${groupedBillNumber(number)}'
      : 'E-way bill';
  final truckWords =
      truck is String && truck.isNotEmpty ? 'truck $truck' : 'truck not added';
  final flaggedWords = check is Map && check['result'] == 'PROBLEM'
      ? '. Ops flagged this bill. Open it to see why.'
      : '';
  return '$numberWords, $truckWords$flaggedWords';
}

/// The truck on the bill and its valid-until time, or nothing when no truck is on it. The countdown
/// shows only in the last 12 hours, so it reads as a reminder, not as pressure. It runs to the
/// valid-until time as it was typed in, not as the portal holds it.
List<String> ewayBillTruckLines(Map<String, dynamic> bill, {DateTime? now}) {
  final truck = bill['truckNumber'];
  if (truck is! String || truck.isEmpty) return const [];
  final lines = ['Truck: $truck'];
  final validUntil = bill['validUntilUtcMs'];
  if (validUntil is! num) return lines;
  lines.add(
      'Valid until: ${ewayBillDateTimeFromUtcMs(validUntil)} (India time)');
  final left =
      DateTime.fromMillisecondsSinceEpoch(validUntil.toInt(), isUtc: true)
          .difference(now ?? DateTime.now());
  if (left <= Duration.zero) {
    // naviG8r cannot see the portal, so it says only that the typed time has passed, not that the bill expired.
    lines.add('The valid-until time entered has passed. Check the portal.');
  } else if (left < const Duration(hours: 12)) {
    final hours = left.inHours;
    lines.add(switch (hours) {
      0 => 'Expires in less than an hour',
      1 => 'Expires in 1 hour',
      _ => 'Expires in $hours hours',
    });
  }
  return lines;
}

/// The reasons a shipper can give, in the order shown, none chosen to start.
const notNeededReasonChoices = {
  'BELOW_THRESHOLD': 'Below the value that needs one',
  'GOODS_EXEMPT': 'These goods do not need one',
  'OTHER': 'Other',
};

String notNeededReasonWords(Map<String, dynamic> bill) {
  switch (bill['notNeededReason']) {
    case 'BELOW_THRESHOLD':
    case 'GOODS_EXEMPT':
      return notNeededReasonChoices[bill['notNeededReason']]!;
    default:
      final note = bill['notNeededNote'];
      return note is String && note.isNotEmpty ? note : 'Other';
  }
}

/// What ops saw. [forShipper] decides who is told what to do next and how the unchecked state reads.
String ewayBillCheckLine(Map<String, dynamic> bill,
    {required bool forShipper}) {
  final check = bill['check'];
  if (check is! Map) {
    return forShipper ? 'Entered by you. Not checked yet.' : 'Not checked yet.';
  }
  final checkedAt = check['checkedAtUtcMs'];
  final date =
      checkedAt is num ? ' on ${ewayBillDateFromUtcMs(checkedAt)}' : '';
  if (check['result'] == 'FOUND') {
    return 'Ops saw this bill on the $ewayBillPortalName$date. It may have changed since.';
  }
  final problem = switch (check['problemReason']) {
    'NOT_FOUND' => 'Ops could not find this bill on the portal$date.',
    'CANCELLED' => 'Ops saw on the portal that this bill was cancelled$date.',
    'DETAILS_DO_NOT_MATCH' =>
      'The details here did not match the portal when ops looked$date.',
    _ => 'Ops found a problem with this bill$date.',
  };
  return forShipper
      ? '$problem Check the details here and on the portal.'
      : '$problem The shipper can see this on their shipment.';
}
