/**
 * The carrier office names the truck and the driver for a trip, and can change either until the trip is complete.
 * What the assignment means for who sees what is in tripAssignmentRules.ts.
 */
import { AuthorizationError, recordAudit, requirePermission } from "./rbac.ts";
import { ApiError, tripWithCarrierDisplay } from "./services.ts";
import { isActiveEntity } from "./softDelete.ts";
import type { Store } from "./store.ts";
import type { AnchorTrip } from "./types.ts";

const DRIVING_ROLES: readonly string[] = ["DRIVER", "OWNER_DRIVER", "OWNER"];

function drivesForCarrier(store: Store, userId: string, carrierId: string): boolean {
  const membership = store.memberships.get(`${userId}:${carrierId}`);
  return isActiveEntity(membership) && isActiveEntity(store.users.get(userId)) && DRIVING_ROLES.includes(membership!.role);
}

/**
 * Replaces any earlier assignment. A driver already on a trip in progress is a warning (driverBusy), not a refusal:
 * the office may know the other trip ends first.
 */
export function assignTrip(store: Store, tripId: string, input: Record<string, unknown>): { trip: ReturnType<typeof tripWithCarrierDisplay>; driverBusy: boolean } {
  const trip = store.anchorTrips.get(tripId);
  if (!trip) throw new AuthorizationError("not_found", 404);
  requirePermission(store, "trip.assign", trip);
  if (trip.status === "COMPLETED") {
    throw new ApiError("trip_completed", { detail: "This trip is complete, so its truck and driver can no longer change." }, 409);
  }
  if (trip.status === "CANCELLED") {
    throw new ApiError("trip_cancelled", { detail: "This trip was cancelled, so its truck and driver can no longer change." }, 409);
  }
  const vehicleId = input.vehicleId;
  const vehicle = typeof vehicleId === "string" ? store.vehicles.get(vehicleId) : undefined;
  if (!vehicle || !isActiveEntity(vehicle) || vehicle.orgId !== trip.carrierId) {
    throw new ApiError("invalid_trip_assignment", { detail: "Choose a truck from your own fleet.", field: "vehicleId" });
  }
  const chosenDriver = input.driverUserId;
  const driverUserId = typeof chosenDriver === "string" ? chosenDriver : "";
  if (!drivesForCarrier(store, driverUserId, trip.carrierId)) {
    throw new ApiError("invalid_trip_assignment", { detail: "Choose a driver who works for your carrier.", field: "driverUserId" });
  }
  const updated: AnchorTrip = { ...trip, assignedVehicleId: vehicle.id, assignedDriverUserId: driverUserId };
  store.anchorTrips.set(updated.id, updated);
  // State words only: the audit log never names the truck or the person.
  recordAudit(store, "TRIP_ASSIGNED", "trip", updated.id, trip.assignedVehicleId || trip.assignedDriverUserId ? "ASSIGNED" : "UNASSIGNED", "ASSIGNED");
  const driverBusy = [...store.anchorTrips.values()].some((other) =>
    other.id !== updated.id && isActiveEntity(other) && other.status === "IN_PROGRESS" && other.assignedDriverUserId === driverUserId);
  return { trip: tripWithCarrierDisplay(store, updated), driverBusy };
}

/** The pickers' choices for the caller's own carrier. Names only: no phone numbers leave the server here. */
export function carrierFleet(store: Store): {
  vehicles: Array<{ id: string; registrationNumber: string; vehicleClass: string }>;
  drivers: Array<{ userId: string; displayName: string }>;
} {
  const carrierId = requirePermission(store, "trip.assign").organizationId;
  const vehicles = [...store.vehicles.values()]
    .filter((vehicle) => vehicle.orgId === carrierId && isActiveEntity(vehicle))
    .map((vehicle) => ({ id: vehicle.id, registrationNumber: vehicle.registrationNumber, vehicleClass: vehicle.vehicleClass }))
    .sort((a, b) => a.registrationNumber.localeCompare(b.registrationNumber));
  const drivers = [...store.memberships.values()]
    .filter((membership) => membership.orgId === carrierId && drivesForCarrier(store, membership.userId, carrierId))
    .map((membership) => ({ userId: membership.userId, displayName: store.users.get(membership.userId)?.fullName ?? "" }))
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
  return { vehicles, drivers };
}
