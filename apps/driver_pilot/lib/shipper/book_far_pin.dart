// Book's far-pin rule, the server's own: a pickup near the trip's start town and a drop near its end
// town. The words when a pin is outside it, and when the server refuses a booking for it.
import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../ui/format.dart";
import "../ui/tokens.dart";
import "trip_route.dart";

/// Mirrors the server's default limit (phaseAEndpointRadiiKm in apps/api/src/services.ts): a pickup
/// within this many km of the trip's start town pin, and a drop within it of the end town pin.
const farPinLimitKm = 15;

/// How far [pin] is from [townPin] when that is more than [farPinLimitKm]. Null when it is within it, or
/// when either pin is missing: the server does not hold a trip without town pins to the limit either.
double? farPinKm(LatLng? pin, LatLng? townPin) {
  if (pin == null || townPin == null) return null;
  final km = kmBetween(pin, townPin);
  return km > farPinLimitKm ? km : null;
}

/// A Book place box, with a line under it while its pin is [farKm] from [town]. Always a Column, so
/// each box keeps its place in the list, and its search state, as the line comes and goes.
Widget withFarPinLine(Widget placeBox,
        {required bool pickup, required double? farKm, required String town}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        placeBox,
        if (farKm != null) ...[
          const SizedBox(height: NvSpace.s2),
          Semantics(
              liveRegion: true,
              // Rounded up: a pin refused at 15.3 km must not read "about 15 km".
              child: Text(
                  "This pin is about ${formatKm(farKm.ceil())} from $town. This trip ${pickup ? "picks up" : "drops"} within $farPinLimitKm km of $town.",
                  style: NvText.caption.copyWith(color: NvColors.problem))),
        ],
      ],
    );

/// The help under Book and pay while a pin is too far, or null when neither is.
String? farPinsHelp({required bool pickupFar, required bool dropFar}) {
  final pins = switch ((pickupFar, dropFar)) {
    (true, true) => "pickup and drop pins",
    (true, false) => "pickup pin",
    (false, true) => "drop pin",
    (false, false) => null,
  };
  return pins == null ? null : "Move the $pins, or choose another trip.";
}

/// What Book says when the server refuses a booking for its pins (phase_a_not_eligible), from the limits
/// in the server's answer [body], or [farPinLimitKm] when it has none.
String farPinsRefusal(Object? body, {required String startTown, required String endTown}) {
  // Rounded down: the limit shown is never more than the server allows.
  String limit(String field) {
    final km = body is Map ? body[field] : null;
    return formatKm(km is num && km > 0 ? km.floor() : farPinLimitKm);
  }

  return "This trip picks up within ${limit("maxPickupKm")} of $startTown and drops within ${limit("maxDropKm")} of $endTown. Move the pins or choose another trip.";
}
