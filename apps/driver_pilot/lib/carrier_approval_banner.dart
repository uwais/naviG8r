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

/// What a rejected carrier's owner reads for each reason ops may share; null for any other code.
String? rejectionReasonInWords(String? code) => switch (code) {
      "DOCUMENTS_MISSING" => "NaviG8r needs documents from this carrier.",
      "BANK_DETAILS_MISMATCH" =>
        "The name entered as the bank account holder doesn't match the carrier's name.",
      "DUPLICATE_ACCOUNT" => "NaviG8r already has an account for this carrier.",
      "NOT_A_CARRIER" => "NaviG8r decided this is not a carrier business.",
      _ => null,
    };

/// The rejected banner: what ops decided and, for the owner, why and only a next step that can work.
/// Everyone else is told to ask the owner, since the reason is about the carrier's business.
(String, String?) _rejectedMessage({required bool owner}) {
  final opsDecisionSentence = DriverSession.approvalTakenBack
      ? "NaviG8r operations took back this carrier's approval."
      : "NaviG8r operations did not approve this carrier.";
  const blockedSentence =
      "While this carrier is not approved, you can't accept shipments or start trips.";
  if (!owner) {
    return (
      [opsDecisionSentence, "Ask the carrier owner for details.", blockedSentence]
          .join(" "),
      null,
    );
  }
  final code = DriverSession.rejectionReasonCode;
  final reason = rejectionReasonInWords(code);
  final (nextStep, action) = switch (code) {
    "DOCUMENTS_MISSING" || "NOT_A_CARRIER" => (
        "You can't send documents or contact NaviG8r from the app.",
        null
      ),
    "DUPLICATE_ACCOUNT" => (
        "If you belong to that account, choose it in the organization menu at the top of the screen.",
        null
      ),
    // The bank reason, or none the app knows: new bank details are the one step that can help.
    _ => (
        "You can submit your bank details for another review.",
        "Submit bank details"
      ),
  };
  return (
    [opsDecisionSentence, if (reason != null) reason, nextStep, blockedSentence]
        .join(" "),
    action,
  );
}

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
      "REJECTED" => _rejectedMessage(owner: owner),
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
