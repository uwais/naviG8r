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
        {required double? farKm, required String town}) =>
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
                  "About ${formatKm(farKm.ceil())} from $town.",
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

/// The rule as Book states it under the trip, before anything is typed.
String farPinRule({required String startTown, required String endTown}) =>
    "Picks up within $farPinLimitKm km of $startTown and drops within $farPinLimitKm km of $endTown.";

/// What Book says when the server refuses a booking for its pins (phase_a_not_eligible): the [sentence]
/// above Book and pay and the [help] under it. Which pin is too far, and how far, comes from the server's
/// answer [body]; without it, both pins. The server's own limit for a far pin is said too, so a tighter
/// limit never reads against the 15 km rule in [farPinRule] above the pins. Without a limit, a pin is held
/// to [farPinLimitKm] and no limit is said.
({String sentence, String help}) farPinsRefusal(Object? body,
    {required String startTown, required String endTown}) {
  num? number(String field) {
    final value = body is Map ? body[field] : null;
    return value is num && value >= 0 ? value : null;
  }

  final (pickupKm, dropKm) = (number("pickupDistanceKm"), number("dropDistanceKm"));
  final (maxPickupKm, maxDropKm) = (number("maxPickupKm"), number("maxDropKm"));
  // Rounded up, a distance is never shown as within the limit; rounded down, the limit shown is never
  // more than the server allows.
  String away(num km) => "about ${formatKm(km.ceil())}";
  String limit(num km) => formatKm(km.floor());
  final pickupFar = pickupKm != null && pickupKm > (maxPickupKm ?? farPinLimitKm);
  final dropFar = dropKm != null && dropKm > (maxDropKm ?? farPinLimitKm);
  final pins = switch ((pickupFar, dropFar)) {
    (true, false) => "Pickup pin is ${away(pickupKm!)} from $startTown.",
    (false, true) => "Drop pin is ${away(dropKm!)} from $endTown.",
    (true, true) =>
      "Pickup pin is ${away(pickupKm!)} from $startTown, drop pin ${away(dropKm!)} from $endTown.",
    (false, false) => "A pin is too far from $startTown or $endTown.",
  };
  final limits = [
    if (pickupFar && maxPickupKm != null) "picks up within ${limit(maxPickupKm)}",
    if (dropFar && maxDropKm != null) "drops within ${limit(maxDropKm)}",
  ];
  final named = pickupFar || dropFar;
  return (
    sentence: limits.isEmpty ? pins : "$pins This trip ${limits.join(" and ")}.",
    help: farPinsHelp(pickupFar: pickupFar || !named, dropFar: dropFar || !named)!,
  );
}
