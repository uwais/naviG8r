import "authorization_session.dart";
import "pilot_api.dart";

/// In-memory carrier session refreshed from `/v1/pilot/me`.
abstract final class DriverSession {
  static String? get carrierOrgId =>
      hasCarrierOrg ? AuthorizationSession.organizationId : null;
  static String? get carrierOrgName => hasCarrierOrg
      ? (AuthorizationSession.organization?["displayName"] as String?)
      : null;
  static String? get carrierRole => hasCarrierOrg
      ? (AuthorizationSession.principal?["subrole"] as String?)
      : null;
  static String? get userFullName =>
      AuthorizationSession.user?["fullName"] as String?;
  static String? get userPhone =>
      AuthorizationSession.user?["phone"] as String?;
  static String? get kycStatus => hasCarrierOrg
      ? (AuthorizationSession.organization?["kycStatus"] as String?)
      : null;
  static String? vehicleId;
  static String? vehicleRegistrationNumber;
  static String? vehicleClass;
  static double? vehicleCapacityKg;
  static bool get hasCarrierOrg => AuthorizationSession.hasRole("CARRIER");
  static bool get canInviteDrivers =>
      hasCarrierOrg && AuthorizationSession.can("organization.member.invite");
  static bool get canSetUpPayouts =>
      hasCarrierOrg && AuthorizationSession.can("bank_account.create_token");
  static bool get complianceApproved => kycStatus == "APPROVED";

  static Future<bool> refresh() async {
    clear();
    await AuthorizationSession.refresh();
    if (!hasCarrierOrg ||
        !AuthorizationSession.can("organization.profile.read")) {
      return false;
    }
    final scope = AuthorizationSession.scopeKey;
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      if (scope != AuthorizationSession.scopeKey) return false;
      final profile = r.data?["driverProfile"];
      final vehicles = r.data?["vehicles"];
      if (profile is Map<String, dynamic> && vehicles is List) {
        final primaryId = profile["primaryVehicleId"]?.toString();
        if (primaryId != null && primaryId.isNotEmpty) {
          for (final v in vehicles) {
            if (v is Map<String, dynamic> && v["id"]?.toString() == primaryId) {
              vehicleId = primaryId;
              vehicleRegistrationNumber = v["registrationNumber"]?.toString();
              vehicleClass = v["vehicleClass"]?.toString();
              final cap = v["capacityKg"];
              if (cap is num) vehicleCapacityKg = cap.toDouble();
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
    vehicleId = null;
    vehicleRegistrationNumber = null;
    vehicleClass = null;
    vehicleCapacityKg = null;
  }
}
