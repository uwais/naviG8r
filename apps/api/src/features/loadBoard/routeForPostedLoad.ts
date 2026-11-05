/**
 * A carrier office answers a posted load by making an ordinary route with today's route form, naming the load
 * (owner, 4 Nov 2026). The server checks the load is still open and the route has room for it, sets the route's ends
 * itself from the load, then records the route on the load and tells the shipper. Other shippers may still book the
 * route's leftover room.
 */
import { ApiError } from "../../services.ts";
import { AuthorizationError, recordAudit } from "../../rbac.ts";
import { isActiveEntity } from "../../softDelete.ts";
import type { Store } from "../../store.ts";
import type { AnchorTrip, GeoPoint } from "../../types.ts";
import { alertShipperOfRoute } from "./loadAlerts.ts";
import { requireBoardViewer } from "./loadBoardAudience.ts";
import { MAX_ROUTES_PER_CARRIER_PER_HOUR, type PostedLoad, type PostedLoadPlace } from "./postedLoad.ts";

/**
 * To 0.05 degrees: a square about 5 km on a side, so a trip end never places the shipper's point. The farthest a
 * point moves is under 4 km, well inside booking's 15 km check (PHASE_A_MAX_PICKUP_KM), so the shipper can always
 * book a route made for its load.
 */
const roundedPoint = ({ lat, lng }: PostedLoadPlace): GeoPoint => ({ lat: Math.round(lat * 20) / 20, lng: Math.round(lng * 20) / 20 });

/** Runs before the route is published, so a refused route is never made. Returns the load it is for. */
export function checkRouteForPostedLoad(store: Store, postedLoadId: unknown, route: { orgId: string; capacityKg: number }, nowUtcMs = Date.now()): PostedLoad {
  const office = requireBoardViewer(store);
  if (office.organizationId !== route.orgId) throw new AuthorizationError("not_found", 404);
  const load = typeof postedLoadId === "string" ? store.postedLoads.get(postedLoadId) : undefined;
  if (!load) throw new AuthorizationError("posted_load_not_found", 404);
  // A load whose shipper company was switched off has left the board, as listBoard shows it.
  if (load.state !== "OPEN" || !isActiveEntity(store.organizations.get(load.shipperOrgId))) throw new ApiError("posted_load_not_open", { state: load.state }, 409);
  const since = nowUtcMs - 60 * 60 * 1000;
  const madeThisHour = [...store.postedLoads.values()].flatMap((posted) => posted.routes).filter((made) => made.carrierOrgId === route.orgId && made.madeAtUtcMs > since);
  if (madeThisHour.length >= MAX_ROUTES_PER_CARRIER_PER_HOUR) throw new ApiError("rate_limited", { retryAfterMs: Math.max(1000, Math.min(...madeThisHour.map((made) => made.madeAtUtcMs)) - since) }, 429);
  if (!(route.capacityKg >= load.weightKg)) throw new ApiError("route_too_small_for_load", { weightKg: load.weightKg });
  return load;
}

/** The route's towns and ends, set from the load: whatever towns or map points the carrier sent are replaced. */
export function tripEndsForPostedLoad(load: PostedLoad) {
  return { originCity: load.from.city, destCity: load.to.city, origin: roundedPoint(load.from), destination: roundedPoint(load.to) };
}

export function recordRouteForPostedLoad(store: Store, load: PostedLoad, trip: AnchorTrip, madeByUserId: string, nowUtcMs = Date.now()): void {
  store.postedLoads.set(load.id, { ...load, routes: [...load.routes, { tripId: trip.id, carrierOrgId: trip.carrierId, madeAtUtcMs: nowUtcMs }] });
  recordAudit(store, "POSTED_LOAD_ROUTE_MADE", "posted_load", load.id, undefined, trip.id);
  alertShipperOfRoute(store, load, trip, madeByUserId, nowUtcMs);
}
