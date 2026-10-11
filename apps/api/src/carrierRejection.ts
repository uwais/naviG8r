import { compatibleRole, effectivePermissions, legacyRoles } from "./rbac.ts";
import type { Store } from "./store.ts";
import type { Membership, Organization } from "./types.ts";

/** The reasons /ops/beta offers for rejecting a carrier (opsConsoleBeta.ts), except "Approval taken back". No other
 *  code reaches the carrier; approvalTakenBack comes from the state a rejection replaced, whatever the reason. */
const reasonsCarriersMayRead = new Set(["DOCUMENTS_MISSING", "BANK_DETAILS_MISMATCH", "DUPLICATE_ACCOUNT", "NOT_A_CARRIER"]);
const carrierKinds = new Set(["CARRIER_SOLO", "CARRIER_FLEET", "CARRIER_LEGACY"]);

/** What one member of a rejected carrier may read about the current rejection. Empty unless rejected now. */
export function carrierRejection(store: Store, org: Organization, member: Membership): { rejectionReasonCode?: string; approvalTakenBack?: boolean } {
  if (org.kycStatus !== "REJECTED" || !carrierKinds.has(org.kind)) return {};
  const events = [...store.auditEvents.values()].filter(e => e.resourceType === "organization" && e.resourceId === org.id);
  // Sorted by time, not map order: a database reload returns audit rows in no fixed order.
  const rejections = events
    .filter(e => e.action === "COMPLIANCE_STATUS_CHANGED" && e.newState === "REJECTED")
    .sort((a, b) => a.timestamp - b.timestamp);
  const newest = rejections.at(-1);
  if (!newest) return {};
  // Ops can reject an already rejected carrier, so the first rejection in this run says what it replaced.
  let first = newest;
  for (const earlier of rejections.slice(0, -1).reverse()) {
    if (first.previousState !== "REJECTED") break;
    first = earlier;
  }
  // Proof of a bank-details save: its log entry (only since 16 Sep), any review of a carrier waiting for review
  // (only a save sets SUBMITTED), or a RazorpayX fund account (older saves on production went straight to APPROVED).
  const rejectedAt = newest.timestamp;
  const bankDetailsSaved = Boolean(org.payoutFundAccountId) || events.some(e => e.timestamp <= rejectedAt &&
    (e.action === "BANK_ACCOUNT_CHANGED" || (e.action === "COMPLIANCE_STATUS_CHANGED" && e.previousState === "SUBMITTED")));
  // Only members who can save bank details can act on the bank reason, so only they get it. Roles are worked out as
  // resolvePrincipal does (rbac.ts), so this matches the save route. Every ops page's reject caption states this rule.
  const roles = (store.membershipRoles.get(`${member.userId}:${member.orgId}`) ?? legacyRoles(member, org)).filter(r => compatibleRole(r, org));
  const memberCanSaveBankDetails = effectivePermissions(roles, member.role).includes("bank_account.create_token");
  const code = newest.reasonCode;
  const out: { rejectionReasonCode?: string; approvalTakenBack?: boolean } = {};
  if (code && reasonsCarriersMayRead.has(code) && (code !== "BANK_DETAILS_MISMATCH" || (bankDetailsSaved && memberCanSaveBankDetails))) out.rejectionReasonCode = code;
  if (first.previousState === "APPROVED") out.approvalTakenBack = true;
  return out;
}
