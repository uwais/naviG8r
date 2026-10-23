/**
 * The carrier office's Remind button on a trip held by a shipper's e-way bill (owner, 23 Oct 2026). It replaced a
 * notice sent on every refused start: the office now chooses when the shipper is told. Which bills hold the start is
 * in ewayBillStartGate.ts; the notice and its words are in notifications.ts.
 */
import { AuthorizationError, requirePermission } from "./rbac.ts";
import { ApiError } from "./services.ts";
import { shipmentsBlockingStart } from "./ewayBillStartGate.ts";
import { remindShipperBillHoldsStart } from "./notifications.ts";
import { isActiveEntity } from "./softDelete.ts";
import { assignedTruckNumber } from "./tripAssignmentRules.ts";
import type { Store } from "./store.ts";

/** `sent` is false when an unread reminder for the same reason is already with the shipper. */
export function remindShipperOfEwayBill(store: Store, tripId: string, shipmentId: string): { sent: boolean } {
  const trip = store.anchorTrips.get(tripId);
  if (!trip || !isActiveEntity(trip)) throw new AuthorizationError("not_found", 404);
  requirePermission(store, "trip.assign", trip);
  const shipment = store.shipments.get(shipmentId);
  if (!shipment || shipment.anchorTripId !== trip.id || !isActiveEntity(shipment)) throw new AuthorizationError("not_found", 404);
  if (trip.status !== "OPEN" && trip.status !== "FULL") {
    throw new ApiError("trip_not_startable", { detail: "Only a trip that has not started waits for e-way bills.", status: trip.status }, 409);
  }
  const [holding] = shipmentsBlockingStart(store, trip, [shipment], Date.now());
  if (!holding) {
    throw new ApiError("eway_bill_not_holding_start", { detail: "This booking's e-way bill does not hold the trip." }, 409);
  }
  // With no truck on the trip every bill's truck reads as different; the office chooses a truck, the shipper fixes nothing.
  if (holding.reason === "truck_differs" && !assignedTruckNumber(store, trip)) {
    throw new ApiError("trip_has_no_truck", { detail: "Choose a truck first." }, 409);
  }
  return { sent: remindShipperBillHoldsStart(store, shipment, holding.reason) };
}
