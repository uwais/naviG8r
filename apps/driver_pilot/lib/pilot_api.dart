import "package:dio/dio.dart";

export "pilot_api_dns.dart";
import 'package:flutter/foundation.dart';
import "package:flutter_secure_storage/flutter_secure_storage.dart";

/// Production API. Override at run/build time:
/// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` (Android emulator → host)
/// `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000` (physical device → LAN)
const String kDefaultBaseUrl = "https://navig8r.onrender.com";

String normalizeApiBaseUrl(String raw) {
  var value = raw.trim();
  if (value.startsWith("http://http://")) {
    value = value.substring("http://".length);
  } else if (value.startsWith("https://https://")) {
    value = value.substring("https://".length);
  }
  if (value.isNotEmpty &&
      !value.startsWith("http://") &&
      !value.startsWith("https://") &&
      !value.startsWith("/")) {
    value = "http://$value";
  }
  return value;
}

String resolveApiBaseUrl() {
  const fromEnv = String.fromEnvironment("API_BASE_URL");
  if (fromEnv.trim().isNotEmpty) return normalizeApiBaseUrl(fromEnv);

  if (kIsWeb) {
    return '/api';
  }

  return kDefaultBaseUrl;
}

const _storage = FlutterSecureStorage();

Future<void> clearCommunicationDrafts() async {
  try {
    final values = await _storage.readAll();
    for (final key
        in values.keys.where((key) => key.startsWith('conversation_draft_'))) {
      await _storage.delete(key: key);
    }
  } catch (_) {
    // Cleanup is best effort: drafts are scoped to the user and active
    // organization, so an unavailable secure-storage channel cannot expose
    // one account's draft to another account.
  }
}

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
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      final version = scopeVersion;
      final identityVersionAtRequest = identityVersion;
      final organizationIndependent = _isPushLifecycleRequest(options.path);
      options.extra["scopeVersion"] = version;
      options.extra["identityVersion"] = identityVersionAtRequest;
      options.extra["organizationIndependent"] = organizationIndependent;
      await _tokenWrite;
      final token = await _storage.read(key: "access_token");
      if (organizationIndependent
          ? identityVersionAtRequest != identityVersion
          : version != scopeVersion) {
        handler.reject(DioException(
            requestOptions: options, type: DioExceptionType.cancel));
        return;
      }
      if (activeOrganizationId != null) {
        options.headers["x-organization-id"] = activeOrganizationId;
      }
      if (token != null && token.isNotEmpty) {
        options.headers["authorization"] = "Bearer $token";
      }
      handler.next(options);
    }, onResponse: (response, handler) {
      final extra = response.requestOptions.extra;
      final stale = extra["organizationIndependent"] == true
          ? extra["identityVersion"] != identityVersion
          : extra["scopeVersion"] != scopeVersion;
      if (stale) {
        handler.reject(DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel));
        return;
      }
      handler.next(response);
    }, onError: (error, handler) {
      final extra = error.requestOptions.extra;
      final currentScope = extra["organizationIndependent"] == true
          ? extra["identityVersion"] == identityVersion
          : extra["scopeVersion"] == scopeVersion;
      if (currentScope &&
          error.requestOptions.path != "/v1/auth/me" &&
          [401, 403].contains(error.response?.statusCode)) {
        onAuthorizationFailure?.call();
      }
      handler.next(error);
    }));
  }

  final String baseUrl;
  final Dio dio;

  String? activeOrganizationId;
  int scopeVersion = 0;
  int identityVersion = 0;
  Future<void>? _tokenWrite;
  VoidCallback? onIdentityChanged;
  Future<void> Function()? onBeforeIdentityChange;
  VoidCallback? onAuthorizationFailure;

  bool _isPushLifecycleRequest(String path) =>
      path == '/v1/me/push-devices' || path.startsWith('/v1/me/push-devices/');

  void selectOrganization(String? id) {
    activeOrganizationId = id;
    scopeVersion++;
    lastRegisteredOrgId = null;
  }

  Future<void> setToken(String token) async {
    await onBeforeIdentityChange?.call();
    identityVersion++;
    selectOrganization(null);
    _tokenWrite = _storage.write(key: "access_token", value: token);
    onIdentityChanged?.call();
    try {
      await _tokenWrite;
    } finally {
      _tokenWrite = null;
    }
  }

  Future<void> clearToken() async {
    await onBeforeIdentityChange?.call();
    identityVersion++;
    selectOrganization(null);
    _tokenWrite = _storage.delete(key: "access_token");
    onIdentityChanged?.call();
    try {
      await _tokenWrite;
    } finally {
      _tokenWrite = null;
    }
  }

  Future<bool> hasBearerToken() async {
    await _tokenWrite;
    final token = await _storage.read(key: "access_token");
    return token != null && token.isNotEmpty;
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) =>
      dio.get<T>(path, queryParameters: query);
  Future<Response<T>> post<T>(String path, {Object? data}) =>
      dio.post<T>(path, data: data);
  Future<Response<T>> patch<T>(String path, {Object? data}) =>
      dio.patch<T>(path, data: data);
  Future<Response<T>> put<T>(String path, {Object? data}) =>
      dio.put<T>(path, data: data);
  Future<Response<T>> delete<T>(String path, {Object? data}) =>
      dio.delete<T>(path, data: data);
}

late Api api;

String formatApiError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final code = body is Map ? body["error"] : null;
    if (code == "otp_rate_limited") {
      final retry = body["retryAfterMs"];
      final seconds = retry is num ? (retry / 1000).ceil() : 30;
      final minutes = (seconds / 60).ceil();
      final shownSeconds = seconds > 0 ? seconds : 1;
      final wait = seconds < 60
          ? "$shownSeconds ${shownSeconds == 1 ? "second" : "seconds"}"
          : "$minutes ${minutes == 1 ? "minute" : "minutes"}";
      return "Too many code requests. Please wait $wait and try again.";
    }
    // The server writes these errors' detail for the carrier: which bank field is wrong and how, why
    // the truck cannot change, what a transporter ID looks like, or that a chosen truck or driver is not theirs.
    final detail = body is Map ? body["detail"] : null;
    if (const [
          "invalid_payout_profile",
          "truck_on_unfinished_trip",
          "invalid_vehicleRegistrationNumber",
          "invalid_transporter_id",
          "invalid_trip_assignment"
        ].contains(code) &&
        detail is String &&
        detail.isNotEmpty) {
      return detail;
    }
    const messages = {
      "carrier_compliance_required":
          "NaviG8r must approve your company before you can accept bookings or start trips.",
      "payment_hold_active":
          "Payment is on hold until the shipper accepts delivery or the 48-hour hold ends.",
      "active_organization_required": "Choose a company to continue.",
      "membership_inactive":
          "You no longer have access to this company. Choose another company.",
      "forbidden":
          "You are not allowed to do this in this company.",
      "not_found": "This is not available in the company you chose.",
      "unauthorized": "You were signed out. Please sign in again.",
      // A 409 from every register screen; without it the screen blamed the connection.
      "phone_already_registered":
          "This number already has an account. Sign in instead.",
      // An invite's refusal. Its other one, user_not_found, is worded on the invite screens, which can
      // say "invite"; sign-in words it its own way.
      "membership_already_exists": "This number is already in your company.",
      "otp_expired": "This code has expired. Send a new code.",
      "otp_incorrect":
          "That code is not right. Check the SMS and type it again, or send a new code.",
      "otp_challenge_invalid":
          "This code request is no longer valid. Request a new code.",
      "otp_challenge_not_found":
          "This code request is no longer valid. Request a new code.",
      "otp_challenge_mismatch":
          "This code request is no longer valid. Request a new code.",
      "insufficient_capacity":
          "This trip does not have enough capacity for that weight. Enter less weight, or choose another trip.",
      "anchor_trip_not_open":
          "This trip is no longer taking bookings. Choose another trip.",
      "address_too_long":
          "The pickup or drop address is over 500 characters. Shorten it.",
      "checkout_not_completed_for_accept":
          "The shipper has not finished paying for this booking yet. You can accept it once they do.",
      // A driver can meet this one, so it says nothing about payment.
      "checkout_not_completed_for_pod":
          "This booking is not ready for delivery yet. Ask your office.",
    };
    if (messages.containsKey(code)) return messages[code]!;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      final msg = e.message ?? "";
      if (msg.contains("XMLHttpRequest onError") ||
          msg.contains("connection errored")) {
        return "Cannot reach API at ${api.baseUrl} from the browser. "
            "This is usually CORS — redeploy the API with CORS enabled, or run a local API with "
            "--dart-define=API_BASE_URL=http://localhost:3000.";
      }
      if (msg.contains("Failed host lookup") ||
          msg.contains("Network is unreachable")) {
        return "Cannot reach API at ${api.baseUrl}. Check device Wi‑Fi/mobile data, or run with "
            "--dart-define=API_BASE_URL=http://10.0.2.2:3000 for a local API on the emulator. ($msg)";
      }
    }
    return "HTTP ${status ?? "?"}: ${body ?? e.message ?? e.toString()}";
  }
  return e.toString();
}

/// The request failed before any answer came back: a dropped connection, a timeout, no signal.
bool serverNeverAnswered(Object e) => e is DioException && e.response == null;

/// The server answered that this login cannot see the record, as it does when a trip is no longer a driver's.
bool serverAnsweredNotFound(Object e) =>
    e is DioException && e.response?.statusCode == 404;

/// The server writes a plain sentence for each e-way bill refusal; show it instead of "HTTP 400".
String ewayBillErrorSentence(Object e) {
  if (serverNeverAnswered(e)) {
    return "Could not save. Check your connection and try again.";
  }
  if (e is DioException) {
    final body = e.response?.data;
    final detail = body is Map ? body["detail"] : null;
    if (detail is String && detail.isNotEmpty) return detail;
  }
  // formatApiError can print a raw body, "HTTP n" or the server address; none of that helps here.
  return "Something went wrong. Please try again.";
}

/// The bank details field the server refused (accountHolderName, ifsc or accountNumber), so the form can box it.
String? refusedBankDetailsField(Object e) {
  if (e is! DioException) return null;
  final body = e.response?.data;
  if (body is! Map || body["error"] != "invalid_payout_profile") return null;
  final field = body["field"];
  return field is String ? field : null;
}

int? otpRetryAfterMs(Object e) {
  if (e is! DioException) return null;
  final body = e.response?.data;
  final value = body is Map ? body["retryAfterMs"] : null;
  return value is num && value > 0 ? value.ceil() : null;
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
      if (kind == "CARRIER_SOLO" ||
          kind == "CARRIER_FLEET" ||
          kind == "CARRIER_LEGACY") return id;
    }
  }
  if (orgs.isNotEmpty && orgs.first is Map<String, dynamic>) {
    final id = (orgs.first as Map<String, dynamic>)["id"] as String?;
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

String? carrierOrgDisplayNameFromPilotMe(
    Map<String, dynamic>? data, String orgId) {
  final orgs = data?["organizations"];
  if (orgs is! List<dynamic>) return null;
  for (final o in orgs) {
    if (o is Map<String, dynamic> && o["id"] == orgId) {
      return o["displayName"] as String?;
    }
  }
  return null;
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

String tripStatusLabel(String status) {
  switch (status) {
    case "OPEN":
      return "Open";
    case "FULL":
      return "Full";
    case "IN_PROGRESS":
      return "On the way";
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
