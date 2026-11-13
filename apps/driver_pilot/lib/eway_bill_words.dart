import 'eway_bill_closed.dart';
import 'eway_bill_portal_link.dart';
import 'ui/format.dart';

// The words the e-way bill cards and screens use. They state only what ops saw and when,
// never that a bill is valid now: a bill can change on the government portal and nothing here would
// hear about it.

/// The truck on the bill and its valid-until time, or nothing when no truck is on it. The countdown
/// shows only in the last 12 hours, so it reads as a reminder, not as pressure. It runs to the
/// valid-until time as it was typed in, not as the portal holds it. [forShipper] is the shipper's
/// card, which also says that the trip cannot start and that the new time is entered here, until
/// [tripStarted]; after that it says only that the time has passed.
List<String> ewayBillTruckLines(Map<String, dynamic> bill,
    {DateTime? now, bool forShipper = false, bool tripStarted = false}) {
  final truck = bill['truckNumber'];
  if (truck is! String || truck.isEmpty) return const [];
  final lines = ['Truck on the bill: $truck'];
  final validUntil = bill['validUntilUtcMs'];
  if (validUntil is! num) return lines;
  final validUntilMoment =
      DateTime.fromMillisecondsSinceEpoch(validUntil.toInt(), isUtc: true);
  lines.add(
      'Valid until: ${formatDate(validUntilMoment, now: now)}, ${formatTimeIst(validUntilMoment)}');
  final left = validUntilMoment.difference(now ?? DateTime.now());
  if (left <= Duration.zero) {
    // naviG8r cannot see the portal, so it says only that the typed time has passed, not that the bill expired.
    lines.add(switch ((forShipper, tripStarted)) {
      (true, false) =>
        'The valid-until time you entered has passed, so the trip cannot start. Check the bill on the portal, then enter the new time here.',
      (true, true) => 'The valid-until time you entered has passed.',
      (false, _) => 'The valid-until time has passed. Check the bill on the portal.',
    });
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
/// can do: the shipper changes the bill, the carrier office changes the trip's truck.
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
  final carrierName = shipment['carrierDisplayName']?.toString().trim() ?? '';
  final carrier = carrierName.isEmpty ? 'the carrier' : carrierName;
  return switch (reader) {
    TruckMismatchReader.carrierOffice =>
      'The bill shows $onBill. The trip has $onTrip. If the bill is wrong, ask the shipper to fix it.',
    TruckMismatchReader.shipper =>
      'The bill shows $onBill. The trip has $onTrip. Ask $carrier which is right. If the bill is wrong, fix it on the portal, then here.',
    TruckMismatchReader.driver =>
      'The e-way bill shows $onBill. The truck on this trip is $onTrip. Tell your office.',
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

/// What ops saw, if ops looked the bill up. [forShipper] decides who is told what to do next. An
/// unlooked-up bill promises no check: NaviG8r does not check bills before the trip (owner, 22 Oct 2026).
/// Only the carrier office's step line reads an unlooked-up bill; the shipper's card never asks.
String ewayBillCheckLine(Map<String, dynamic> bill,
    {required bool forShipper}) {
  final check = bill['check'];
  if (check is! Map) return 'Entered by the shipper.';
  final checkedAt = check['checkedAtUtcMs'];
  final date = checkedAt is num
      ? ' on ${formatDate(DateTime.fromMillisecondsSinceEpoch(checkedAt.toInt(), isUtc: true))}'
      : '';
  if (check['result'] == 'FOUND') {
    return 'NaviG8r saw this bill on the $ewayBillPortalName$date. It may have changed since.';
  }
  final problem = switch (check['problemReason']) {
    'NOT_FOUND' => 'NaviG8r could not find this bill on the portal$date.',
    'CANCELLED' => 'NaviG8r saw on the portal that this bill was cancelled$date.',
    'DETAILS_DO_NOT_MATCH' =>
      'The details here did not match the portal when NaviG8r looked$date.',
    _ => 'NaviG8r found a problem with this bill$date.',
  };
  return forShipper
      ? '$problem Check the details here and on the portal.'
      : '$problem The shipper sees this too.';
}
