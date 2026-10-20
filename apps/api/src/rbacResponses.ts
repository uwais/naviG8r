import { authorizationContext, paymentReady } from "./rbac.ts";
import { ewayBillForRoles } from "./ewayBillVisibility.ts";
import type { EwayBill } from "./types.ts";
const pick = (v: Record<string, unknown>, keys: string[]) => Object.fromEntries(keys.filter(k => v[k] !== undefined).map(k => [k, v[k]]));
/** What the carrier earns and when it is paid. A DRIVER never gets these, whatever the route (owner decision, 15 Oct 2026). */
const carrierPayFields = ["netToCarrierPaise", "totalNetToCarrierPaise", "pendingAccruedPaise", "paidPaise", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "paidAtUtcMs", "cutoffUtcMs", "paymentReady", "paymentHoldUntilUtcMs"];
/** Domain allowlists prevent new storage fields from silently becoming API fields. */
export function serializeResponse(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(serializeResponse);
  if (!value || typeof value !== "object") return value;
  const v = value as Record<string, unknown>;
  const p = authorizationContext.getStore()?.principal;
  let out: Record<string, unknown>;
  if ("customerOrgName" in v && "paymentId" in v) {
    const keys = ["id", "anchorTripId", "carrierId", "carrierDisplayName", "customerOrgId", "customerOrgName", "status", "weightKg", "createdAtUtcMs", "updatedAtUtcMs", "podAtUtcMs", "podAcceptedAtUtcMs", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "externalLoadId"];
    if (p?.roles.some(r => ["SHIPPER", "CARRIER", "OPS"].includes(r))) keys.push("pickupAddress", "dropAddress", "pickup", "drop", "assignedTruckNumber");
    if (p?.roles.some(r => ["SHIPPER", "FINANCE"].includes(r))) keys.push("grossPaise");
    // The shipper enters it on the e-way bill (owner decision, 16 Oct 2026); no other role needs it on a shipment.
    if (p?.roles.includes("SHIPPER")) keys.push("carrierTransporterId");
    if (p?.roles.some(r => ["CARRIER", "FINANCE"].includes(r))) keys.push("netToCarrierPaise");
    if (p?.roles.includes("FINANCE")) keys.push("commissionPaise", "paymentId");
    const ewayBill = ewayBillForRoles(v.ewayBill as EwayBill | undefined, p?.roles ?? []);
    out = { ...pick(v, keys), ...(ewayBill ? { ewayBill } : {}), paymentReady: paymentReady(v as never), paymentHoldUntilUtcMs: typeof v.podAtUtcMs === "number" ? v.podAtUtcMs + 48 * 60 * 60 * 1000 : null };
  } else if ("providerRef" in v && "amountPaise" in v) {
    out = pick(v, ["id", "shipmentId", "status", "provider", "createdAtUtcMs", "updatedAtUtcMs", ...(p?.roles.some(r => ["SHIPPER", "FINANCE"].includes(r)) ? ["amountPaise", "razorpayOrderId"] : [])]);
  } else if ("kind" in v && "kycStatus" in v) {
    out = pick(v, ["id", "kind", "displayName", "kycStatus", "createdAtUtcMs", "inactiveAtUtcMs", "rejectionReasonCode", "approvalTakenBack",
      // The carrier office (whoever may assign trips) reads its own transporter ID; its drivers have no use for it.
      ...(p !== undefined && p.roles.includes("CARRIER") && p.permissions.includes("trip.assign") && v.id === p.organizationId ? ["transporterId"] : [])]);
  } else if ("originCity" in v && "reservedKg" in v) {
    out = pick(v, ["id", "carrierId", "carrierDisplayName", "originCity", "destCity", "origin", "destination", "windowStart", "windowEnd", "vehicleClass", "capacityKg", "reservedKg", "status", "createdAtUtcMs", "startedAtUtcMs", "completedAtUtcMs",
      // Who drives is the carrier's own business, and ops'. Shippers and public trip lists never get it.
      ...(p?.roles.some(r => ["CARRIER", "OPS"].includes(r)) ? ["assignedVehicleId", "assignedDriverUserId", "assignedTruckNumber", "assignedDriverName"] : []),
      // The carrier's reason and note for asking NaviG8r to cancel are for the operations team only.
      ...(p?.internal ? ["cancelRequest"] : [])]);
  } else if ("netToCarrierPaise" in v && "shipmentId" in v) {
    out = pick(v, ["id", "shipmentId", "carrierId", "status", "podAtUtcMs", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "paidAtUtcMs", "createdAtUtcMs", ...(p?.roles.some(r => ["CARRIER", "FINANCE"].includes(r)) ? ["netToCarrierPaise"] : []), ...(p?.roles.includes("FINANCE") ? ["grossPaise", "commissionPaise"] : [])]);
  } else {
    out = { ...v };
    for (const key of ["accountNumber", "pan", "PAN", "bankStatement", "secretHash", "webhookSecret", "payoutContactId", "payoutFundAccountId", "providerRef", "providerPayoutId", "permanentUrl", "documentUrl", "metadata", "podNotes"]) delete out[key];
  }
  // After every branch, since payout batches, their transfers and the earnings summary have no branch of their own.
  if (p?.subrole === "DRIVER") for (const key of carrierPayFields) delete out[key];
  return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, serializeResponse(v)]));
}
