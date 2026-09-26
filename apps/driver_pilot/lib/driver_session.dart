import "authorization_session.dart";
import "pilot_api.dart";

/// In-memory carrier session refreshed from `/v1/pilot/me`.
abstract final class DriverSession {
  static int _epoch = 0;
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
    // The auth session stays. clear() wipes it, the app listener on that session
    // calls back in here, and the two recurse until the stack overflows. The
    // router also treats the wipe as a sign-out and sends a signed-in carrier
    // to the phone screen. A refresh only needs to drop this cache so a late
    // response cannot refill it after sign-out.
    clearCarrierCache();
    final epoch = _epoch;
    await AuthorizationSession.refresh();
    if (epoch != _epoch) return false;
    if (!hasCarrierOrg ||
        !AuthorizationSession.can("organization.profile.read")) {
      return false;
    }
    final scope = AuthorizationSession.scopeKey;
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      if (epoch != _epoch || scope != AuthorizationSession.scopeKey)
        return false;
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

  /// Drops the in-process carrier cache. Does not touch the auth session, so it
  /// is safe to call from the auth session's own listener.
  static void clearCarrierCache() {
    _epoch++;
    lastRegisteredOrgId = null;
    vehicleId = null;
    vehicleRegistrationNumber = null;
    vehicleClass = null;
    vehicleCapacityKg = null;
  }

  static void clear() {
    clearCarrierCache();
    AuthorizationSession.clear();
  }
}
