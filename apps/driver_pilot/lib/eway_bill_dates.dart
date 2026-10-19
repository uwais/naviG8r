// E-way bill dates and times, always read in India whatever zone the phone is set to.

import 'package:flutter/foundation.dart';

/// India has no daylight saving, so one fixed offset is right all year.
const indiaTimeOffset = Duration(hours: 5, minutes: 30);

/// Where [indiaToday] reads the time. Tests set a fixed moment, because India's date differs from the
/// phone's for part of every day and a test must not pass or fail by when it runs.
@visibleForTesting
DateTime Function() ewayBillClock = DateTime.now;

/// Today's date in India, as a plain date for a date picker. A bill is dated in India, so a phone
/// still on yesterday must still offer India's today.
DateTime indiaToday() {
  final india = ewayBillClock().toUtc().add(indiaTimeOffset);
  return DateTime(india.year, india.month, india.day);
}

/// "23:59", always 24-hour, so it reads the same as the portal.
String ewayBillClockTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
