import 'package:dio/dio.dart';

import 'pilot_api.dart';

/// The words both e-way bill cards use. They state only what ops saw and when, never that a bill is
/// valid now: a bill can change on the government portal and nothing here would hear about it. The
/// truck lines count down to the valid-until time as it was typed in, not as the portal holds it.
/// The real portal, unless the build points at the practice site: --dart-define=EWAY_PORTAL=http://.../demo/eway-portal
const ewayBillPortalAddress = String.fromEnvironment('EWAY_PORTAL',
    defaultValue: 'https://ewaybillgst.gov.in');

/// Says "government" only when the build really opens the government site.
String get ewayBillPortalButtonLabel =>
    ewayBillPortalAddress == 'https://ewaybillgst.gov.in'
        ? 'Open the government e-way bill portal'
        : 'Open the practice e-way bill portal';

/// Shown when the browser would not open; names the address this build actually uses.
String get ewayBillPortalOpenFailedSentence {
  // Authority, not host: the practice site's port is part of its address.
  final host = Uri.tryParse(ewayBillPortalAddress)?.authority ?? '';
  return 'Could not open the portal from here. Its address is ${host.isEmpty ? ewayBillPortalAddress : host}.';
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "14 Oct 2026" for a moment in time, read in India.
String ewayBillDateFromUtcMs(num utcMs) {
  final india = DateTime.fromMillisecondsSinceEpoch(utcMs.toInt(), isUtc: true)
      .add(const Duration(hours: 5, minutes: 30));
  return '${india.day} ${_monthNames[india.month - 1]} ${india.year}';
}

/// "16 Oct 2026, 23:59" for a moment in time, read in India. E-way bill times are India times.
String ewayBillDateTimeFromUtcMs(num utcMs) {
  final india = DateTime.fromMillisecondsSinceEpoch(utcMs.toInt(), isUtc: true)
      .add(const Duration(hours: 5, minutes: 30));
  return '${ewayBillDateFromUtcMs(utcMs)}, ${ewayBillClockTime(india.hour, india.minute)}';
}

/// "23:59", always 24-hour, so it reads the same as the portal.
String ewayBillClockTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// The truck on the bill and its valid-until time, or nothing when no truck is on it. The countdown
/// shows only in the last 12 hours, so it reads as a reminder, not as pressure.
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

/// The server writes a plain sentence for each refusal; show it instead of "HTTP 400".
String ewayBillErrorSentence(Object e) {
  if (e is DioException) {
    final body = e.response?.data;
    final detail = body is Map ? body['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
  }
  return formatApiError(e);
}

/// "1 Oct 2026" for a calendar date written as 2026-10-01.
String ewayBillDateFromCalendarDate(String date) {
  final parts = date.split('-');
  if (parts.length != 3) return date;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null || month < 1 || month > 12) return date;
  return '$day ${_monthNames[month - 1]} ${parts[0]}';
}

/// "1234 5678 9012", so it can be read aloud.
String groupedBillNumber(String number) {
  final groups = <String>[];
  for (var start = 0; start < number.length; start += 4) {
    groups.add(number.substring(start, (start + 4).clamp(0, number.length)));
  }
  return groups.join(' ');
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
    return 'Ops saw this bill on the government portal$date. It may have changed since.';
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
