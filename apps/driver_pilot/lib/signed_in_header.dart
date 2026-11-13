import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "authorization_session.dart";
import "notification_bell.dart";
import "pilot_api.dart";
import "ui/format.dart";
import "ui/nv_account_sheet.dart";
import "ui/nv_header.dart";

/// The header on every signed-in screen, filled from the signed-in person and company. Its
/// account menu switches company and signs out through the same session calls the old
/// drop-down and sign-out icon used. "Add a company" is left out: no flow adds one today.
NvHeader signedInHeader(BuildContext context,
    {String? backLabel, VoidCallback? onBack, Widget? navigation}) {
  final user = AuthorizationSession.user ?? const <String, dynamic>{};
  final phone = formatPhone(user["phone"]?.toString() ?? "");
  final router = GoRouter.maybeOf(context);
  return NvHeader(
    company:
        AuthorizationSession.organization?["displayName"]?.toString() ?? "",
    person: user["fullName"]?.toString() ?? phone,
    role: _roleWord(),
    phone: phone,
    companies: [
      for (final organization in AuthorizationSession.organizations)
        NvCompany(
            id: organization["id"].toString(),
            name: organization["displayName"]?.toString() ?? "",
            role: _roleAtCompany(organization)),
    ],
    currentCompanyId: AuthorizationSession.organizationId,
    onSwitch: _switchCompany,
    onSignOut: () => _signOut(router, {
      Navigator.maybeOf(context),
      router?.routerDelegate.navigatorKey.currentState
    }),
    backLabel: backLabel,
    onBack: onBack,
    navigation: navigation,
    // Every signed-in screen, detail screens included, so a change by the other party shows anywhere.
    trailing: AuthorizationSession.can("notification.read")
        ? const NotificationBell()
        : null,
  );
}

/// "Shipper", or the carrier role: "Owner", "Owner-driver", "Dispatcher" or "Driver".
String _roleWord() {
  if (AuthorizationSession.hasRole("SHIPPER")) return "Shipper";
  final subrole = AuthorizationSession.principal?["subrole"]?.toString() ?? "";
  return subrole.isEmpty ? "Carrier" : carrierMemberRoleLabel(subrole);
}

// The server sends the role for the chosen company only, so the other companies say which
// side they are on and nothing more.
String? _roleAtCompany(Map<String, dynamic> organization) {
  final kind = organization["kind"]?.toString() ?? "";
  if (kind == "CUSTOMER") return "Shipper";
  if (!kind.startsWith("CARRIER_")) return null;
  final role = _roleWord();
  final chosen = organization["id"] == AuthorizationSession.organizationId;
  return chosen && role != "Carrier" ? "Carrier · $role" : "Carrier";
}

Future<String?> _switchCompany(String companyId) async {
  await AuthorizationSession.selectOrganization(companyId);
  return AuthorizationSession.error;
}

// The router is taken before signing out: signing out rebuilds the screens under a new key,
// so the header's own context is gone by the time the start screen should open.
// Screens pushed over the router's pages, as Updates is, keep their place under the new key; they
// are closed so the sign-in screen shows nothing from the old account.
Future<void> _signOut(
    GoRouter? router, Set<NavigatorState?> navigators) async {
  await AuthorizationSession.signOut();
  for (final navigator in navigators) {
    if (navigator != null && navigator.mounted) {
      navigator.popUntil((route) => route.settings is Page);
    }
  }
  router?.go("/");
}
