import "pilot_api.dart";

/// In-memory customer session from `/v1/auth/me` + `/v1/pilot/me`.
abstract final class CustomerSession {
  static String? userFullName;
  static String? userPhone;
  static String? customerOrgId;
  static String? customerOrgName;
  static String? customerRole;

  static bool get isSignedIn => userPhone != null && userPhone!.isNotEmpty;
  static bool get hasCustomerOrg => customerOrgId != null && customerOrgId!.isNotEmpty;
  static bool get isOrgAdmin => customerRole == "CUSTOMER_ADMIN";

  static Future<bool> refresh() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/auth/me");
      final user = r.data?["user"];
      if (user is Map<String, dynamic>) {
        userFullName = user["fullName"] as String?;
        userPhone = user["phone"] as String?;
      }
      customerOrgId = null;
      customerOrgName = null;
      customerRole = null;
      try {
        final me = await api.get<Map<String, dynamic>>("/v1/pilot/me");
        final orgs = me.data?["organizations"];
        final memberships = me.data?["memberships"];
        if (orgs is List && memberships is List) {
          final customerOrgs = <Map<String, dynamic>>[];
          for (final o in orgs) {
            if (o is Map<String, dynamic> && o["kind"] == "CUSTOMER") {
              customerOrgs.add(o);
            }
          }
          customerOrgs.sort((a, b) => (a["id"]?.toString() ?? "").compareTo(b["id"]?.toString() ?? ""));
          if (customerOrgs.isNotEmpty) {
            final primary = customerOrgs.first;
            customerOrgId = primary["id"]?.toString();
            customerOrgName = primary["displayName"] as String?;
            final orgId = customerOrgId;
            if (orgId != null) {
              for (final m in memberships) {
                if (m is Map<String, dynamic> && m["orgId"]?.toString() == orgId) {
                  customerRole = m["role"]?.toString();
                  break;
                }
              }
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
    customerOrgId = null;
    customerOrgName = null;
    customerRole = null;
  }
}
