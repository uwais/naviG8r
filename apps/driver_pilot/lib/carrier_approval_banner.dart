import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "authorization_session.dart";
import "driver_session.dart";

/// The carrier's approval status in plain words, for screens that show it.
String approvalStatusInWords(String? kycStatus) => switch (kycStatus) {
      "APPROVED" => "Approved",
      "SUBMITTED" => "Waiting for NaviG8r to check",
      "REJECTED" => "Not approved",
      _ => "Bank details not added yet",
    };

/// What a rejected carrier's owner reads for each reason ops may share; null for any other code.
String? rejectionReasonInWords(String? code) => switch (code) {
      "DOCUMENTS_MISSING" => "NaviG8r needs documents from your company.",
      "BANK_DETAILS_MISMATCH" =>
        "The bank account holder's name does not match your company name.",
      "DUPLICATE_ACCOUNT" => "NaviG8r already has an account for your company.",
      "NOT_A_CARRIER" => "NaviG8r decided this is not a carrier business.",
      _ => null,
    };

/// The rejected banner: what ops decided and, for the owner, why and only a next step that can work.
/// Everyone else is told to ask the owner, since the reason is about the carrier's business.
(String, String?) _rejectedMessage({required bool owner}) {
  final opsDecisionSentence = DriverSession.approvalTakenBack
      ? "NaviG8r took back your company's approval."
      : "NaviG8r did not approve your company.";
  const blockedSentence =
      "Until your company is approved, you cannot accept bookings or start trips.";
  if (!owner) {
    return (
      [opsDecisionSentence, "Ask the owner for details.", blockedSentence]
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
        "If you are part of that account, choose it in the company menu at the top of the screen. If not, ask the person who runs it to invite your phone number.",
        null
      ),
    // The bank reason, or none the app knows: new bank details are the one step that can help.
    _ => (
        "You can send your bank details for a new check.",
        "Send bank details"
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
          "NaviG8r is checking your company. Until it is approved, you cannot accept bookings or start trips.",
          null
        ),
      "REJECTED" => _rejectedMessage(owner: owner),
      _ => owner
          ? (
              "Add your bank details so NaviG8r can check your company. Until it is approved, you cannot accept bookings or start trips.",
              "Add bank details"
            )
          : (
              "Your company is not approved yet. Ask the owner to add bank details. Until then, you cannot accept bookings or start trips.",
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
