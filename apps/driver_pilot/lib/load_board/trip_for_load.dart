// Adding a trip for a posted load (Load Board phase 1, 4 Nov 2026): what today's Add a trip form is handed, the
// line it shows about the load, and the server's refusals in words. The trip is otherwise an ordinary trip.
import "package:dio/dio.dart" show DioException;
import "package:flutter/material.dart";

import "../ui/format.dart";
import "../ui/tokens.dart";
import "posted_load_words.dart";

/// The board's load, as the Add a trip form gets it in the router's extra. The board shows only towns, weight,
/// size and pickup days, so that is all there is here.
class LoadForTrip {
  const LoadForTrip({
    required this.id,
    required this.fromCity,
    required this.toCity,
    required this.weightKg,
    required this.firstPickupDay,
    required this.lastPickupDay,
  });

  final String id;
  final String fromCity;
  final String toCity;
  final num weightKg;
  final DateTime firstPickupDay;
  final DateTime lastPickupDay;

  /// Null when the board's row is missing a field the form needs.
  static LoadForTrip? fromBoard(Map<String, dynamic> load) {
    final id = load["id"]?.toString() ?? "";
    final from = load["fromCity"]?.toString() ?? "";
    final to = load["toCity"]?.toString() ?? "";
    final weight = load["weightKg"];
    final first = calendarDay(load["earliestPickupDate"]);
    final last = calendarDay(load["latestPickupDate"]);
    if (id.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        weight is! num ||
        first == null ||
        last == null) {
      return null;
    }
    return LoadForTrip(
        id: id,
        fromCity: from,
        toCity: to,
        weightKg: weight,
        firstPickupDay: first,
        lastPickupDay: last);
  }

  /// Whole kilograms, as the capacity field takes them, rounded up so the trip always has room.
  int get weightKgRoundedUp => weightKg.ceil();
}

/// Above the form: which load the trip is for, and the rule the server holds it to.
class LoadForTripSummary extends StatelessWidget {
  const LoadForTripSummary(this.load, {super.key});
  final LoadForTrip load;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.infoTint,
            borderRadius: BorderRadius.circular(NvRadius.card)),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("FOR A POSTED LOAD", style: NvText.label),
              const SizedBox(height: NvSpace.s1),
              Text("${load.fromCity} to ${load.toCity}",
                  style: NvText.bodyStrong),
              Text(
                  "${formatKg(load.weightKg)} · pickup ${formatDateRange(load.firstPickupDay, load.lastPickupDay)}",
                  style: NvText.body),
              const SizedBox(height: NvSpace.s2),
              const Text(
                  "Start near the pickup town and end near the drop town. The shipper may book your trip, another carrier's, or none. Other shippers can book any capacity left.",
                  style: NvText.caption),
            ],
          ),
        ),
      );
}

/// The server's refusal of a trip for a load, in words, or null for any other answer.
String? tripForLoadRefusal(Object error) {
  final body = error is DioException ? error.response?.data : null;
  final code = body is Map ? body["error"] : null;
  final weight = body is Map ? body["weightKg"] : null;
  return switch (code) {
    "posted_load_not_open" =>
      "This load is no longer on the Load Board. The shipper booked or withdrew it, or its pickup days passed.",
    "posted_load_not_found" => "This load is no longer on the Load Board.",
    "route_cities_do_not_match_load" =>
      "The trip must go from the load's pickup town to its drop town.",
    "route_too_small_for_load" => weight is num
        ? "The capacity must be at least ${formatKg(weight)} for this load."
        : "The capacity is too small for this load.",
    "route_too_far_from_load" => body is Map && body["detail"] is String
        ? body["detail"] as String
        : "Start the trip near the load's pickup town and end it near its drop town.",
    _ => null,
  };
}
