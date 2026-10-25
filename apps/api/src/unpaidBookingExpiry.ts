import type { Shipment } from "./types.ts";
import type { Store } from "./store.ts";
import { emitIntegrationEvent } from "./integrationWebhooks.ts";

/** How long a booking holds trip space while it waits for the shipper's payment. */
export const UNPAID_BOOKING_WINDOW_MS = 30 * 60 * 1000;

export const UNPAID_BOOKING_EXPIRED_DETAIL =
  `This booking expired because it was not paid within ${UNPAID_BOOKING_WINDOW_MS / 60_000} minutes.`;

/**
 * Closes one booking whose payment never arrived within the window and frees the trip space it held.
 * Returns true when it closed the booking now.
 */
export function expireUnpaidBooking(store: Store, shipment: Shipment, now = Date.now()): boolean {
  if (shipment.status !== "PENDING_CARRIER_ACCEPT") return false;
  if (now < shipment.createdAtUtcMs + UNPAID_BOOKING_WINDOW_MS) return false;
  const payment = store.payments.get(shipment.paymentId);
  if (!payment || payment.provider !== "RAZORPAY") return false;
  if (payment.status !== "CREATED" && payment.status !== "FAILED") return false;

  const trip = store.anchorTrips.get(shipment.anchorTripId);
  if (trip) {
    trip.reservedKg = Math.max(0, trip.reservedKg - shipment.weightKg);
    if (trip.status === "FULL" && trip.reservedKg < trip.capacityKg) trip.status = "OPEN";
    store.anchorTrips.set(trip.id, trip);
  }
  store.payments.set(payment.id, { ...payment, status: "FAILED", updatedAtUtcMs: now });
  store.shipments.set(shipment.id, {
    ...shipment,
    status: "FAILED_CARRIER_REFUNDED",
    unpaidBookingExpiredAtUtcMs: now,
    updatedAtUtcMs: now,
  });
  emitIntegrationEvent(store, { eventType: "load.cancelled", shipmentId: shipment.id });
  return true;
}

/**
 * Keeps the Razorpay payment id of a payment that arrived after its booking expired, so staff can find it.
 * Razorpay refunds an authorized payment that is never captured, and a closed booking is never captured.
 */
export function keepPaymentAfterExpiry(store: Store, paymentId: string, razorpayPaymentId: string, now = Date.now()): void {
  const payment = store.payments.get(paymentId);
  if (!payment || (payment.status !== "CREATED" && payment.status !== "FAILED")) return;
  store.payments.set(payment.id, { ...payment, status: "AUTHORIZED", razorpayPaymentId, updatedAtUtcMs: now });
}

/** Run before reading trip space or booking lists, so an unpaid booking past its window holds nothing. */
export function expireUnpaidBookings(store: Store, now = Date.now()): void {
  for (const shipment of [...store.shipments.values()]) expireUnpaidBooking(store, shipment, now);
}
