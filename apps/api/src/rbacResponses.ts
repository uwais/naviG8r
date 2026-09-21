import { authorizationContext, paymentReady } from "./rbac.ts";
const pick = (v: Record<string, unknown>, keys: string[]) => Object.fromEntries(keys.filter(k => v[k] !== undefined).map(k => [k, v[k]]));
/** Domain allowlists prevent new storage fields from silently becoming API fields. */
export function serializeResponse(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(serializeResponse);
  if (!value || typeof value !== "object") return value;
  const v = value as Record<string, unknown>;
  const p = authorizationContext.getStore()?.principal;
  let out: Record<string, unknown>;
  if ("customerOrgName" in v && "paymentId" in v) {
    const keys = ["id", "anchorTripId", "carrierId", "carrierDisplayName", "customerOrgId", "customerOrgName", "status", "weightKg", "createdAtUtcMs", "updatedAtUtcMs", "podAtUtcMs", "podAcceptedAtUtcMs", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "externalLoadId"];
    if (p?.roles.some(r => ["SHIPPER", "CARRIER", "OPS"].includes(r))) keys.push("pickupAddress", "dropAddress", "pickup", "drop");
    if (p?.roles.some(r => ["SHIPPER", "FINANCE"].includes(r))) keys.push("grossPaise");
    if (p?.roles.some(r => ["CARRIER", "FINANCE"].includes(r))) keys.push("netToCarrierPaise");
    if (p?.roles.includes("FINANCE")) keys.push("commissionPaise", "paymentId");
    out = { ...pick(v, keys), paymentReady: paymentReady(v as never), paymentHoldUntilUtcMs: typeof v.podAtUtcMs === "number" ? v.podAtUtcMs + 48 * 60 * 60 * 1000 : null };
  } else if ("providerRef" in v && "amountPaise" in v) {
    out = pick(v, ["id", "shipmentId", "status", "provider", "createdAtUtcMs", "updatedAtUtcMs", ...(p?.roles.some(r => ["SHIPPER", "FINANCE"].includes(r)) ? ["amountPaise", "razorpayOrderId"] : [])]);
  } else if ("kind" in v && "kycStatus" in v) {
    out = pick(v, ["id", "kind", "displayName", "kycStatus", "createdAtUtcMs", "inactiveAtUtcMs"]);
  } else if ("originCity" in v && "reservedKg" in v) {
    out = pick(v, ["id", "carrierId", "carrierDisplayName", "originCity", "destCity", "origin", "destination", "windowStart", "windowEnd", "vehicleClass", "capacityKg", "reservedKg", "status", "createdAtUtcMs", "startedAtUtcMs", "completedAtUtcMs"]);
  } else if ("netToCarrierPaise" in v && "shipmentId" in v) {
    out = pick(v, ["id", "shipmentId", "carrierId", "status", "podAtUtcMs", "firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "paidAtUtcMs", "createdAtUtcMs", ...(p?.roles.some(r => ["CARRIER", "FINANCE"].includes(r)) ? ["netToCarrierPaise"] : []), ...(p?.roles.includes("FINANCE") ? ["grossPaise", "commissionPaise"] : [])]);
  } else {
    out = { ...v };
    for (const key of ["accountNumber", "pan", "PAN", "bankStatement", "secretHash", "webhookSecret", "payoutContactId", "payoutFundAccountId", "providerRef", "providerPayoutId", "permanentUrl", "documentUrl", "metadata", "podNotes"]) delete out[key];
  }
  return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, serializeResponse(v)]));
}
