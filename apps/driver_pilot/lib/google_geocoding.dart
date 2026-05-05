import "package:dio/dio.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "maps_config.dart";

class GeocodeOutcome {
  GeocodeOutcome._({this.position, this.formattedAddress, this.status, this.errorMessage});

  final LatLng? position;
  final String? formattedAddress;
  final String? status;
  final String? errorMessage;

  bool get isOk => position != null && status == "OK";

  factory GeocodeOutcome.ok(LatLng position, String formattedAddress) {
    return GeocodeOutcome._(position: position, formattedAddress: formattedAddress, status: "OK");
  }

  factory GeocodeOutcome.fail(String status, [String? errorMessage]) {
    return GeocodeOutcome._(status: status, errorMessage: errorMessage);
  }
}

/// Forward / reverse geocoding via Google Geocoding API (same key as Maps SDK).
class GoogleGeocodingService {
  GoogleGeocodingService._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
  ));

  static Future<GeocodeOutcome> forwardAddress(String address, {String? apiKey}) async {
    final key = apiKey ?? kMapsApiKey;
    if (key.isEmpty) return GeocodeOutcome.fail("NO_API_KEY", "Set MAPS_API_KEY (--dart-define) for look up.");
    final q = address.trim();
    if (q.isEmpty) return GeocodeOutcome.fail("EMPTY", "Enter a place or address.");

    try {
      final r = await _dio.get<Map<String, dynamic>>(
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

  static Future<String?> reverseLatLng(LatLng p, {String? apiKey}) async {
    final key = apiKey ?? kMapsApiKey;
    if (key.isEmpty) return null;

    try {
      final r = await _dio.get<Map<String, dynamic>>(
        "https://maps.googleapis.com/maps/api/geocode/json",
        queryParameters: {
          "latlng": "${p.latitude},${p.longitude}",
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
