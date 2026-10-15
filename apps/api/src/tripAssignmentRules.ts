/**
 * What follows from the truck and driver named on a trip: who may read the trip and its shipments, what is shown
 * about the assignment, and the solo owner-operator's default. Naming them is in tripAssignment.ts.
 * Imports types only, apart from softDelete.ts, because rbac.ts and services.ts both import this file.
 */
import type { Principal } from "./rbac.ts";
import type { Store } from "./store.ts";
import type { AnchorTrip } from "./types.ts";
import { isActiveEntity } from "./softDelete.ts";

/**
 * A DRIVER login sees only the trips naming them and the shipments on those trips. Everyone else, and any
 * resource that is neither a trip nor a shipment (an organization check, say), is left to visible().
 */
export function assignedDriverMaySee(store: Store, principal: Principal, resource: object): boolean {
  if (principal.internal || principal.subrole !== "DRIVER") return true;
  const fields = resource as { id?: unknown; anchorTripId?: unknown; reservedKg?: unknown };
  let tripId: string;
  if (typeof fields.anchorTripId === "string") tripId = fields.anchorTripId;
  else if (fields.reservedKg !== undefined && typeof fields.id === "string") tripId = fields.id;
  else return true;
  return store.anchorTrips.get(tripId)?.assignedDriverUserId === principal.userId;
}

/** The same form the e-way bill keeps its truck in, so the two compare as plain strings. */
export function normalizedTruckNumber(registrationNumber: string): string {
  return registrationNumber.replace(/[\s-]/g, "").toUpperCase();
}

export function assignedTruckNumber(store: Store, trip: AnchorTrip | undefined): string | undefined {
  const vehicle = trip?.assignedVehicleId ? store.vehicles.get(trip.assignedVehicleId) : undefined;
  const truckNumber = vehicle ? normalizedTruckNumber(vehicle.registrationNumber) : "";
  return truckNumber || undefined;
}

/** For carrier screens. The serializer keeps these, and the two ids, away from shippers and ERP callers. */
export function tripAssignmentDisplay(store: Store, trip: AnchorTrip): { assignedTruckNumber?: string; assignedDriverName?: string } {
  const truckNumber = assignedTruckNumber(store, trip);
  const driverName = trip.assignedDriverUserId ? store.users.get(trip.assignedDriverUserId)?.fullName : undefined;
  return {
    ...(truckNumber ? { assignedTruckNumber: truckNumber } : {}),
    ...(driverName ? { assignedDriverName: driverName } : {}),
  };
}

type AssignmentFields = { assignedVehicleId?: unknown; assignedDriverUserId?: unknown; assignedTruckNumber?: unknown; assignedDriverName?: unknown };

/** ERP responses are written without the serializer, and their shape is a contract with other systems. */
export function withoutTripAssignment<T extends AssignmentFields>(value: T): Omit<T, keyof AssignmentFields> {
  const copy = { ...value };
  delete copy.assignedVehicleId;
  delete copy.assignedDriverUserId;
  delete copy.assignedTruckNumber;
  delete copy.assignedDriverName;
  return copy;
}

/**
 * A solo owner-operator drives their own truck, so a trip they publish names them and their primary vehicle
 * with no extra step. Undefined for anyone else, or when the profile or vehicle is not in this organization.
 */
export function soloOwnerOperatorAssignment(store: Store, trip: AnchorTrip, userId: string): AnchorTrip | undefined {
  if (store.memberships.get(`${userId}:${trip.carrierId}`)?.role !== "OWNER_DRIVER") return undefined;
  const profile = store.driverProfiles.get(userId);
  const vehicle = profile ? store.vehicles.get(profile.primaryVehicleId) : undefined;
  if (!profile || profile.orgId !== trip.carrierId || !vehicle || !isActiveEntity(vehicle) || vehicle.orgId !== trip.carrierId) return undefined;
  return { ...trip, assignedVehicleId: vehicle.id, assignedDriverUserId: userId };
}
