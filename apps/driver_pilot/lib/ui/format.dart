// The app's one way to write dates, times, money, weights and bill numbers
// (spec/copy.md, "Formats"). Dates and times are always read in India, whatever zone the phone is in.

// India has no daylight saving, so one fixed offset is right all year.
const _indiaOffset = Duration(hours: 5, minutes: 30);

const _monthNames = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

DateTime _inIndia(DateTime moment) => moment.toUtc().add(_indiaOffset);

String _dayAndMonth(DateTime india) =>
    "${india.day} ${_monthNames[india.month - 1]}";

/// "18 Oct", or "18 Oct 2026" when the year is not this year or [withYear] is set (forms).
String formatDate(DateTime moment, {DateTime? now, bool withYear = false}) {
  final india = _inIndia(moment);
  final thisYear = _inIndia(now ?? DateTime.now()).year;
  if (withYear || india.year != thisYear) {
    return "${_dayAndMonth(india)} ${india.year}";
  }
  return _dayAndMonth(india);
}

/// "18 – 19 Oct", "30 Oct – 2 Nov", or "18 Oct" when both ends are the same day.
String formatDateRange(DateTime start, DateTime end, {DateTime? now}) {
  final first = _inIndia(start);
  final last = _inIndia(end);
  final thisYear = _inIndia(now ?? DateTime.now()).year;
  if (first.year != last.year) {
    return "${_dayAndMonth(first)} ${first.year} – ${_dayAndMonth(last)} ${last.year}";
  }
  final yearSuffix = last.year == thisYear ? "" : " ${last.year}";
  if (first.month != last.month) {
    return "${_dayAndMonth(first)} – ${_dayAndMonth(last)}$yearSuffix";
  }
  if (first.day != last.day) {
    return "${first.day} – ${_dayAndMonth(last)}$yearSuffix";
  }
  return "${_dayAndMonth(last)}$yearSuffix";
}

/// "16:40 IST", always 24-hour.
String formatTimeIst(DateTime moment) {
  final india = _inIndia(moment);
  final hour = india.hour.toString().padLeft(2, "0");
  final minute = india.minute.toString().padLeft(2, "0");
  return "$hour:$minute IST";
}

/// "₹1,25,000" from an amount in paise, with Indian digit grouping. Paise appear only when
/// they are not zero: "₹2,640.50".
String formatRupees(num paise) {
  assert(paise >= 0, "amounts shown to people are never negative");
  final totalPaise = paise.round();
  final rupees = _indianGrouping(totalPaise ~/ 100);
  final paiseLeft = totalPaise % 100;
  if (paiseLeft == 0) return "₹$rupees";
  return "₹$rupees.${paiseLeft.toString().padLeft(2, "0")}";
}

// Indian grouping: the last three digits together, then pairs ("1,25,000").
String _indianGrouping(int number) {
  final digits = number.toString();
  if (digits.length <= 3) return digits;
  var leading = digits.substring(0, digits.length - 3);
  final groups = [digits.substring(digits.length - 3)];
  while (leading.length > 2) {
    groups.insert(0, leading.substring(leading.length - 2));
    leading = leading.substring(0, leading.length - 2);
  }
  groups.insert(0, leading);
  return groups.join(",");
}

/// "45 km", "1,834 km": rounded to the whole km, with the same Indian grouping as rupees.
String formatKm(num kilometres) => "${_indianGrouping(kilometres.round())} km";

/// "80 kg", "2,400 kg", with the same Indian grouping as rupees.
String formatKg(num kilograms) {
  final whole = kilograms == kilograms.roundToDouble();
  final digits = (whole ? kilograms.round() : kilograms).toString().split(".");
  final grouped = _indianGrouping(int.parse(digits.first));
  return "${digits.length == 2 ? "$grouped.${digits.last}" : grouped} kg";
}

/// "3412 0098 7654", in groups of four so it can be read aloud. Copy the number without spaces.
String formatBillNumber(String number) {
  final digits = number.replaceAll(RegExp(r"\s"), "");
  final groups = <String>[];
  for (var start = 0; start < digits.length; start += 4) {
    groups.add(digits.substring(start, (start + 4).clamp(0, digits.length)));
  }
  return groups.join(" ");
}

/// "Bengaluru to Chennai, 18 Oct": how a shipment is named everywhere, never by its ID.
String shipmentName(
    {required String from,
    required String to,
    required DateTime date,
    DateTime? now}) {
  return "$from to $to, ${formatDate(date, now: now)}";
}

/// "+91 98450 12345" for an Indian mobile number, with or without the 91 in front. Any other
/// number comes back as it was given.
String formatPhone(String phone) {
  var digits = phone.replaceAll(RegExp(r"\D"), "");
  if (digits.length == 12 && digits.startsWith("91")) {
    digits = digits.substring(2);
  }
  if (digits.length != 10) return phone;
  return "+91 ${digits.substring(0, 5)} ${digits.substring(5)}";
}
