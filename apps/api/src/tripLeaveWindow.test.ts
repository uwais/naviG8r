import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { indiaDateString } from "./ewayBillValidation.ts";
import { publishAnchorTrip } from "./services.ts";
import { leaveWindowEnded } from "./tripLeaveWindow.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

const DAY_MS = 86_400_000;
/** UTC milliseconds for a wall-clock time in India. */
const india = (year: number, month: number, day: number, hour = 0, minute = 0, second = 0) =>
  Date.UTC(year, month - 1, day, hour, minute, second) - 5.5 * 60 * 60 * 1000;

/** The India date `days` from today, as the app sends a last leaving day: its final second in India. */
const lastLeavingDay = (days: number) => `${indiaDateString(Date.now() + days * DAY_MS)}T23:59:59+05:30`;
const firstLeavingDay = (days: number) => `${indiaDateString(Date.now() + days * DAY_MS)}T00:00:00+05:30`;

const nearTheLane = { pickup: { lat: 12.97, lng: 77.59 }, drop: { lat: 13.08, lng: 80.27 } };
const search = "/v1/customer/eligible-anchor-trips?pickupLat=12.97&pickupLng=77.59&dropLat=13.08&dropLng=80.27&weightKg=10";

function publish(f: Fixture, lastDayFromToday: number) {
  return publishAnchorTrip(f.store, {
    carrierId: f.carrierA.org.id, originCity: "Bengaluru", destCity: "Chennai",
    origin: { lat: 12.97, lng: 77.59 }, destination: { lat: 13.08, lng: 80.27 },
    windowStart: firstLeavingDay(lastDayFromToday - 1), windowEnd: lastLeavingDay(lastDayFromToday),
    vehicleClass: "MEDIUM", capacityKg: 1000,
  });
}

const listedIds = async (f: Fixture) => ((await f.request("/anchor-trips")).body.trips as { id: string }[]).map((t) => t.id);
const searchedIds = async (f: Fixture) =>
  ((await f.request(search)).body.trips as { trip: { id: string } }[]).map((row) => row.trip.id);

test("the window ends with the last leaving day in India, not in UTC", () => {
  const trip = { windowEnd: "2026-11-19T23:59:59+05:30" };
  assert.equal(leaveWindowEnded(trip, india(2026, 11, 19, 23, 59, 59)), false, "the last second of the last day");
  assert.equal(leaveWindowEnded(trip, india(2026, 11, 20)), true, "midnight in India the next day");
  assert.equal(leaveWindowEnded(trip, Date.UTC(2026, 11 - 1, 19, 20)), true, "20:00 UTC is already the 20th in India");
  assert.equal(leaveWindowEnded({ windowEnd: "2026-11-19" }, india(2026, 11, 19, 23)), false, "a date alone counts as that India day");
  assert.equal(leaveWindowEnded({ windowEnd: "2026-11-19" }, india(2026, 11, 20, 1)), true);
  assert.equal(leaveWindowEnded({ windowEnd: "" }, india(2030, 1, 1)), false, "a window with no readable end never ends");
  assert.equal(leaveWindowEnded({ windowEnd: "not a date" }, india(2030, 1, 1)), false);
});

test("Book a trip and route search list a trip on its last leaving day and drop it the day after", async t => {
  const f = await httpFixture(t);
  const lastDayToday = publish(f, 0);
  const lastDayYesterday = publish(f, -1);
  const lastDayTomorrow = publish(f, 1);

  const listed = await listedIds(f);
  assert.ok(listed.includes(lastDayToday.id), "the last leaving day is still listed");
  assert.ok(listed.includes(lastDayTomorrow.id));
  assert.ok(!listed.includes(lastDayYesterday.id), "the day after the last leaving day it is gone");

  const searched = await searchedIds(f);
  assert.ok(searched.includes(lastDayToday.id));
  assert.ok(!searched.includes(lastDayYesterday.id));

  const one = await f.request(`/anchor-trips/${lastDayYesterday.id}`);
  assert.equal(one.status, 200, "the trip itself still opens, so a link to it can say why it cannot be booked");
  assert.equal(one.body.trip.leaveWindowEnded, true);
  assert.equal((await f.request(`/anchor-trips/${lastDayToday.id}`)).body.trip.leaveWindowEnded, false);
});

test("booking a trip whose last leaving day has passed is refused with its own code and sentence, and holds no room", async t => {
  const f = await httpFixture(t);
  const ended = publish(f, -1);
  const refused = await f.book(f.tokens.shipperA, { anchorTripId: ended.id, ...nearTheLane });
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, "anchor_trip_leave_window_ended");
  assert.equal(refused.body.detail, "The last day this trip can leave has passed. Choose another trip.");
  assert.equal(f.store.anchorTrips.get(ended.id)!.reservedKg, 0);
  assert.equal(f.store.shipments.size, 0);

  const lastDay = publish(f, 0);
  assert.equal((await f.book(f.tokens.shipperA, { anchorTripId: lastDay.id, ...nearTheLane })).status, 201, "the last leaving day still books");
});

test("a trip with a shipment on it stays on the list after its window, so the shipper's shipment keeps its route name", async t => {
  const f = await httpFixture(t);
  const trip = publish(f, 0);
  const booked = await f.book(f.tokens.shipperA, { anchorTripId: trip.id, ...nearTheLane });
  assert.equal(booked.status, 201, JSON.stringify(booked.body));
  // The window passes with the booking on it.
  const stored = f.store.anchorTrips.get(trip.id)!;
  f.store.anchorTrips.set(trip.id, { ...stored, windowStart: firstLeavingDay(-2), windowEnd: lastLeavingDay(-1) });

  const listed = (await f.request("/anchor-trips")).body.trips as { id: string; leaveWindowEnded: boolean; status: string }[];
  const row = listed.find((t) => t.id === trip.id);
  assert.ok(row, "still listed");
  assert.equal(row.leaveWindowEnded, true, "and marked, so Book a trip can leave it out");
  assert.equal(row.status, "OPEN", "no status changes");
  assert.ok(!(await searchedIds(f)).includes(trip.id), "route search still leaves it out");
  assert.equal((await f.book(f.tokens.shipperA, { anchorTripId: trip.id, ...nearTheLane })).body.error, "anchor_trip_leave_window_ended");
});

test("the carrier's own list keeps an ended trip and marks it; a carrier office cancels it in one call when nothing is booked", async t => {
  const f = await httpFixture(t);
  const ended = publish(f, -1);
  const mine = (await f.request("/v1/pilot/anchor-trips", "GET", undefined, f.tokens.carrierA)).body.trips as { id: string; leaveWindowEnded: boolean; status: string }[];
  const row = mine.find((t) => t.id === ended.id);
  assert.ok(row, "the carrier still sees it");
  assert.equal(row.leaveWindowEnded, true);
  assert.equal(row.status, "OPEN");

  const cancelled = await f.request(`/v1/pilot/anchor-trips/${ended.id}/cancel`, "POST", {}, f.tokens.carrierA);
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));
  assert.equal(cancelled.body.trip.status, "CANCELLED");
  assert.equal(f.store.anchorTrips.get(ended.id)!.status, "CANCELLED");
});
