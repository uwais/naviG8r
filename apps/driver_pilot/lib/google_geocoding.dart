import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "maps_config.dart";

/// Why a place search failed, so the screen can say what is true and what to do next.
enum PlaceSearchFailure { nothingTyped, notFound, unreachable, notWorking }

/// The sentence for a failed place search. [pinOnMap] is whether the screen has a map pin the
/// person can drag to the place instead; without one, the pin advice would be untrue.
String placeSearchFailureSentence(PlaceSearchFailure? failure, {required bool pinOnMap}) =>
    switch (failure) {
      PlaceSearchFailure.nothingTyped => "Type a town or area, then search.",
      PlaceSearchFailure.notFound => pinOnMap
          ? "Could not find this place. Try a nearby town, or drag the pin on the map to it."
          : "Could not find this place. Try a nearby town.",
      PlaceSearchFailure.unreachable =>
        "Could not reach the map service. Check your connection, then search again.",
      PlaceSearchFailure.notWorking || null => pinOnMap
          ? "Place search is not working right now. Drag the pin on the map to the place."
          : "Place search is not working right now. Try again later.",
    };

class GeocodeOutcome {
  GeocodeOutcome._({this.position, this.formattedAddress, this.placeName, this.status, this.errorMessage});

  final LatLng? position;
  final String? formattedAddress;

  /// The short name a trip's city field takes: the town when Google names one.
  final String? placeName;
  final String? status;
  final String? errorMessage;

  bool get isOk => position != null && status == "OK";

  PlaceSearchFailure? get failure => isOk
      ? null
      : switch (status) {
          "EMPTY" => PlaceSearchFailure.nothingTyped,
          "ZERO_RESULTS" => PlaceSearchFailure.notFound,
          // Timeouts, no connection and HTTP error codes all arrive as a DioException.
          "NETWORK" => PlaceSearchFailure.unreachable,
          // A missing or refused key, a used-up quota, or an answer the app cannot read.
          _ => PlaceSearchFailure.notWorking,
        };

  factory GeocodeOutcome.ok(LatLng position, String formattedAddress, [String? townName]) {
    return GeocodeOutcome._(
      position: position,
      formattedAddress: formattedAddress,
      placeName: townName ?? placeNameFromAddress(formattedAddress),
      status: "OK",
    );
  }

  factory GeocodeOutcome.fail(String status, [String? errorMessage]) {
    return GeocodeOutcome._(status: status, errorMessage: errorMessage);
  }
}

/// The place's own name, the first part of its address: "Hoskote" from
/// "Hoskote, Karnataka 562114, India". Null when that part is empty.
String? placeNameFromAddress(String? address) {
  final name = address?.split(",").first.trim() ?? "";
  return name.isEmpty ? null : name;
}

/// The town a Google result is in, read from its parts. Google's docs say not to parse
/// formatted_address, whose first part is often a road ("NH 75, Hoskote, ...").
String? _townName(Map<String, dynamic> result) {
  final parts = result["address_components"];
  if (parts is! List<dynamic>) return null;
  for (final part in parts) {
    if (part is! Map<String, dynamic>) continue;
    final types = part["types"];
    if (types is! List<dynamic> || !types.contains("locality")) continue;
    final name = (part["long_name"] as String? ?? "").trim();
    if (name.isNotEmpty) return name;
  }
  return null;
}

/// Turns typed place words into a map point. Screens take it as a parameter so tests can stand
/// in for the geocoding service.
typedef PlaceFinder = Future<GeocodeOutcome> Function(String place);

/// Names a map point: the town it is in for a trip ([GoogleGeocodingService.reverseLatLng]), or
/// its full address for a pickup or drop ([GoogleGeocodingService.reverseAddress]). Screens take it
/// as a parameter so tests can stand in for the geocoding service.
typedef PinNamer = Future<GeocodeOutcome> Function(LatLng point);

/// Forward / reverse geocoding via Google Geocoding API (same key as Maps SDK).
class GoogleGeocodingService {
  GoogleGeocodingService._();

  @visibleForTesting
  static Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
  ));

  static Future<GeocodeOutcome> forwardAddress(String address, {String? apiKey}) async {
    final key = apiKey ?? kMapsApiKey;
    if (key.isEmpty) return GeocodeOutcome.fail("NO_API_KEY", "Set MAPS_API_KEY (--dart-define) for look up.");
    final q = address.trim();
    if (q.isEmpty) return GeocodeOutcome.fail("EMPTY", "Enter a place or address.");

    try {
      final r = await dio.get<Map<String, dynamic>>(
        "https://maps.googleapis.com/maps/api/geocode/json",
        queryParameters: {"address": q, "key": key},
      );
      final data = r.data;
      if (data == null) return GeocodeOutcome.fail("NO_BODY");
      final status = data["status"] as String? ?? "UNKNOWN";
      final err = data["error_message"] as String?;
      if (status != "OK") return GeocodeOutcome.fail(status, err);

      final results = data["results"];
      if (results is! List<dynamic> || results.isEmpty) {
        return GeocodeOutcome.fail("ZERO_RESULTS", "No matches — try adding state or landmark.");
      }
      final first = results.first;
      if (first is! Map<String, dynamic>) return GeocodeOutcome.fail("BAD_RESPONSE");
      final loc = first["geometry"]?["location"];
      if (loc is! Map<String, dynamic>) return GeocodeOutcome.fail("BAD_RESPONSE");
      final lat = loc["lat"];
      final lng = loc["lng"];
      if (lat is! num || lng is! num) return GeocodeOutcome.fail("BAD_RESPONSE");
      final formatted = first["formatted_address"] as String? ?? q;
      return GeocodeOutcome.ok(LatLng(lat.toDouble(), lng.toDouble()), formatted, _townName(first));
    } on DioException catch (e) {
      return GeocodeOutcome.fail("NETWORK", e.message);
    } catch (e) {
      return GeocodeOutcome.fail("ERROR", e.toString());
    }
  }

  /// The town the point is in. Only towns are asked for: a pin's own address starts with a
  /// house number, road or plus code, which is no name for a trip's city. A spot with no town
  /// comes back as ZERO_RESULTS.
  static Future<GeocodeOutcome> reverseLatLng(LatLng p, {String? apiKey}) =>
      _reverse(p, townOnly: true, apiKey: apiKey);

  /// The point's full address (street, area, town, pin), for a pickup or drop the carrier has to
  /// find: Google's closest result, with no result_type filter.
  static Future<GeocodeOutcome> reverseAddress(LatLng p, {String? apiKey}) =>
      _reverse(p, townOnly: false, apiKey: apiKey);

  static Future<GeocodeOutcome> _reverse(LatLng p,
      {required bool townOnly, String? apiKey}) async {
    final key = apiKey ?? kMapsApiKey;
    if (key.isEmpty) return GeocodeOutcome.fail("NO_API_KEY");

    try {
      final r = await dio.get<Map<String, dynamic>>(
        "https://maps.googleapis.com/maps/api/geocode/json",
        queryParameters: {
          "latlng": "${p.latitude},${p.longitude}",
          if (townOnly) "result_type": "locality",
          "key": key,
        },
      );
      final data = r.data;
      if (data == null) return GeocodeOutcome.fail("NO_BODY");
      final status = data["status"] as String? ?? "UNKNOWN";
      if (status != "OK") return GeocodeOutcome.fail(status, data["error_message"] as String?);
      final results = data["results"];
      if (results is! List<dynamic> || results.isEmpty) return GeocodeOutcome.fail("ZERO_RESULTS");
      final first = results.first;
      if (first is! Map<String, dynamic>) return GeocodeOutcome.fail("BAD_RESPONSE");
      final formatted = first["formatted_address"] as String?;
      if (formatted == null) return GeocodeOutcome.fail("BAD_RESPONSE");
      return GeocodeOutcome.ok(p, formatted, _townName(first));
    } on DioException catch (e) {
      return GeocodeOutcome.fail("NETWORK", e.message);
    } catch (e) {
      return GeocodeOutcome.fail("ERROR", e.toString());
    }
  }
}
