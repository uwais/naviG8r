import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "authorization_session.dart";
import "driver_session.dart";

/// The carrier's approval status in plain words, for screens that show it.
String approvalStatusInWords(String? kycStatus) => switch (kycStatus) {
      "APPROVED" => "Approved",
      "SUBMITTED" => "Waiting for NaviG8r review",
      "REJECTED" => "Not approved",
      _ => "Bank details not added yet",
    };

/// Tells an unapproved carrier why loads are blocked and what to do next.
/// Redraws when the session refreshes, so a status change shows without leaving the screen.
class CarrierApprovalBanner extends StatelessWidget {
  const CarrierApprovalBanner({super.key, required this.currentPath});

  /// The shell's current path: no button on the bank form itself, and Home opens it differently.
  final String currentPath;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AuthorizationSession.revision,
        builder: (context, _) => _banner(context),
      );

  Widget _banner(BuildContext context) {
    if (!DriverSession.hasCarrierOrg || DriverSession.complianceApproved) {
      return const SizedBox.shrink();
    }
    final owner = DriverSession.canSetUpPayouts;
    final (message, action) = switch (DriverSession.kycStatus) {
      "SUBMITTED" => (
          "This carrier is waiting for NaviG8r operations to review it. Until it is approved, you can't accept shipments or start trips.",
          null
        ),
      "REJECTED" => owner
          ? (
              "NaviG8r operations did not approve this carrier. You can submit your bank details again for another review. Until this carrier is approved, you can't accept shipments or start trips.",
              "Submit bank details again"
            )
          : (
              "NaviG8r operations did not approve this carrier. Ask the carrier owner to submit bank details again for another review. Until this carrier is approved, you can't accept shipments or start trips.",
              null
            ),
      _ => owner
          ? (
              "Add your bank details so NaviG8r operations can review this carrier. Until it is approved, you can't accept shipments or start trips.",
              "Add bank details"
            )
          : (
              "This carrier is not approved yet. Ask the carrier owner to add bank details. Until then, you can't accept shipments or start trips.",
              null
            ),
    };
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          if (action != null && !currentPath.startsWith("/driver/payout-setup"))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              // From Home, go not push: after a push the router's sign-in check still sees public Home,
              // so the form would survive sign-out. Elsewhere push, so phone Back returns and a live trip keeps running.
              child: FilledButton(
                onPressed: () => currentPath == "/driver"
                    ? context.go("/driver/payout-setup")
                    : context.push("/driver/payout-setup"),
                child: Text(action),
              ),
            ),
        ],
      ),
    );
  }
}
