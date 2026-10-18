// E-way bill dates and times, always read in India whatever zone the phone is set to.

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
