// The plain words both sides of the Load Board use for a posted load: its route, size, pickup days and state.
// A posted load carries no amount of any kind, so nothing here writes one.
import "../ui/format.dart";
import "../ui/nv_status_label.dart";

/// A "YYYY-MM-DD" calendar day in India, held as midnight UTC so days compare directly. Null if unreadable.
DateTime? calendarDay(Object? day) {
  final match = RegExp(r"^(\d{4})-(\d{2})-(\d{2})$").firstMatch("${day ?? ""}");
  if (match == null) return null;
  return DateTime.utc(
      int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
}

/// The "YYYY-MM-DD" the server reads for [day].
String calendarDayText(DateTime day) =>
    "${day.year.toString().padLeft(4, "0")}-${day.month.toString().padLeft(2, "0")}-${day.day.toString().padLeft(2, "0")}";

/// Today in India, as [calendarDay] holds a day.
DateTime todayInIndia({DateTime? now}) {
  final india =
      (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime.utc(india.year, india.month, india.day);
}

/// "Pune to Mumbai". The shipper's copy names its places `from` and `to`; the board's, `fromCity` and `toCity`.
String postedLoadRoute(Map<String, dynamic> load) {
  String city(String place, String boardField) {
    final named = load[place];
    return (named is Map ? named["city"] : load[boardField])?.toString() ?? "";
  }

  return "${city("from", "fromCity")} to ${city("to", "toCity")}";
}

/// "5 – 6 Nov", or "5 Nov" when the first and last pickup days are the same.
String? pickupDaysWords(Map<String, dynamic> load) {
  final first = calendarDay(load["earliestPickupDate"]);
  final last = calendarDay(load["latestPickupDate"]);
  if (first == null || last == null) return null;
  return formatDateRange(first, last);
}

String? loadWeightWords(Map<String, dynamic> load) {
  final weight = load["weightKg"];
  return weight is num ? formatKg(weight) : null;
}

String _number(num value) =>
    value == value.roundToDouble() ? value.round().toString() : "$value";

/// "12 packages, each 40 by 30 by 20 inches", or "120 cubic feet": the size as the shipper entered it.
String? packagesWords(Object? packages) {
  if (packages is! Map) return null;
  if (packages["kind"] == "SIZES") {
    final count = packages["count"];
    final sides = [packages["length"], packages["width"], packages["height"]];
    final unit = switch (packages["unit"]) {
      "INCHES" => "inches",
      "CENTIMETRES" => "cm",
      _ => null,
    };
    if (count is! num || unit == null || sides.any((side) => side is! num)) {
      return null;
    }
    final sizes = sides.map((side) => _number(side as num)).join(" by ");
    final what = count == 1 ? "1 package" : "${_number(count)} packages, each";
    return "$what $sizes $unit";
  }
  if (packages["kind"] == "TOTAL_VOLUME") {
    final volume = packages["volume"];
    final unit = switch (packages["unit"]) {
      "CUBIC_FEET" => "cubic feet",
      "CUBIC_METRES" => "cubic metres",
      _ => null,
    };
    if (volume is! num || unit == null) return null;
    return "${_number(volume)} $unit";
  }
  return null;
}

NvStatusLabel postedLoadStateLabel(String state) => switch (state) {
      "OPEN" => const NvStatusLabel("Open", tone: NvStatusTone.good),
      "BOOKED" => const NvStatusLabel("Booked", tone: NvStatusTone.info),
      "WITHDRAWN" => const NvStatusLabel("Withdrawn", tone: NvStatusTone.ended),
      "EXPIRED" =>
        const NvStatusLabel("Pickup days passed", tone: NvStatusTone.ended),
      _ => NvStatusLabel(state.isEmpty ? "Unknown" : state,
          tone: NvStatusTone.ended),
    };
