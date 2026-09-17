import "package:flutter/foundation.dart";
import "authorization_session.dart";

/// Shipper projection of the shared, server-authorized session.
abstract final class CustomerSession {
  static Listenable get listenable => AuthorizationSession.revision;
  static String? get userFullName =>
      AuthorizationSession.user?["fullName"] as String?;
  static String? get userPhone =>
      AuthorizationSession.user?["phone"] as String?;
  static String? get customerOrgId =>
      hasCustomerOrg ? AuthorizationSession.organizationId : null;
  static String? get customerOrgName => hasCustomerOrg
      ? (AuthorizationSession.organization?["displayName"] as String?)
      : null;
  static String? get customerRole => hasCustomerOrg
      ? (AuthorizationSession.principal?["subrole"] as String?)
      : null;
  static bool get isSignedIn => AuthorizationSession.signedIn;
  static bool get hasCustomerOrg => AuthorizationSession.hasRole("SHIPPER");
  static bool get isOrgAdmin =>
      hasCustomerOrg && AuthorizationSession.can("organization.member.invite");
  static bool get canManageIntegrations =>
      hasCustomerOrg && AuthorizationSession.can("integration.manage");
  static Future<bool> refresh() async =>
      skipRefreshInTests ? isSignedIn : await AuthorizationSession.refresh();
  static void clear() => AuthorizationSession.clear();
  static Future<void> signOut() => AuthorizationSession.signOut();

  @visibleForTesting
  static bool skipRefreshInTests = false;

  @visibleForTesting
  static void applyForTest(
      {String? userFullName,
      String? userPhone,
      String? customerOrgId,
      String? customerOrgName,
      String? customerRole}) {
    AuthorizationSession.user = {
      "id": "test-user",
      "fullName": userFullName,
      "phone": userPhone
    };
    AuthorizationSession.organizations = [
      {"id": customerOrgId, "displayName": customerOrgName, "kind": "CUSTOMER"}
    ];
    AuthorizationSession.principal = {
      "organizationId": customerOrgId,
      "subrole": customerRole,
      "roles": ["SHIPPER"],
      "permissions": [
        "load.read",
        "load.create",
        "pod.accept",
        if (customerRole == "CUSTOMER_ADMIN") ...[
          "organization.member.invite",
          "integration.manage"
        ]
      ],
    };
    AuthorizationSession.initialized = true;
    AuthorizationSession.revision.value++;
  }
}
