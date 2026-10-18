// E-way bill dates and times, always read in India whatever zone the phone is set to.

/// India has no daylight saving, so one fixed offset is right all year.
const indiaTimeOffset = Duration(hours: 5, minutes: 30);

/// "23:59", always 24-hour, so it reads the same as the portal.
String ewayBillClockTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
