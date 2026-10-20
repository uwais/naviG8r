import { randomUUID } from "node:crypto";
import { authorizationContext, recordAudit } from "./rbac.ts";
import type { Store } from "./store.ts";
import type { Payment } from "./types.ts";

function nowUtcMs(): number {
  return Date.now();
}

function findPaymentByRazorpayOrderId(store: Store, orderId: string): Payment | undefined {
  for (const p of store.payments.values()) {
    if (p.razorpayOrderId === orderId) return p;
  }
}

function findPaymentByRazorpayPaymentId(store: Store, razorpayPayId: string): Payment | undefined {
  for (const p of store.payments.values()) {
    if (p.razorpayPaymentId === razorpayPayId) return p;
  }
}

/** A cancelled shipment's payment says how it ended (refunded, hold released); a late event must not bring it back. */
function shipmentCancelled(store: Store, pay: Payment): boolean {
  return store.shipments.get(pay.shipmentId)?.status === "FAILED_CARRIER_REFUNDED";
}

/**
 * Money Razorpay reports after the shipment was cancelled is recorded, never applied: the shipment stays cancelled,
 * one audit row per event says what arrived, and a capture marks the payment so Finance refunds it in Razorpay.
 * Razorpay can deliver an event twice or late: an authorization NaviG8r already held, or the capture of a payment it
 * already refunded, is not new money and is ignored.
 */
function recordPaymentAfterCancel(store: Store, pay: Payment, event: "AUTHORIZED" | "CAPTURED", razorpayPayId: string): void {
  if (pay.razorpayPaymentId === razorpayPayId && (event === "AUTHORIZED" || pay.status === "REFUNDED")) return;
  const recorded = [...store.auditEvents.values()].some((row) =>
    row.action === "PAYMENT_AFTER_CANCEL" && row.resourceId === pay.shipmentId && row.reasonCode === event);
  if (recorded) return;
  const status = event === "CAPTURED" ? "CAPTURED_AFTER_CANCEL" : pay.status;
  if (status !== pay.status) store.payments.set(pay.id, { ...pay, status, updatedAtUtcMs: nowUtcMs() });
  // A webhook carries no signed-in person, and an audit row needs an actor.
  const context = authorizationContext.getStore() ?? { requestId: randomUUID() };
  authorizationContext.run({ ...context, system: true }, () =>
    recordAudit(store, "PAYMENT_AFTER_CANCEL", "shipment", pay.shipmentId, pay.status, status, event));
}

function paymentEntity(payload: Record<string, unknown>): { id?: string; order_id?: string; status?: string } | null {
  const payWrap = payload.payment as Record<string, unknown> | undefined;
  if (!payWrap) return null;
  const ent = payWrap.entity as Record<string, unknown> | undefined;
  if (!ent) return null;
  return {
    id: typeof ent.id === "string" ? ent.id : undefined,
    order_id: typeof ent.order_id === "string" ? ent.order_id : undefined,
    status: typeof ent.status === "string" ? ent.status : undefined,
  };
}

/** Apply one Razorpay webhook JSON body into the store (caller persists). Best-effort / idempotent. */
export function applyRazorpayWebhookPayload(store: Store, raw: Record<string, unknown>): void {
  const event = String(raw.event ?? "");
  const payload = raw.payload as Record<string, unknown> | undefined;
  if (!payload) return;

  const ent = paymentEntity(payload);
  if (!ent?.id && !ent?.order_id) return;

  const now = nowUtcMs();

  if (event === "payment.authorized") {
    const orderId = ent.order_id ?? "";
    if (!orderId) return;
    const pay = findPaymentByRazorpayOrderId(store, orderId);
    if (!pay || pay.provider !== "RAZORPAY") return;
    const rid = ent.id ?? pay.razorpayPaymentId;
    if (!rid) return;
    if (pay.status === "AUTHORIZED" || pay.status === "CAPTURED") return;
    if (shipmentCancelled(store, pay)) return recordPaymentAfterCancel(store, pay, "AUTHORIZED", rid);
    store.payments.set(pay.id, {
      ...pay,
      status: "AUTHORIZED",
      razorpayPaymentId: rid,
      updatedAtUtcMs: now,
    });
    return;
  }

  if (event === "payment.captured") {
    const razorpayPayId = ent.id ?? "";
    if (!razorpayPayId) return;
    const pay = findPaymentByRazorpayPaymentId(store, razorpayPayId)
      ?? (ent.order_id ? findPaymentByRazorpayOrderId(store, ent.order_id) : undefined);
    if (!pay || pay.provider !== "RAZORPAY") return;
    if (shipmentCancelled(store, pay)) return recordPaymentAfterCancel(store, pay, "CAPTURED", razorpayPayId);
    store.payments.set(pay.id, {
      ...pay,
      razorpayPaymentId: razorpayPayId,
      status: "CAPTURED",
      updatedAtUtcMs: now,
    });
    return;
  }

  if (event === "payment.failed") {
    const razorpayPayId = ent.id ?? "";
    const orderId = ent.order_id ?? "";
    const pay = (razorpayPayId ? findPaymentByRazorpayPaymentId(store, razorpayPayId) : undefined)
      ?? (orderId ? findPaymentByRazorpayOrderId(store, orderId) : undefined);
    if (!pay || pay.provider !== "RAZORPAY") return;
    if (pay.status === "CAPTURED" || pay.status === "REFUNDED" || shipmentCancelled(store, pay)) return;
    store.payments.set(pay.id, {
      ...pay,
      ...(razorpayPayId ? { razorpayPaymentId: razorpayPayId } : {}),
      status: "FAILED",
      updatedAtUtcMs: now,
    });
  }
}
