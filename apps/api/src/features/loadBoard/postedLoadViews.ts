/**
 * Who sees what of a posted load, one builder per audience. Each picks its fields by name, so a field added to the
 * record later reaches nobody until it is added here. No builder has an amount: a posted load has none.
 * Carriers never get the shipper's name, map points, poster or note (who-sees-what table, 4 Nov 2026).
 */
import { isActiveEntity } from "../../softDelete.ts";
import { tripForPublicListing } from "../../services.ts";
import type { Store } from "../../store.ts";
import type { AnchorTrip } from "../../types.ts";
import type { PostedLoad } from "./postedLoad.ts";

/** The posting shipper company: everything it entered, and each route made for it as today's route search shows a route. */
export function loadForShipper(store: Store, load: PostedLoad) {
  return {
    id: load.id,
    from: load.from,
    to: load.to,
    weightKg: load.weightKg,
    packages: load.packages,
    earliestPickupDate: load.earliestPickupDate,
    latestPickupDate: load.latestPickupDate,
    ...(load.note ? { note: load.note } : {}),
    state: load.state,
    postedAtUtcMs: load.postedAtUtcMs,
    ...(load.closedAtUtcMs != null ? { closedAtUtcMs: load.closedAtUtcMs } : {}),
    ...(load.booking ? { booking: load.booking } : {}),
    routes: load.routes.flatMap((route) => {
      const trip = store.anchorTrips.get(route.tripId);
      if (!trip || !isActiveEntity(trip)) return [];
      const whyNot = whyNotBookable(store, load, trip);
      return [{ tripId: route.tripId, madeAtUtcMs: route.madeAtUtcMs, canBook: whyNot == null, ...(whyNot ? { whyNotBookable: whyNot } : {}), trip: tripForPublicListing(store, trip) }];
    }),
  };
}

/** Why My loads shows no Book button on this route, so the app can say so; undefined when it can be booked. */
function whyNotBookable(store: Store, load: PostedLoad, trip: AnchorTrip) {
  if (load.booking && store.shipments.get(load.booking.shipmentId)?.anchorTripId === trip.id) return "YOU_BOOKED_IT";
  if (trip.status !== "OPEN") return "TRIP_CLOSED";
  if (trip.capacityKg - trip.reservedKg < load.weightKg) return "NOT_ENOUGH_ROOM";
  if (load.state !== "OPEN") return "LOAD_CLOSED";
  return undefined;
}

/** An approved carrier office reading the board. */
export function loadForCarrier(load: PostedLoad) {
  return {
    id: load.id,
    fromCity: load.from.city,
    toCity: load.to.city,
    weightKg: load.weightKg,
    packages: load.packages,
    earliestPickupDate: load.earliestPickupDate,
    latestPickupDate: load.latestPickupDate,
    postedAtUtcMs: load.postedAtUtcMs,
  };
}

/** NaviG8r staff, read only, for counting what was posted and what came of it. */
export function loadForOps(store: Store, load: PostedLoad) {
  return {
    id: load.id,
    shipperOrgId: load.shipperOrgId,
    shipperName: store.organizations.get(load.shipperOrgId)?.displayName ?? "",
    fromCity: load.from.city,
    toCity: load.to.city,
    weightKg: load.weightKg,
    earliestPickupDate: load.earliestPickupDate,
    latestPickupDate: load.latestPickupDate,
    state: load.state,
    postedAtUtcMs: load.postedAtUtcMs,
    ...(load.closedAtUtcMs != null ? { closedAtUtcMs: load.closedAtUtcMs } : {}),
    routes: load.routes.map((route) => ({
      tripId: route.tripId,
      carrierOrgId: route.carrierOrgId,
      carrierName: store.organizations.get(route.carrierOrgId)?.displayName ?? "",
      madeAtUtcMs: route.madeAtUtcMs,
    })),
    ...(load.booking ? { booking: load.booking } : {}),
  };
}
