/**
 * What happens to a posted load after it is posted (owner, 4 Nov 2026). It is BOOKED when its own shipper company books
 * a route made for it; a booking by anyone else leaves it alone. If that booking then fails or is not paid in time, it
 * goes back on the board while its pickup window is still open. After its latest pickup day it is EXPIRED.
 * Nobody is alerted by any of this: the other carriers just stop seeing it.
 */
import { randomUUID } from "node:crypto";
import { authorizationContext, recordAudit } from "../../rbac.ts";
import { isActiveEntity } from "../../softDelete.ts";
import type { Store } from "../../store.ts";
import type { Shipment } from "../../types.ts";
import { pickupWindowPassed, type PostedLoad } from "./postedLoad.ts";

/** Called once a booking is made. Returns the load it booked, if any. */
export function markPostedLoadBooked(store: Store, shipment: Shipment, nowUtcMs = Date.now()): PostedLoad | undefined {
  const load = [...store.postedLoads.values()].find((candidate) =>
    candidate.state === "OPEN" && candidate.shipperOrgId === shipment.customerOrgId && candidate.routes.some((route) => route.tripId === shipment.anchorTripId));
  if (!load) return undefined;
  const booked: PostedLoad = { ...load, state: "BOOKED", closedAtUtcMs: nowUtcMs, booking: { shipmentId: shipment.id, bookedAtUtcMs: nowUtcMs } };
  store.postedLoads.set(load.id, booked);
  recordAudit(store, "POSTED_LOAD_BOOKED", "posted_load", load.id, "OPEN", "BOOKED");
  return booked;
}

function bookingFell(store: Store, load: PostedLoad): boolean {
  const shipment = load.booking ? store.shipments.get(load.booking.shipmentId) : undefined;
  return !shipment || !isActiveEntity(shipment) || shipment.status === "FAILED_CARRIER_REFUNDED";
}

/**
 * Expires open loads past their pickup window, and reopens or expires a booked load whose booking fell through. The
 * HTTP server runs this before every request, right after the unpaid-booking expiry, so no timer is needed.
 * Returns how many loads changed.
 */
export function sweepPostedLoads(store: Store, nowUtcMs = Date.now()): number {
  let changed = 0;
  for (const load of store.postedLoads.values()) {
    const fell = load.state === "BOOKED" && bookingFell(store, load);
    if (load.state !== "OPEN" && !fell) continue;
    if (load.state === "OPEN" && !pickupWindowPassed(load, nowUtcMs)) continue;
    const { booking: _booking, closedAtUtcMs: _closedAt, ...rest } = load;
    const next: PostedLoad = pickupWindowPassed(load, nowUtcMs) ? { ...rest, state: "EXPIRED", closedAtUtcMs: nowUtcMs } : { ...rest, state: "OPEN" };
    store.postedLoads.set(load.id, next);
    const requestId = authorizationContext.getStore()?.requestId ?? randomUUID();
    authorizationContext.run({ requestId, system: true, systemActor: "system:posted-load-sweep" }, () =>
      recordAudit(store, next.state === "OPEN" ? "POSTED_LOAD_REOPENED" : "POSTED_LOAD_EXPIRED", "posted_load", load.id, load.state, next.state));
    changed++;
  }
  return changed;
}
