import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";

/// Production API. Override at run/build time:
/// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` (Android emulator → host)
/// `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000` (physical device → LAN)
const String kDefaultBaseUrl = "https://navig8r.onrender.com";

String resolveApiBaseUrl() {
  const fromEnv = String.fromEnvironment("API_BASE_URL");
  if (fromEnv.trim().isNotEmpty) return fromEnv.trim();
  return kDefaultBaseUrl;
}

const _storage = FlutterSecureStorage();

class Api {
  Api(this.baseUrl)
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {"content-type": "application/json"},
            connectTimeout: const Duration(seconds: 45),
            receiveTimeout: const Duration(seconds: 45),
          ),
        ) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await _storage.read(key: "access_token");
      if (token != null && token.isNotEmpty) {
        options.headers["authorization"] = "Bearer $token";
      }
      handler.next(options);
    }));
  }

  final String baseUrl;
  final Dio dio;

  Future<void> setToken(String token) => _storage.write(key: "access_token", value: token);
  Future<void> clearToken() => _storage.delete(key: "access_token");

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) => dio.get<T>(path, queryParameters: query);
  Future<Response<T>> post<T>(String path, {Object? data}) => dio.post<T>(path, data: data);
}

late Api api;

/// Resolves the API host from [baseUrl] using Dart's resolver (same path Dio uses).
Future<String> diagnoseApiDns(String baseUrl) async {
  Uri uri;
  try {
    uri = Uri.parse(baseUrl);
  } catch (e) {
    return "Invalid API base URL: $baseUrl ($e)";
  }
  final host = uri.host;
  if (host.isEmpty) return "Invalid API base URL (no host): $baseUrl";
  try {
    final ips = await InternetAddress.lookup(host);
    return "DNS ok for $host → ${ips.map((a) => a.address).join(", ")}";
  } on SocketException catch (e) {
    return "DNS failed from Flutter for $host: ${e.message}. "
        "Emulator Chrome can still work (it may use its own DNS). "
        "Try: Settings → Network → Private DNS → Off, cold-boot the AVD, "
        "or run with --dart-define=API_BASE_URL=http://10.0.2.2:3000 against a local API.";
  }
}

String formatApiError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.unknown) {
      final msg = e.message ?? "";
      if (msg.contains("Failed host lookup") || msg.contains("Network is unreachable")) {
        return "Cannot reach API at ${api.baseUrl}. Check device Wi‑Fi/mobile data, or run with "
            "--dart-define=API_BASE_URL=http://10.0.2.2:3000 for a local API on the emulator. ($msg)";
      }
    }
    return "HTTP ${status ?? "?"}: ${body ?? e.message ?? e.toString()}";
  }
  return e.toString();
}

String? lastRegisteredOrgId;

String digitsOnly(String input) => input.replaceAll(RegExp(r"\D"), "");

String? orgIdFromRegisterResponse(Map<String, dynamic>? data) {
  final org = data?["org"];
  if (org is Map<String, dynamic>) {
    final id = org["id"];
    if (id is String && id.trim().isNotEmpty) return id.trim();
  }
  return null;
}

String? firstCarrierOrgIdFromPilotMe(Map<String, dynamic>? data) {
  final orgs = data?["organizations"];
  if (orgs is! List<dynamic>) return null;
  for (final o in orgs) {
    if (o is Map<String, dynamic>) {
      final kind = o["kind"] as String?;
      final id = o["id"] as String?;
      if (id == null || id.isEmpty) continue;
      if (kind == "CARRIER_SOLO" || kind == "CARRIER_FLEET" || kind == "CARRIER_LEGACY") return id;
    }
  }
  if (orgs.isNotEmpty && orgs.first is Map<String, dynamic>) {
    final id = (orgs.first as Map<String, dynamic>)["id"] as String?;
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

String? carrierOrgDisplayNameFromPilotMe(Map<String, dynamic>? data, String orgId) {
  final orgs = data?["organizations"];
  if (orgs is! List<dynamic>) return null;
  for (final o in orgs) {
    if (o is Map<String, dynamic> && o["id"] == orgId) {
      return o["displayName"] as String?;
    }
  }
  return null;
}

String formatInrFromPaise(num paise) {
  final rupees = paise / 100;
  if (rupees == rupees.roundToDouble()) return "₹${rupees.toStringAsFixed(0)}";
  return "₹${rupees.toStringAsFixed(2)}";
}

String formatIstIsoFromUtc(DateTime utc) {
  final ist = utc.add(const Duration(hours: 5, minutes: 30));
  final y = ist.year;
  final m = ist.month.toString().padLeft(2, "0");
  final d = ist.day.toString().padLeft(2, "0");
  final h = ist.hour.toString().padLeft(2, "0");
  final min = ist.minute.toString().padLeft(2, "0");
  final s = ist.second.toString().padLeft(2, "0");
  return "$y-$m-${d}T$h:$min:$s+05:30";
}

void defaultAnchorTripWindow(TextEditingController w1, TextEditingController w2) {
  final utc = DateTime.now().toUtc();
  final istNow = utc.add(const Duration(hours: 5, minutes: 30));
  final y = istNow.year;
  final m = istNow.month;
  final d = istNow.day;
  final startUtc = DateTime.utc(y, m, d).subtract(const Duration(hours: 5, minutes: 30));
  final endUtc = DateTime.utc(y, m, d + 2).subtract(const Duration(hours: 5, minutes: 30)).subtract(const Duration(seconds: 1));
  w1.text = formatIstIsoFromUtc(startUtc);
  w2.text = formatIstIsoFromUtc(endUtc);
}

String shipmentStatusLabel(String status) {
  switch (status) {
    case "PENDING_CARRIER_ACCEPT":
      return "Awaiting carrier acceptance";
    case "BOOKED":
      return "Accepted";
    case "PENDING_RELEASE":
      return "Awaiting ops release";
    case "DELIVERED":
      return "Delivered";
    default:
      return status;
  }
}

String tripStatusLabel(String status) {
  switch (status) {
    case "OPEN":
      return "Open";
    case "FULL":
      return "Full";
    case "IN_PROGRESS":
      return "In progress";
    case "COMPLETED":
      return "Done";
    default:
      return status;
  }
}

String vehicleClassLabel(String? vehicleClass) {
  switch (vehicleClass) {
    case "SMALL":
      return "Small truck";
    case "MEDIUM":
      return "Medium truck";
    case "LARGE":
      return "Large truck";
    default:
      return vehicleClass ?? "—";
  }
}

String carrierMemberRoleLabel(String role) {
  switch (role) {
    case "OWNER_DRIVER":
      return "Owner-driver";
    case "OWNER":
      return "Owner";
    case "DISPATCHER":
      return "Dispatcher";
    case "DRIVER":
      return "Driver";
    default:
      return role.isEmpty ? "—" : role;
  }
}

String customerMemberRoleLabel(String role) {
  switch (role) {
    case "CUSTOMER_ADMIN":
      return "Admin";
    case "CUSTOMER_MEMBER":
      return "Member";
    default:
      return role.isEmpty ? "—" : role;
  }
}

String paymentStatusLabel(String status) {
  switch (status) {
    case "CREATED":
      return "Awaiting checkout";
    case "AUTHORIZED":
      return "Payment authorized";
    case "CAPTURED":
      return "Payment captured";
    case "FAILED":
      return "Payment failed";
    case "REFUNDED":
      return "Refunded";
    default:
      return status;
  }
}

/// Short human range from ISO window strings, e.g. "12–14 Jun".
String formatTripWindowRange(String? windowStart, String? windowEnd) {
  String dayMonth(String? iso) {
    if (iso == null || iso.isEmpty) return "—";
    final t = iso.indexOf("T");
    final date = t > 0 ? iso.substring(0, t) : iso;
    final parts = date.split("-");
    if (parts.length < 3) return date;
    const months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    if (m < 1 || m > 12 || d < 1) return date;
    return "$d ${months[m]}";
  }

  final a = dayMonth(windowStart);
  final b = dayMonth(windowEnd);
  if (a == "—" && b == "—") return "Window not set";
  if (a == b) return a;
  return "$a – $b";
}

class ShipmentTimelineStep {
  const ShipmentTimelineStep({
    required this.label,
    required this.subtitle,
    required this.complete,
    required this.current,
  });

  final String label;
  final String subtitle;
  final bool complete;
  final bool current;
}

List<ShipmentTimelineStep> shipmentTimelineSteps({
  required String shipmentStatus,
  String? tripStatus,
  bool isLive = false,
}) {
  final accepted = shipmentStatus == "BOOKED" ||
      shipmentStatus == "PENDING_RELEASE" ||
      shipmentStatus == "DELIVERED";
  final started = tripStatus == "IN_PROGRESS" || tripStatus == "COMPLETED";
  final delivered = shipmentStatus == "DELIVERED";
  final pendingRelease = shipmentStatus == "PENDING_RELEASE";

  return [
    ShipmentTimelineStep(
      label: "Booking placed",
      subtitle: "Your request was submitted",
      complete: true,
      current: false,
    ),
    ShipmentTimelineStep(
      label: "Carrier accepted",
      subtitle: "Carrier confirmed they will carry your load",
      complete: accepted || pendingRelease || delivered,
      current: shipmentStatus == "PENDING_CARRIER_ACCEPT",
    ),
    ShipmentTimelineStep(
      label: "Load started",
      subtitle: "Carrier marked the trip as started",
      complete: started || delivered || pendingRelease,
      current: shipmentStatus == "BOOKED" && !started && !delivered && !pendingRelease,
    ),
    ShipmentTimelineStep(
      label: "In transit",
      subtitle: isLive ? "Live tracking active" : "Tracking when the load is on the road",
      complete: delivered || pendingRelease,
      current: started && !delivered && !pendingRelease,
    ),
    ShipmentTimelineStep(
      label: delivered ? "Delivered" : pendingRelease ? "Delivered (processing)" : "Delivered",
      subtitle: delivered
          ? "Shipment complete"
          : pendingRelease
              ? "Proof of delivery submitted"
              : "Confirmation after drop-off",
      complete: delivered,
      current: pendingRelease,
    ),
  ];
}
