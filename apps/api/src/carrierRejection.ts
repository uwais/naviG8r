import type { AuditEvent } from "./rbac.ts";
import type { Store } from "./store.ts";
import type { Organization } from "./types.ts";

/** The reasons /ops/beta offers for rejecting a carrier (opsConsoleBeta.ts). No other code reaches the carrier. */
const reasonsCarriersMayRead = new Set(["DOCUMENTS_MISSING", "BANK_DETAILS_MISMATCH", "DUPLICATE_ACCOUNT", "NOT_A_CARRIER"]);
const carrierKinds = new Set(["CARRIER_SOLO", "CARRIER_FLEET", "CARRIER_LEGACY"]);

/** What a rejected carrier's own members may read about the newest rejection. Empty unless rejected now. */
export function carrierRejection(store: Store, org: Organization): { rejectionReasonCode?: string; approvalTakenBack?: boolean } {
  if (org.kycStatus !== "REJECTED" || !carrierKinds.has(org.kind)) return {};
  const events = [...store.auditEvents.values()].filter(e => e.resourceType === "organization" && e.resourceId === org.id);
  // Newest by timestamp, not map order: a database reload returns audit rows in no fixed order.
  let newest: AuditEvent | undefined;
  for (const e of events) {
    if (e.action === "COMPLIANCE_STATUS_CHANGED" && e.newState === "REJECTED" && (!newest || e.timestamp >= newest.timestamp)) newest = e;
  }
  if (!newest) return {};
  const rejectedAt = newest.timestamp, code = newest.reasonCode;
  // The bank reason is only true of a carrier that saved bank details before this rejection.
  const bankDetailsSaved = events.some(e => e.action === "BANK_ACCOUNT_CHANGED" && e.timestamp <= rejectedAt);
  const out: { rejectionReasonCode?: string; approvalTakenBack?: boolean } = {};
  if (code && reasonsCarriersMayRead.has(code) && (code !== "BANK_DETAILS_MISMATCH" || bankDetailsSaved)) out.rejectionReasonCode = code;
  if (newest.previousState === "APPROVED") out.approvalTakenBack = true;
  return out;
}
