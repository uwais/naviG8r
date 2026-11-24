/**
 * What a posted load is: a shipper's load that fit no route, put on the Load Board for carriers to make a route for.
 * It never carries an amount of any kind: the price is worked out only when the shipper books a route (owner, 4 Nov 2026).
 * A closed load is kept, never deleted, so the team can count what was posted and what came of it.
 */
export type PostedLoadState = "OPEN" | "BOOKED" | "WITHDRAWN" | "EXPIRED";

export type PostedLoadPlace = { city: string; lat: number; lng: number };

/** As the shipper entered it, with its unit. Nothing prices by it. */
export type PostedLoadPackages =
  | { kind: "SIZES"; count: number; length: number; width: number; height: number; unit: "INCHES" | "CENTIMETRES" }
  | { kind: "TOTAL_VOLUME"; volume: number; unit: "CUBIC_FEET" | "CUBIC_METRES" };

export type PostedLoad = {
  id: string;
  shipperOrgId: string;
  postedByUserId: string;
  from: PostedLoadPlace;
  to: PostedLoadPlace;
  weightKg: number;
  packages: PostedLoadPackages;
  /** Calendar days in India, YYYY-MM-DD. */
  earliestPickupDate: string;
  latestPickupDate: string;
  state: PostedLoadState;
  postedAtUtcMs: number;
  /** Set when it leaves OPEN; cleared if a failed booking puts it back on the board. */
  closedAtUtcMs?: number;
  /** Each route (trip) a carrier made for it. The route is otherwise ordinary: anyone may book its room. */
  routes: Array<{ tripId: string; carrierOrgId: string; madeAtUtcMs: number }>;
  booking?: { shipmentId: string; bookedAtUtcMs: number };
};

/** A carrier office member's choice to hear of new loads. No row means on. */
export type LoadAlertSetting = { userId: string; loadAlertsOn: boolean; updatedAtUtcMs: number };

export const MAX_OPEN_LOADS_PER_SHIPPER = 10;
export const MAX_DAYS_TO_EARLIEST_PICKUP = 7;
export const MAX_PICKUP_WINDOW_DAYS = 3;
// Each post alerts every carrier office and each route alerts the shipper, so both are capped per hour. Counted from
// what was made, as conversation messages are, so a refused attempt never uses one up.
export const MAX_POSTS_PER_USER_PER_HOUR = 10;
export const MAX_ROUTES_PER_CARRIER_PER_HOUR = 20;

const INDIA_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Today in India, YYYY-MM-DD: pickup dates are India calendar days. */
export function indiaToday(nowUtcMs: number): string {
  return new Date(nowUtcMs + INDIA_OFFSET_MS).toISOString().slice(0, 10);
}

/** Whole days from one YYYY-MM-DD to another; negative when the second is earlier. */
export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS);
}

/** Its latest pickup day is over in India, so no truck can collect it in its window. */
export function pickupWindowPassed(load: PostedLoad, nowUtcMs: number): boolean {
  return indiaToday(nowUtcMs) > load.latestPickupDate;
}
