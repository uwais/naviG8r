import { authorizationContext, paymentReady } from "./rbac.ts";
import { ewayBillForRoles } from "./ewayBillVisibility.ts";
import type { EwayBill } from "./types.ts";
const pick = (v: Record<string, unknown>, keys: string[]) => Object.fromEntries(keys.filter(k => v[k] !== undefined).map(k => [k, v[k]]));
/** Domain allowlists prevent new storage fields from silently becoming API fields. */
export function serializeResponse(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(serializeResponse);
  if (!value || typeof value !== "object") return value;
  const v = value as Record<string, unknown>;
  const p = authorizationContext.getStore()?.principal;
  // A DRIVER never sees carrier earnings (owner decision, 15 Oct 2026), whatever the route.
  const seesCarrierMoney = p?.subrole !== "DRIVER" && p?.roles.some(r => ["CARRIER", "FINANCE"].includes(r));
  let out: Record<string, unknown>;
  if ("customerOrgName" in v && "paymentId" in v) {
    const keys = ["id", "anchorTripId", "carrierId", "carrierDisplayName", "customerOrgId", "customerOrgName", "status", "weightKg", "createdAtUtcMs", "updatedAtUtcMs", "podAtUtcMs", "podAcceptedAtUtcMs", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "externalLoadId"];
    if (p?.roles.some(r => ["SHIPPER", "CARRIER", "OPS"].includes(r))) keys.push("pickupAddress", "dropAddress", "pickup", "drop", "assignedTruckNumber");
    if (p?.roles.some(r => ["SHIPPER", "FINANCE"].includes(r))) keys.push("grossPaise");
    if (seesCarrierMoney) keys.push("netToCarrierPaise");
    if (p?.roles.includes("FINANCE")) keys.push("commissionPaise", "paymentId");
    const ewayBill = ewayBillForRoles(v.ewayBill as EwayBill | undefined, p?.roles ?? []);
    out = { ...pick(v, keys), ...(ewayBill ? { ewayBill } : {}), paymentReady: paymentReady(v as never), paymentHoldUntilUtcMs: typeof v.podAtUtcMs === "number" ? v.podAtUtcMs + 48 * 60 * 60 * 1000 : null };
  } else if ("providerRef" in v && "amountPaise" in v) {
    out = pick(v, ["id", "shipmentId", "status", "provider", "createdAtUtcMs", "updatedAtUtcMs", ...(p?.roles.some(r => ["SHIPPER", "FINANCE"].includes(r)) ? ["amountPaise", "razorpayOrderId"] : [])]);
  } else if ("kind" in v && "kycStatus" in v) {
    out = pick(v, ["id", "kind", "displayName", "kycStatus", "createdAtUtcMs", "inactiveAtUtcMs", "rejectionReasonCode", "approvalTakenBack"]);
  } else if ("originCity" in v && "reservedKg" in v) {
    out = pick(v, ["id", "carrierId", "carrierDisplayName", "originCity", "destCity", "origin", "destination", "windowStart", "windowEnd", "vehicleClass", "capacityKg", "reservedKg", "status", "createdAtUtcMs", "startedAtUtcMs", "completedAtUtcMs",
      // Who drives is the carrier's own business, and ops'. Shippers and public trip lists never get it.
      ...(p?.roles.some(r => ["CARRIER", "OPS"].includes(r)) ? ["assignedVehicleId", "assignedDriverUserId", "assignedTruckNumber", "assignedDriverName"] : [])]);
  } else if ("netToCarrierPaise" in v && "shipmentId" in v) {
    out = pick(v, ["id", "shipmentId", "carrierId", "status", "podAtUtcMs", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "paidAtUtcMs", "createdAtUtcMs", ...(seesCarrierMoney ? ["netToCarrierPaise"] : []), ...(p?.roles.includes("FINANCE") ? ["grossPaise", "commissionPaise"] : [])]);
  } else {
    out = { ...v };
    for (const key of ["accountNumber", "pan", "PAN", "bankStatement", "secretHash", "webhookSecret", "payoutContactId", "payoutFundAccountId", "providerRef", "providerPayoutId", "permanentUrl", "documentUrl", "metadata", "podNotes"]) delete out[key];
    // Payout batches, their transfers and the earnings summary have no branch of their own.
    if (p?.subrole === "DRIVER") for (const key of ["netToCarrierPaise", "totalNetToCarrierPaise", "pendingAccruedPaise", "paidPaise"]) delete out[key];
  }
  return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, serializeResponse(v)]));
}
