/**
 * A carrier office takes back a trip it published (owner decision, 19 Oct 2026). With no booking on it, the trip is
 * cancelled at once. With bookings, the carrier asks NaviG8r instead: the trip takes no new bookings, operations
 * sees the request, and Finance cancels each shipment with failCarrierAndRefund, which ends the trip after the last.
 */
import { AuthorizationError, principalFor, recordAudit, requirePermission } from "./rbac.ts";
import { ApiError, bookingsOnTrip, tripHasBookings, tripWithCarrierDisplay } from "./services.ts";
import { isActiveEntity } from "./softDelete.ts";
import type { Store } from "./store.ts";
import type { AnchorTrip, TripCancelReasonCode } from "./types.ts";

const REASON_CODES: readonly TripCancelReasonCode[] = ["TRUCK_UNAVAILABLE", "DRIVER_UNAVAILABLE", "ROUTE_CHANGED", "OTHER"];
const MAX_NOTE_LENGTH = 500;

function officeTrip(store: Store, tripId: string): AnchorTrip {
  const trip = store.anchorTrips.get(tripId);
  if (!trip || !isActiveEntity(trip)) throw new AuthorizationError("not_found", 404);
  requirePermission(store, "trip.assign", trip);
  return trip;
}

function notBeforeTheRoad(trip: AnchorTrip): void {
  if (trip.status !== "OPEN" && trip.status !== "FULL") {
    throw new ApiError("trip_not_cancellable", { detail: "Only a trip that has not started can be cancelled.", status: trip.status }, 409);
  }
}

function changeStatus(store: Store, trip: AnchorTrip, changed: AnchorTrip): ReturnType<typeof tripWithCarrierDisplay> {
  store.anchorTrips.set(changed.id, changed);
  recordAudit(store, "TRIP_STATUS_CHANGED", "trip", trip.id, trip.status, changed.status, changed.cancelRequest?.reasonCode);
  return tripWithCarrierDisplay(store, changed);
}

/** A trip with no booking at all, paid or not, accepted or not. Asking again for a cancelled trip changes nothing. */
export function cancelTrip(store: Store, tripId: string): { trip: ReturnType<typeof tripWithCarrierDisplay> } {
  const trip = officeTrip(store, tripId);
  if (trip.status === "CANCELLED") return { trip: tripWithCarrierDisplay(store, trip) };
  notBeforeTheRoad(trip);
  if (tripHasBookings(store, trip.id)) {
    throw new ApiError("trip_has_bookings", { detail: "This trip has bookings, so it cannot be cancelled here." }, 409);
  }
  return { trip: changeStatus(store, trip, { ...trip, status: "CANCELLED" }) };
}

/** The trip stops taking bookings until NaviG8r cancels its shipments or the carrier withdraws. Asking twice keeps the first reason. */
export function requestTripCancel(store: Store, tripId: string, input: Record<string, unknown>): { trip: ReturnType<typeof tripWithCarrierDisplay> } {
  const trip = officeTrip(store, tripId);
  if (trip.status === "CANCEL_REQUESTED") return { trip: tripWithCarrierDisplay(store, trip) };
  notBeforeTheRoad(trip);
  if (!tripHasBookings(store, trip.id)) {
    throw new ApiError("trip_has_no_bookings", { detail: "This trip has no bookings, so you can cancel it yourself." }, 409);
  }
  const reasonCode = input.reasonCode as TripCancelReasonCode;
  if (!REASON_CODES.includes(reasonCode)) {
    throw new ApiError("invalid_cancel_request", { detail: "Choose why you want to cancel this trip.", field: "reasonCode" });
  }
  const note = typeof input.note === "string" ? input.note.trim() : "";
  if (note.length > MAX_NOTE_LENGTH) {
    throw new ApiError("invalid_cancel_request", { detail: `Keep the note to ${MAX_NOTE_LENGTH} characters or fewer.`, field: "note" });
  }
  const cancelRequest = { reasonCode, ...(note ? { note } : {}), requestedAtUtcMs: Date.now() };
  return { trip: changeStatus(store, trip, { ...trip, status: "CANCEL_REQUESTED", cancelRequest }) };
}

/** Back to OPEN, or FULL when its bookings fill it. Withdrawing a request already withdrawn changes nothing. */
export function withdrawTripCancelRequest(store: Store, tripId: string): { trip: ReturnType<typeof tripWithCarrierDisplay> } {
  const trip = officeTrip(store, tripId);
  if ((trip.status === "OPEN" || trip.status === "FULL") && !trip.cancelRequest) return { trip: tripWithCarrierDisplay(store, trip) };
  if (trip.status !== "CANCEL_REQUESTED") {
    throw new ApiError("no_cancel_request", { detail: "This trip has no cancel request to withdraw.", status: trip.status }, 409);
  }
  const { cancelRequest: _withdrawn, ...rest } = trip;
  return { trip: changeStatus(store, trip, { ...rest, status: trip.reservedKg >= trip.capacityKg ? "FULL" : "OPEN" }) };
}

/** Every trip waiting on NaviG8r, oldest request first, with the bookings Finance still has to cancel. Operations staff only. */
export function listTripCancelRequestsForOps(store: Store) {
  if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
  return [...store.anchorTrips.values()]
    .filter((trip) => trip.status === "CANCEL_REQUESTED" && isActiveEntity(trip))
    .sort((a, b) => (a.cancelRequest?.requestedAtUtcMs ?? 0) - (b.cancelRequest?.requestedAtUtcMs ?? 0))
    .map((trip) => ({
      trip: tripWithCarrierDisplay(store, trip),
      shipments: bookingsOnTrip(store, trip.id).map((shipment) => ({ shipment, payment: store.payments.get(shipment.paymentId) ?? null })),
    }));
}
