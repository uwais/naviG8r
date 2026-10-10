import type { Store } from "./store.ts";
import type { Organization } from "./types.ts";

/** The reasons /ops/beta offers for rejecting a carrier (opsConsoleBeta.ts). No other code reaches the carrier. */
const reasonsCarriersMayRead = new Set(["DOCUMENTS_MISSING", "BANK_DETAILS_MISMATCH", "DUPLICATE_ACCOUNT", "NOT_A_CARRIER"]);
const carrierKinds = new Set(["CARRIER_SOLO", "CARRIER_FLEET", "CARRIER_LEGACY"]);

/** What a rejected carrier's own members may read about the current rejection. Empty unless rejected now. */
export function carrierRejection(store: Store, org: Organization): { rejectionReasonCode?: string; approvalTakenBack?: boolean } {
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
  // Only saving bank details moves a carrier to SUBMITTED; the save itself is logged only since 16 Sep.
  const rejectedAt = newest.timestamp;
  const bankDetailsSaved = first.previousState === "SUBMITTED" || events.some(e => e.action === "BANK_ACCOUNT_CHANGED" && e.timestamp <= rejectedAt);
  const code = newest.reasonCode;
  const out: { rejectionReasonCode?: string; approvalTakenBack?: boolean } = {};
  if (code && reasonsCarriersMayRead.has(code) && (code !== "BANK_DETAILS_MISMATCH" || bankDetailsSaved)) out.rejectionReasonCode = code;
  if (first.previousState === "APPROVED") out.approvalTakenBack = true;
  return out;
}
