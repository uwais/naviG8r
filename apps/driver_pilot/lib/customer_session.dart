import "pilot_api.dart";

/// In-memory customer session from `/v1/auth/me` (and org name when available).
abstract final class CustomerSession {
  static String? userFullName;
  static String? userPhone;
  static String? customerOrgName;

  static bool get isSignedIn => userPhone != null && userPhone!.isNotEmpty;

  static Future<bool> refresh() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/auth/me");
      final user = r.data?["user"];
      if (user is Map<String, dynamic>) {
        userFullName = user["fullName"] as String?;
        userPhone = user["phone"] as String?;
      }
      customerOrgName = null;
      try {
        final me = await api.get<Map<String, dynamic>>("/v1/pilot/me");
        final orgs = me.data?["organizations"];
        if (orgs is List) {
          for (final o in orgs) {
            if (o is Map<String, dynamic> && o["kind"] == "CUSTOMER") {
              customerOrgName = o["displayName"] as String?;
              break;
            }
          }
        }
      } catch (_) {}
      return userPhone != null;
    } catch (_) {
      return false;
    }
  }

  static void clear() {
    userFullName = null;
    userPhone = null;
    customerOrgName = null;
  }
}
