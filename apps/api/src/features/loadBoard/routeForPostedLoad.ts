/**
 * A carrier office answers a posted load by making an ordinary route with today's route form, naming the load
 * (owner, 4 Nov 2026). The server checks the load is still open, the cities match and the route has room for it,
 * then records the route on the load and tells the shipper. Other shippers may still book the route's leftover room.
 */
import { ApiError, assertPhaseABookingEligible } from "../../services.ts";
import { AuthorizationError, recordAudit } from "../../rbac.ts";
import { isActiveEntity } from "../../softDelete.ts";
import type { Store } from "../../store.ts";
import type { AnchorTrip, GeoPoint } from "../../types.ts";
import { alertShipperOfRoute } from "./loadAlerts.ts";
import { requireBoardViewer } from "./loadBoardAudience.ts";
import { MAX_ROUTES_PER_CARRIER_PER_HOUR, type PostedLoad } from "./postedLoad.ts";

const sameCity = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase();
/** Two decimal places: a square about 1.1 km on a side. */
const roundedPoint = ({ lat, lng }: GeoPoint): GeoPoint => ({ lat: Math.round(lat * 100) / 100, lng: Math.round(lng * 100) / 100 });

/** Runs before the route is published, so a refused route is never made. Returns the load it is for. */
export function checkRouteForPostedLoad(store: Store, postedLoadId: unknown, route: {
  orgId: string; originCity: string; destCity: string; origin?: GeoPoint; destination?: GeoPoint; capacityKg: number;
}, nowUtcMs = Date.now()): PostedLoad {
  const office = requireBoardViewer(store);
  if (office.organizationId !== route.orgId) throw new AuthorizationError("not_found", 404);
  const load = typeof postedLoadId === "string" ? store.postedLoads.get(postedLoadId) : undefined;
  if (!load) throw new AuthorizationError("posted_load_not_found", 404);
  // A load whose shipper company was switched off has left the board, as listBoard shows it.
  if (load.state !== "OPEN" || !isActiveEntity(store.organizations.get(load.shipperOrgId))) throw new ApiError("posted_load_not_open", { state: load.state }, 409);
  const since = nowUtcMs - 60 * 60 * 1000;
  const madeThisHour = [...store.postedLoads.values()].flatMap((posted) => posted.routes).filter((made) => made.carrierOrgId === route.orgId && made.madeAtUtcMs > since);
  if (madeThisHour.length >= MAX_ROUTES_PER_CARRIER_PER_HOUR) throw new ApiError("rate_limited", { retryAfterMs: Math.max(1000, Math.min(...madeThisHour.map((made) => made.madeAtUtcMs)) - since) }, 429);
  if (!sameCity(load.from.city, route.originCity) || !sameCity(load.to.city, route.destCity)) throw new ApiError("route_cities_do_not_match_load");
  if (!(route.capacityKg >= load.weightKg)) throw new ApiError("route_too_small_for_load", { weightKg: load.weightKg });
  // The shipper books it exactly as today, and booking refuses a route whose ends are too far from the load's. Here
  // the route is held to the load's points rounded to about 1 km, as a carrier sees only the town, and no distance
  // is passed on. Booking checks the exact points later.
  if (route.origin && route.destination) {
    try {
      assertPhaseABookingEligible({ trip: { origin: route.origin, destination: route.destination } as AnchorTrip, pickup: roundedPoint(load.from), drop: roundedPoint(load.to) });
    } catch {
      throw new ApiError("route_too_far_from_load", { detail: "Start the route near the load's pickup city and end it near its drop city." });
    }
  }
  return load;
}

export function recordRouteForPostedLoad(store: Store, load: PostedLoad, trip: AnchorTrip, madeByUserId: string, nowUtcMs = Date.now()): void {
  store.postedLoads.set(load.id, { ...load, routes: [...load.routes, { tripId: trip.id, carrierOrgId: trip.carrierId, madeAtUtcMs: nowUtcMs }] });
  recordAudit(store, "POSTED_LOAD_ROUTE_MADE", "posted_load", load.id, undefined, trip.id);
  alertShipperOfRoute(store, load, trip, madeByUserId, nowUtcMs);
}
