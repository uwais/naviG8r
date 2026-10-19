import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "maps_config.dart";

/// Why a place search failed, so the screen can say what is true and what to do next.
enum PlaceSearchFailure { nothingTyped, notFound, unreachable, notWorking }

class GeocodeOutcome {
  GeocodeOutcome._({this.position, this.formattedAddress, this.status, this.errorMessage});

  final LatLng? position;
  final String? formattedAddress;
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

  factory GeocodeOutcome.ok(LatLng position, String formattedAddress) {
    return GeocodeOutcome._(position: position, formattedAddress: formattedAddress, status: "OK");
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

/// Turns typed place words into a map point. Screens take it as a parameter so tests can stand
/// in for the geocoding service.
typedef PlaceFinder = Future<GeocodeOutcome> Function(String place);

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
      return GeocodeOutcome.ok(LatLng(lat.toDouble(), lng.toDouble()), formatted);
    } on DioException catch (e) {
      return GeocodeOutcome.fail("NETWORK", e.message);
    } catch (e) {
      return GeocodeOutcome.fail("ERROR", e.toString());
    }
  }

  /// The address of the town the point is in, or null. Only towns are asked for: a pin's own
  /// address starts with a house number, road or plus code, which is no name for a trip's city.
  static Future<String?> reverseLatLng(LatLng p, {String? apiKey}) async {
    final key = apiKey ?? kMapsApiKey;
    if (key.isEmpty) return null;

    try {
      final r = await dio.get<Map<String, dynamic>>(
        "https://maps.googleapis.com/maps/api/geocode/json",
        queryParameters: {
          "latlng": "${p.latitude},${p.longitude}",
          "result_type": "locality",
          "key": key,
        },
      );
      final data = r.data;
      if (data == null) return null;
      if (data["status"] != "OK") return null;
      final results = data["results"];
      if (results is! List<dynamic> || results.isEmpty) return null;
      final first = results.first;
      if (first is Map<String, dynamic>) {
        return first["formatted_address"] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
