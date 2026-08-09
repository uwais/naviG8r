import type { Store } from "./store.ts";
import type { Payment, Shipment } from "./types.ts";

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

function findShipmentByPaymentId(store: Store, paymentId: string): Shipment | undefined {
  for (const s of store.shipments.values()) {
    if (s.paymentId === paymentId) return s;
  }
}

function releasePendingCheckoutCapacity(store: Store, shipment: Shipment): void {
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  if (!trip) return;
  trip.reservedKg = Math.max(0, trip.reservedKg - shipment.weightKg);
  if (trip.status === "FULL" && trip.reservedKg < trip.capacityKg) trip.status = "OPEN";
  store.anchorTrips.set(trip.id, trip);
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
    // Do not downgrade secured/terminal payments (retry/late failed webhooks).
    if (pay.status === "AUTHORIZED" || pay.status === "CAPTURED" || pay.status === "REFUNDED") return;
    if (pay.status === "FAILED") return;
    store.payments.set(pay.id, {
      ...pay,
      ...(razorpayPayId ? { razorpayPaymentId: razorpayPayId } : {}),
      status: "FAILED",
      updatedAtUtcMs: now,
    });
    // Abandoned/failed checkout: free reserved capacity so the trip is bookable again.
    const shipment = findShipmentByPaymentId(store, pay.id);
    if (shipment && shipment.status === "PENDING_CARRIER_ACCEPT") {
      releasePendingCheckoutCapacity(store, shipment);
      store.shipments.set(shipment.id, {
        ...shipment,
        status: "FAILED_CARRIER_REFUNDED",
        updatedAtUtcMs: now,
      });
    }
  }
}
