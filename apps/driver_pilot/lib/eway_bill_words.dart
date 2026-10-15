/// The words both e-way bill cards use. They state only what ops saw and when, never that a bill is
/// valid now: a bill can change on the government portal and nothing here would hear about it.
const ewayBillPortalAddress = 'https://ewaybillgst.gov.in';

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

String notNeededReasonWords(Map<String, dynamic> bill) {
  switch (bill['notNeededReason']) {
    case 'BELOW_THRESHOLD':
      return 'Below the value that needs one';
    case 'GOODS_EXEMPT':
      return 'These goods do not need one';
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
