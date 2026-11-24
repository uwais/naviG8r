/**
 * The Load Board's requests: a shipper posts a load, lists its company's loads and withdraws one; a carrier office
 * reads the board; staff read every load. Making a route for a load is in routeForPostedLoad.ts, and what happens to
 * a load on booking and over time is in postedLoadLifecycle.ts.
 */
import { randomUUID } from "node:crypto";
import { ApiError } from "../../services.ts";
import { AuthorizationError, principalFor, recordAudit } from "../../rbac.ts";
import { isActiveEntity } from "../../softDelete.ts";
import type { Store } from "../../store.ts";
import { alertCarriersOfNewLoad } from "./loadAlerts.ts";
import { requireBoardViewer, requirePostingShipper } from "./loadBoardAudience.ts";
import { MAX_OPEN_LOADS_PER_SHIPPER, MAX_POSTS_PER_USER_PER_HOUR, type PostedLoad } from "./postedLoad.ts";

const HOUR_MS = 60 * 60 * 1000;
import { readPostedLoadInput } from "./postedLoadInput.ts";
import { loadForCarrier, loadForOps, loadForShipper } from "./postedLoadViews.ts";

const newestFirst = (a: PostedLoad, b: PostedLoad) => b.postedAtUtcMs - a.postedAtUtcMs || b.id.localeCompare(a.id);

export function postLoad(store: Store, body: unknown, nowUtcMs = Date.now()) {
  const shipper = requirePostingShipper(store);
  const fields = readPostedLoadInput(body, nowUtcMs);
  const open = [...store.postedLoads.values()].filter((load) => load.shipperOrgId === shipper.organizationId && load.state === "OPEN").length;
  if (open >= MAX_OPEN_LOADS_PER_SHIPPER) throw new ApiError("too_many_open_loads", { limit: MAX_OPEN_LOADS_PER_SHIPPER }, 409);
  const postedThisHour = [...store.postedLoads.values()].filter((load) => load.postedByUserId === shipper.userId && load.postedAtUtcMs > nowUtcMs - HOUR_MS);
  if (postedThisHour.length >= MAX_POSTS_PER_USER_PER_HOUR) {
    const oldest = Math.min(...postedThisHour.map((load) => load.postedAtUtcMs));
    throw new ApiError("rate_limited", { retryAfterMs: Math.max(1000, oldest + HOUR_MS - nowUtcMs) }, 429);
  }
  const load: PostedLoad = {
    id: `load_${randomUUID()}`,
    shipperOrgId: shipper.organizationId,
    postedByUserId: shipper.userId,
    ...fields,
    state: "OPEN",
    postedAtUtcMs: nowUtcMs,
    routes: [],
  };
  store.postedLoads.set(load.id, load);
  recordAudit(store, "POSTED_LOAD_CREATED", "posted_load", load.id, "ABSENT", "OPEN");
  alertCarriersOfNewLoad(store, load, nowUtcMs);
  return loadForShipper(store, load);
}

/** Every load the signed-in shipper's company posted, closed ones included, newest first. */
export function listMyLoads(store: Store) {
  const shipper = requirePostingShipper(store);
  return [...store.postedLoads.values()].filter((load) => load.shipperOrgId === shipper.organizationId).sort(newestFirst).map((load) => loadForShipper(store, load));
}

export function withdrawLoad(store: Store, loadId: string, nowUtcMs = Date.now()) {
  const shipper = requirePostingShipper(store);
  const load = store.postedLoads.get(loadId);
  if (!load || load.shipperOrgId !== shipper.organizationId) throw new AuthorizationError("not_found", 404);
  if (load.state !== "OPEN") throw new ApiError("load_not_open", { state: load.state }, 409);
  const withdrawn: PostedLoad = { ...load, state: "WITHDRAWN", closedAtUtcMs: nowUtcMs };
  store.postedLoads.set(load.id, withdrawn);
  recordAudit(store, "POSTED_LOAD_WITHDRAWN", "posted_load", load.id, "OPEN", "WITHDRAWN");
  return loadForShipper(store, withdrawn);
}

/** Open loads of active shipper companies only, the soonest pickup first. */
export function listBoard(store: Store) {
  requireBoardViewer(store);
  return [...store.postedLoads.values()]
    .filter((load) => load.state === "OPEN" && isActiveEntity(store.organizations.get(load.shipperOrgId)))
    .sort((a, b) => a.earliestPickupDate.localeCompare(b.earliestPickupDate) || a.postedAtUtcMs - b.postedAtUtcMs || a.id.localeCompare(b.id))
    .map(loadForCarrier);
}

/** Read only, for NaviG8r staff; the route guard already refused anyone else. */
export function listLoadsForOps(store: Store) {
  if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
  return [...store.postedLoads.values()].sort(newestFirst).map((load) => loadForOps(store, load));
}
