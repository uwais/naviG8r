// Shared set-up for the Load Board tests: the HTTP fixture plus a carrier office, a driver, an unapproved carrier
// and a second shipper login, all signed in. Not a test file itself (no .test.ts), so the runner skips it.
import type { TestContext } from "node:test";
import { httpFixture } from "../../../../test/httpFixtures.ts";
import { inviteCarrierDriver, registerCustomerUser, registerSoloOwnerOperatorDriver } from "../../../services.ts";
import { indiaToday } from "../postedLoad.ts";

const DAY_MS = 24 * 60 * 60 * 1000;

/** YYYY-MM-DD in India, this many days from today. */
export function indiaDay(daysFromToday: number): string {
  return indiaToday(Date.now() + daysFromToday * DAY_MS);
}

/** A load that fits the rules: picked up today or tomorrow. */
export function loadBody(extra: Record<string, unknown> = {}) {
  return {
    from: { city: "Pune", lat: 18.5204, lng: 73.8567 },
    to: { city: "Mumbai", lat: 19.076, lng: 72.8777 },
    weightKg: 400,
    packages: { kind: "SIZES", count: 4, length: 40, width: 30, height: 20, unit: "INCHES" },
    earliestPickupDate: indiaDay(0),
    latestPickupDate: indiaDay(1),
    ...extra,
  };
}

/** A route the carrier office makes for the load, as the app sends it: today's route form plus the load's id. */
export function routeBody(orgId: string, postedLoadId: string, extra: Record<string, unknown> = {}) {
  return {
    orgId, postedLoadId, originCity: "Pune", destCity: "Mumbai",
    origin: { lat: 18.53, lng: 73.85 }, destination: { lat: 19.07, lng: 72.88 },
    windowStart: `${indiaDay(1)}T09:00:00.000Z`, windowEnd: `${indiaDay(1)}T18:00:00.000Z`,
    vehicleClass: "MEDIUM", capacityKg: 1000, ...extra,
  };
}

export async function loadBoardFixture(t: TestContext) {
  const f = await httpFixture(t);
  const carrierOrgId = f.carrierB.org.id;
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000021" });
  const dispatcher = inviteCarrierDriver(f.store, f.carrierB.user.id, { orgId: carrierOrgId, phone: "8000000021", role: "DISPATCHER" });
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000022" });
  const driver = inviteCarrierDriver(f.store, f.carrierB.user.id, { orgId: carrierOrgId, phone: "8000000022", role: "DRIVER", vehicleRegistrationNumber: "KA09LB0001", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const unapproved = registerSoloOwnerOperatorDriver(f.store, { fullName: "Synthetic Unapproved", phone: "8000000023", orgDisplayName: "Synthetic Unapproved", vehicleRegistrationNumber: "TEST-U", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const tokens = {
    ...f.tokens,
    dispatcher: await f.login("8000000021"),
    driver: await f.login("8000000022"),
    unapproved: await f.login("8000000023"),
  };
  const post = (body: unknown = loadBody(), token = tokens.shipperA) => f.request("/v1/posted-loads", "POST", body, token);
  const board = (token: string) => f.request("/v1/load-board", "GET", undefined, token);
  const makeRoute = (postedLoadId: string, token = tokens.carrierB, extra: Record<string, unknown> = {}) =>
    f.request("/v1/pilot/anchor-trips", "POST", routeBody(carrierOrgId, postedLoadId, extra), token);
  const notices = async (token: string) =>
    ((await f.request("/v1/notifications", "GET", undefined, token)).body.notifications ?? []) as Array<Record<string, any>>;
  return { f, tokens, dispatcher, driver, unapproved, carrierOrgId, post, board, makeRoute, notices };
}

/** Every key anywhere in a JSON value, nested ones included. */
export function allKeys(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(allKeys);
  if (!value || typeof value !== "object") return [];
  return Object.entries(value).flatMap(([key, inner]) => [key, ...allKeys(inner)]);
}
