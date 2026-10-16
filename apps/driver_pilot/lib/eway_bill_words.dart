import 'eway_bill_closed.dart';
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

/// A truck number as the e-way bill portal takes it, the same rule as portalTruckNumber in the API: letters and
/// digits only, upper case, and in the state, district, series, number shape the district padded to two digits
/// and the number to four, so UP 1 345 is UP010345 (CBIC e-way bill FAQ, 2019). No district is 0: one starting
/// with 0 has two digits. With no series letters, a space or other mark typed between the district and the number
/// is where the district ends, so UP 32 345 is UP320345; with none typed, a district from 1 to 9 takes one digit,
/// which is how UP1345 reads as UP 1 345 and KA01123 as KA 01 123. Any other shape (temporary, Bharat series,
/// defence, foreign) is only cleaned.
String portalTruckNumber(String truck) {
  final typedApart = RegExp(
          r'^[^A-Za-z0-9]*([A-Za-z]{2})[^A-Za-z0-9]*(0[1-9]|[1-9][0-9]?)[^A-Za-z0-9]+([0-9]{1,4})[^A-Za-z0-9]*$')
      .firstMatch(truck);
  if (typedApart != null) {
    return '${typedApart[1]!.toUpperCase()}${typedApart[2]!.padLeft(2, '0')}${typedApart[3]!.padLeft(4, '0')}';
  }
  final cleaned = truck.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  final standardForm =
      RegExp(r'^([A-Z]{2})(0[1-9]|[1-9][0-9]??)([A-Z]{0,3})([0-9]{1,4})$')
          .firstMatch(cleaned);
  if (standardForm == null) return cleaned;
  return '${standardForm[1]}${standardForm[2]!.padLeft(2, '0')}${standardForm[3]}${standardForm[4]!.padLeft(4, '0')}';
}

/// Who reads the sentence about an e-way bill and a trip that name different trucks. Each is told only what they
/// can do.
enum TruckMismatchReader { carrierOffice, shipper, driver }

/// One plain sentence when the truck on the bill is not the truck the carrier assigned to the trip, or null
/// when they match, either is missing, or the shipment is closed and nothing about the bill can change. Both
/// go through the portal's form first, so UP1345 on the bill matches UP010345 on the trip.
String? ewayBillTruckMismatchSentence(
    Map<String, dynamic> shipment, Map<String, dynamic> bill,
    {required TruckMismatchReader reader}) {
  if (ewayBillIsClosed(shipment)) return null;
  final onBill = bill['truckNumber'];
  final onTrip = shipment['assignedTruckNumber'];
  if (onBill is! String || onTrip is! String) return null;
  if (portalTruckNumber(onBill).isEmpty || portalTruckNumber(onTrip).isEmpty) {
    return null;
  }
  if (portalTruckNumber(onBill) == portalTruckNumber(onTrip)) return null;
  return switch (reader) {
    TruckMismatchReader.carrierOffice =>
      'The e-way bill shows $onBill. The truck on this trip is $onTrip. Check which one is right; if the e-way bill is wrong, update it on the $ewayBillPortalName, then here.',
    TruckMismatchReader.shipper =>
      'The e-way bill shows $onBill. Your carrier has assigned $onTrip to this trip. Ask your carrier which truck is right.',
    TruckMismatchReader.driver =>
      'The e-way bill shows $onBill. The truck on this trip is $onTrip. Tell your carrier.',
  };
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
