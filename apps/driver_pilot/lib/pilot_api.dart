import "package:dio/dio.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";

/// Android emulator → host machine API: `http://10.0.2.2:3000`
const String kDefaultBaseUrl = "https://navig8r.onrender.com";

const _storage = FlutterSecureStorage();

class Api {
  Api(this.baseUrl) : dio = Dio(BaseOptions(baseUrl: baseUrl, headers: {"content-type": "application/json"})) {
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

String formatApiError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
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
