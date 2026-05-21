import "pilot_api.dart";

/// In-memory carrier session refreshed from `/v1/pilot/me`.
abstract final class DriverSession {
  static String? carrierOrgId;
  static String? carrierOrgName;
  static String? userFullName;
  static String? userPhone;
  static String? kycStatus;

  static bool get hasCarrierOrg => carrierOrgId != null && carrierOrgId!.isNotEmpty;

  static bool get payoutSetupComplete => kycStatus == "SUBMITTED" || kycStatus == "APPROVED";

  static Future<bool> refresh() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      final user = r.data?["user"];
      if (user is Map<String, dynamic>) {
        userFullName = user["fullName"] as String?;
        userPhone = user["phone"] as String?;
      }
      final oid = firstCarrierOrgIdFromPilotMe(r.data);
      if (oid != null) {
        carrierOrgId = oid;
        lastRegisteredOrgId = oid;
        carrierOrgName = carrierOrgDisplayNameFromPilotMe(r.data, oid);
        final orgs = r.data?["organizations"];
        if (orgs is List) {
          for (final o in orgs) {
            if (o is Map<String, dynamic> && o["id"] == oid) {
              kycStatus = o["kycStatus"] as String?;
              break;
            }
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static void clear() {
    carrierOrgId = null;
    carrierOrgName = null;
    userFullName = null;
    userPhone = null;
    kycStatus = null;
  }
}
