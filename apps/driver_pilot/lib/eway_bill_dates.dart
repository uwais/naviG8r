// E-way bill dates and times, always read in India whatever zone the phone is set to, and the truck's
// valid-until lines. The countdown runs to the valid-until time as it was typed in, not as the portal
// holds it.

/// India has no daylight saving, so one fixed offset is right all year.
const indiaTimeOffset = Duration(hours: 5, minutes: 30);

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

DateTime _inIndia(num utcMs) =>
    DateTime.fromMillisecondsSinceEpoch(utcMs.toInt(), isUtc: true)
        .add(indiaTimeOffset);

/// "14 Oct 2026" for a moment in time, read in India.
String ewayBillDateFromUtcMs(num utcMs) {
  final india = _inIndia(utcMs);
  return '${india.day} ${_monthNames[india.month - 1]} ${india.year}';
}

/// "16 Oct 2026, 23:59" for a moment in time, read in India. E-way bill times are India times.
String ewayBillDateTimeFromUtcMs(num utcMs) {
  final india = _inIndia(utcMs);
  return '${ewayBillDateFromUtcMs(utcMs)}, ${ewayBillClockTime(india.hour, india.minute)}';
}

/// "23:59", always 24-hour, so it reads the same as the portal.
String ewayBillClockTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// "1 Oct 2026" for a calendar date written as 2026-10-01.
String ewayBillDateFromCalendarDate(String date) {
  final parts = date.split('-');
  if (parts.length != 3) return date;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null || month < 1 || month > 12) return date;
  return '$day ${_monthNames[month - 1]} ${parts[0]}';
}

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
