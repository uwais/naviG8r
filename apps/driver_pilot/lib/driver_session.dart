import "pilot_api.dart";

/// In-memory carrier session refreshed from `/v1/pilot/me`.
abstract final class DriverSession {
  static String? carrierOrgId;
  static String? carrierOrgName;
  static String? carrierRole;
  static String? userFullName;
  static String? userPhone;
  static String? kycStatus;

  static bool get hasCarrierOrg => carrierOrgId != null && carrierOrgId!.isNotEmpty;

  static bool get canInviteDrivers {
    final r = carrierRole;
    return r == "OWNER_DRIVER" || r == "OWNER" || r == "DISPATCHER";
  }

  static bool get payoutSetupComplete => kycStatus == "SUBMITTED" || kycStatus == "APPROVED";

  static Future<bool> refresh() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      final user = r.data?["user"];
      if (user is Map<String, dynamic>) {
        userFullName = user["fullName"] as String?;
        userPhone = user["phone"] as String?;
      }
      carrierRole = null;
      final oid = firstCarrierOrgIdFromPilotMe(r.data);
      if (oid != null) {
        carrierOrgId = oid;
        lastRegisteredOrgId = oid;
        carrierOrgName = carrierOrgDisplayNameFromPilotMe(r.data, oid);
        final orgs = r.data?["organizations"];
        final memberships = r.data?["memberships"];
        if (orgs is List) {
          for (final o in orgs) {
            if (o is Map<String, dynamic> && o["id"] == oid) {
              kycStatus = o["kycStatus"] as String?;
              break;
            }
          }
        }
        if (memberships is List) {
          for (final m in memberships) {
            if (m is Map<String, dynamic> && m["orgId"]?.toString() == oid) {
              carrierRole = m["role"]?.toString();
              break;
            }
          }
        }
      } else {
        carrierOrgId = null;
        carrierOrgName = null;
        kycStatus = null;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static void clear() {
    carrierOrgId = null;
    carrierOrgName = null;
    carrierRole = null;
    userFullName = null;
    userPhone = null;
    kycStatus = null;
  }
}
