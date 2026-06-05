import "dart:io";

import "package:dio/dio.dart";
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
