// The Load Board's rules (owner, 4 Nov 2026): what a shipper may post, how a carrier answers with an ordinary route,
// and what booking, a booking that falls through, and the end of the pickup window do to a posted load.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { UNPAID_BOOKING_EXPIRY_MS, UNPAID_BOOKING_GRACE_MS } from "../../../config.ts";
import { distanceBetweenGeoPointsKm } from "../../../services.ts";
import { createIntegrationApiKey, createIntegrationLoad } from "../../../integrationServices.ts";
import { resolveIntegrationAuth } from "../../../integrationAuth.ts";
import { indiaDay, loadBoardFixture, loadBody } from "./loadBoardSetup.ts";

type Fixture = Awaited<ReturnType<typeof loadBoardFixture>>;

async function postedLoadId(fx: Fixture, extra: Record<string, unknown> = {}): Promise<string> {
  const posted = await fx.post(loadBody(extra));
  assert.equal(posted.status, 201, JSON.stringify(posted.body));
  return posted.body.load.id as string;
}

async function routeFor(fx: Fixture, loadId: string, extra: Record<string, unknown> = {}): Promise<string> {
  const made = await fx.makeRoute(loadId, fx.tokens.carrierB, extra);
  assert.equal(made.status, 201, JSON.stringify(made.body));
  return made.body.trip.id as string;
}

/** Books a route as today's booking flow does: the load's weight and map points. */
function bookRoute(fx: Fixture, tripId: string, token: string, weightKg = 400, body: { from: { lat: number; lng: number }; to: { lat: number; lng: number } } = loadBody()) {
  return fx.f.request("/shipments/book", "POST", {
    anchorTripId: tripId, customerOrgName: "ignored", weightKg, pickupAddress: "Synthetic pickup", dropAddress: "Synthetic drop",
    pickup: { lat: body.from.lat, lng: body.from.lng }, drop: { lat: body.to.lat, lng: body.to.lng },
  }, token);
}

test("posting refuses pickup days outside the rules, a bad package size and a town that is not a town name", async t => {
  const fx = await loadBoardFixture(t);
  const refused = async (extra: Record<string, unknown>, error: string) => {
    const out = await fx.post(loadBody(extra));
    assert.deepEqual([out.status, out.body.error], [400, error], JSON.stringify(extra));
  };
  await refused({ earliestPickupDate: indiaDay(-1), latestPickupDate: indiaDay(0) }, "earliest_pickup_in_the_past");
  await refused({ earliestPickupDate: indiaDay(8), latestPickupDate: indiaDay(8) }, "earliest_pickup_too_far_ahead");
  await refused({ earliestPickupDate: indiaDay(2), latestPickupDate: indiaDay(1) }, "latest_pickup_before_earliest");
  await refused({ earliestPickupDate: indiaDay(0), latestPickupDate: indiaDay(4) }, "pickup_window_too_long");
  await refused({ earliestPickupDate: "2026-02-30", latestPickupDate: "2026-03-01" }, "invalid_earliestPickupDate");
  await refused({ packages: { kind: "SIZES", count: 0, length: 1, width: 1, height: 1, unit: "INCHES" } }, "invalid_packages");
  await refused({ packages: { kind: "SIZES", count: 2, length: 1, width: 1, height: 1, unit: "FEET" } }, "invalid_packages");
  await refused({ packages: { kind: "TOTAL_VOLUME", volume: -1, unit: "CUBIC_METRES" } }, "invalid_packages");
  await refused({ from: { city: "", lat: 1, lng: 1 } }, "invalid_from");
  await refused({ to: { city: "Mumbai", lat: 200, lng: 1 } }, "invalid_to");
  await refused({ from: { city: "Pune call 9800000010", lat: 18.52, lng: 73.85 } }, "invalid_from");
  await refused({ to: { city: "Plot 22, MIDC Bhosari", lat: 19.07, lng: 72.87 } }, "invalid_to");
  await refused({ weightKg: 0 }, "invalid_weightKg");
  assert.equal(fx.f.store.postedLoads.size, 0, "nothing refused was kept");

  const edges = await fx.post(loadBody({ earliestPickupDate: indiaDay(7), latestPickupDate: indiaDay(10), packages: { kind: "TOTAL_VOLUME", volume: 12.5, unit: "CUBIC_METRES" } }));
  assert.equal(edges.status, 201, "7 days ahead and a 3-day window are allowed");
  assert.deepEqual(edges.body.load.packages, { kind: "TOTAL_VOLUME", volume: 12.5, unit: "CUBIC_METRES" }, "kept as entered, with its unit");
  assert.equal(edges.body.load.state, "OPEN");
  const townNames = await fx.post(loadBody({ from: { city: "Pimpri-Chinchwad", lat: 18.62, lng: 73.8 }, to: { city: "पुणे", lat: 18.52, lng: 73.85 } }));
  assert.equal(townNames.status, 201, "a town name may have a hyphen, or be written in Devanagari");
});

test("a company may have at most 10 open loads, and posting is held at 10 an hour per user", async t => {
  const fx = await loadBoardFixture(t);
  const ids: string[] = [];
  for (let i = 0; i < 10; i++) ids.push(await postedLoadId(fx));
  const eleventh = await fx.post();
  assert.deepEqual([eleventh.status, eleventh.body.error, eleventh.body.limit], [409, "too_many_open_loads", 10]);

  const withdrawn = await fx.f.request(`/v1/posted-loads/${ids[0]}/withdraw`, "POST", {}, fx.tokens.shipperA);
  assert.equal(withdrawn.status, 200);
  const held = await fx.post();
  assert.equal(held.status, 429, "the eleventh post in an hour is held even with room");
  assert.equal(held.body.error, "rate_limited");
});

test("a carrier may make at most 20 routes for posted loads an hour; a refused attempt does not count", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  assert.equal((await fx.makeRoute(loadId, fx.tokens.carrierB, { capacityKg: 399 })).status, 400);
  for (let i = 0; i < 20; i++) await routeFor(fx, loadId);
  const held = await fx.makeRoute(loadId);
  assert.deepEqual([held.status, held.body.error], [429, "rate_limited"]);
  assert.equal(fx.f.store.postedLoads.get(loadId)?.routes.length, 20);
});

test("withdraw closes an open load once, takes it off the board and keeps it in My loads", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const out = await fx.f.request(`/v1/posted-loads/${loadId}/withdraw`, "POST", {}, fx.tokens.shipperA);
  assert.equal(out.status, 200);
  assert.equal(out.body.load.state, "WITHDRAWN");
  assert.equal(typeof out.body.load.closedAtUtcMs, "number");
  const again = await fx.f.request(`/v1/posted-loads/${loadId}/withdraw`, "POST", {}, fx.tokens.shipperA);
  assert.deepEqual([again.status, again.body.error], [409, "load_not_open"]);
  assert.deepEqual((await fx.board(fx.tokens.carrierB)).body.loads, []);
  const mine = (await fx.f.request("/v1/posted-loads", "GET", undefined, fx.tokens.shipperA)).body.loads;
  assert.deepEqual(mine.map((load: any) => [load.id, load.state]), [[loadId, "WITHDRAWN"]]);
  assert.equal((await fx.makeRoute(loadId)).status, 409, "no route for a withdrawn load");
});

test("the board lists open loads only, the soonest pickup first", async t => {
  const fx = await loadBoardFixture(t);
  const later = await postedLoadId(fx, { earliestPickupDate: indiaDay(3), latestPickupDate: indiaDay(4) });
  const sooner = await postedLoadId(fx, { earliestPickupDate: indiaDay(1), latestPickupDate: indiaDay(1) });
  const gone = await postedLoadId(fx);
  await fx.f.request(`/v1/posted-loads/${gone}/withdraw`, "POST", {}, fx.tokens.shipperA);
  assert.deepEqual((await fx.board(fx.tokens.dispatcher)).body.loads.map((load: any) => load.id), [sooner, later]);
});

test("a trip for a load needs room for its weight; NaviG8r sets its ends from the load whatever the carrier sends", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const refused = async (extra: Record<string, unknown>, status: number, error: string) => {
    const out = await fx.makeRoute(loadId, fx.tokens.carrierB, extra);
    assert.deepEqual([out.status, out.body.error], [status, error], JSON.stringify(extra));
  };
  await refused({ capacityKg: 399 }, 400, "route_too_small_for_load");
  await refused({ postedLoadId: "load_unknown" }, 404, "posted_load_not_found");
  assert.equal(fx.f.store.anchorTrips.size, 1, "a refused route is never made (the fixture's own trip only)");

  // The load's points 18.5204, 73.8567 and 19.076, 72.8777 rounded to 0.05 degrees.
  const ends = { originCity: "Pune", destCity: "Mumbai", origin: { lat: 18.5, lng: 73.85 }, destination: { lat: 19.1, lng: 72.9 } };
  const tripEnds = (tripId: string) => {
    const trip = fx.f.store.anchorTrips.get(tripId)!;
    return { originCity: trip.originCity, destCity: trip.destCity, origin: trip.origin, destination: trip.destination };
  };
  const elsewhere = await routeFor(fx, loadId, { originCity: "Nashik", destCity: "Surat", origin: { lat: 20, lng: 73.79, label: "Nashik" }, destination: { lat: 21.17, lng: 72.83 } });
  assert.deepEqual(tripEnds(elsewhere), ends, "the carrier's towns and points are ignored");
  const placeless = await fx.f.request("/v1/pilot/anchor-trips", "POST", {
    orgId: fx.carrierOrgId, postedLoadId: loadId, windowStart: `${indiaDay(1)}T09:00:00.000Z`, windowEnd: `${indiaDay(1)}T18:00:00.000Z`, vehicleClass: "MEDIUM", capacityKg: 1000,
  }, fx.tokens.carrierB);
  assert.equal(placeless.status, 201, JSON.stringify(placeless.body));
  assert.deepEqual(tripEnds(placeless.body.trip.id), ends, "a trip sent with no places at all gets the same ends");

  const load = fx.f.store.postedLoads.get(loadId)!;
  assert.deepEqual(load.routes.map((route) => [route.tripId, route.carrierOrgId]), [[elsewhere, fx.carrierOrgId], [placeless.body.trip.id, fx.carrierOrgId]], "recorded on the load");
  assert.equal(load.state, "OPEN", "still on the board: other carriers may make routes too");
});

test("a trip for a load must leave, by India date, on one of the load's pickup days", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx, { earliestPickupDate: indiaDay(1), latestPickupDate: indiaDay(3) });
  const leaving = (windowStart: string) => fx.makeRoute(loadId, fx.tokens.carrierB, { windowStart, windowEnd: `${indiaDay(4)}T23:59:59+05:30` });
  for (const [windowStart, why] of [
    [`${indiaDay(0)}T23:59:59+05:30`, "the last second of the day before"],
    [`${indiaDay(4)}T00:00:00+05:30`, "the first second of the day after"],
  ] as const) {
    const out = await leaving(windowStart);
    assert.deepEqual([out.status, out.body.error, out.body.earliestPickupDate, out.body.latestPickupDate],
      [400, "trip_leaves_outside_pickup_days", indiaDay(1), indiaDay(3)], why);
  }
  const unreadable = await leaving("not a time");
  assert.deepEqual([unreadable.status, unreadable.body.error], [400, "invalid_windowStart"]);
  assert.equal(fx.f.store.postedLoads.get(loadId)?.routes.length, 0, "no refused trip was made");

  for (const [windowStart, why] of [
    [`${indiaDay(1)}T00:00:00+05:30`, "the first second of the first pickup day"],
    [`${indiaDay(3)}T23:59:59+05:30`, "the last second of the last pickup day"],
  ] as const) {
    const out = await leaving(windowStart);
    assert.equal(out.status, 201, `${why}: ${JSON.stringify(out.body)}`);
  }
});

test("a load whose points sit near a rounding edge: the trip ends are under 4 km away, and the shipper books it", async t => {
  const fx = await loadBoardFixture(t);
  // 0.0249 degrees from a 0.05 line on both axes: about as far as rounding can move a point.
  const edge = { from: { city: "Pune", lat: 18.5249, lng: 73.8749 }, to: { city: "Mumbai", lat: 19.0749, lng: 72.8749 } };
  const loadId = await postedLoadId(fx, edge);
  const tripId = await routeFor(fx, loadId);
  const trip = fx.f.store.anchorTrips.get(tripId)!;
  assert.deepEqual([trip.origin, trip.destination], [{ lat: 18.5, lng: 73.85 }, { lat: 19.05, lng: 72.85 }]);
  for (const [point, end] of [[edge.from, trip.origin!], [edge.to, trip.destination!]] as const) {
    const km = distanceBetweenGeoPointsKm(point, end);
    assert.ok(km > 3.5 && km < 4, `${km} km: near the worst case, inside booking's 15 km`);
  }
  const booked = await bookRoute(fx, tripId, fx.tokens.shipperA, 400, edge);
  assert.equal(booked.status, 201, JSON.stringify(booked.body));
  assert.equal(fx.f.store.postedLoads.get(loadId)?.state, "BOOKED");
});

test("a route made for a load tells the posting shipper, not the carrier who made it, with no amount", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  await routeFor(fx, loadId);
  const [notice, ...more] = (await fx.notices(fx.tokens.shipperA)).filter((n) => n.eventKey === "posted_load.route_made");
  assert.ok(notice);
  assert.equal(more.length, 0);
  assert.equal(notice.data.title, "A carrier added a trip for your load");
  assert.equal(notice.data.body, `Synthetic Carrier B added a trip from Pune to Mumbai, leaves ${shortDay(indiaDay(1))}. Open My loads to book it.`);
  assert.ok(!/Paise|₹/.test(JSON.stringify(notice)));
  for (const who of ["carrierB", "dispatcher", "shipperB", "driver"] as const) {
    assert.deepEqual((await fx.notices(fx.tokens[who])).filter((n) => n.eventKey === "posted_load.route_made"), [], who);
  }
});

test("only the poster's own booking books the load; another shipper may book leftover room on the route", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const tripId = await routeFor(fx, loadId);
  const other = await routeFor(fx, loadId, { capacityKg: 500 });

  const byOther = await bookRoute(fx, tripId, fx.tokens.shipperB, 100);
  assert.equal(byOther.status, 201, JSON.stringify(byOther.body));
  assert.equal(fx.f.store.postedLoads.get(loadId)?.state, "OPEN", "another shipper's booking leaves the load alone");

  const mine = await bookRoute(fx, tripId, fx.tokens.shipperA);
  assert.equal(mine.status, 201, JSON.stringify(mine.body));
  assert.equal(typeof mine.body.shipment.grossPaise, "number", "priced by today's formula at booking");
  const load = fx.f.store.postedLoads.get(loadId)!;
  assert.equal(load.state, "BOOKED");
  assert.equal(load.booking?.shipmentId, mine.body.shipment.id);
  assert.deepEqual((await fx.board(fx.tokens.carrierB)).body.loads, [], "the booked load leaves the board");
  assert.equal(fx.f.store.anchorTrips.get(other)?.status, "OPEN", "the other route stays an ordinary route");
  assert.deepEqual((await fx.notices(fx.tokens.carrierB)).filter((n) => n.eventKey.startsWith("posted_load.") && n.eventKey !== "posted_load.new"), [], "no carrier is told the load was booked");
  const listed = (await fx.f.request("/v1/posted-loads", "GET", undefined, fx.tokens.shipperA)).body.loads[0];
  assert.equal(listed.routes.every((route: any) => route.canBook === false), true, "a booked load offers no more Book buttons");
  assert.deepEqual(listed.routes.map((route: any) => [route.tripId, route.whyNotBookable]), [[tripId, "YOU_BOOKED_IT"], [other, "LOAD_CLOSED"]],
    "each route says why it has no Book button: the one booked, and one still open but for a closed load");
});

test("a route for an open load with too little room left says so", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const tripId = await routeFor(fx, loadId);
  assert.equal((await bookRoute(fx, tripId, fx.tokens.shipperB, 700)).status, 201);
  const [route] = (await fx.f.request("/v1/posted-loads", "GET", undefined, fx.tokens.shipperA)).body.loads[0].routes;
  assert.deepEqual([route.canBook, route.whyNotBookable], [false, "NOT_ENOUGH_ROOM"]);
  const open = await routeFor(fx, loadId);
  const bookable = (await fx.f.request("/v1/posted-loads", "GET", undefined, fx.tokens.shipperA)).body.loads[0].routes.find((row: any) => row.tripId === open);
  assert.equal("whyNotBookable" in bookable, false, "a bookable route gives no reason");
});

/** As the unpaid-booking tests do: the booking is old and its Razorpay checkout never finished. */
function leaveUnpaid(fx: Fixture, shipmentId: string): void {
  const shipment = fx.f.store.shipments.get(shipmentId)!;
  fx.f.store.shipments.set(shipmentId, { ...shipment, createdAtUtcMs: Date.now() - UNPAID_BOOKING_EXPIRY_MS - UNPAID_BOOKING_GRACE_MS - 1000 });
  const payment = fx.f.store.payments.get(shipment.paymentId)!;
  fx.f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", status: "CREATED", razorpayOrderId: `order_${shipmentId}` });
}

test("a booking not paid in time puts the load back on the board while its window is open", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const tripId = await routeFor(fx, loadId);
  const booked = await bookRoute(fx, tripId, fx.tokens.shipperA);
  leaveUnpaid(fx, booked.body.shipment.id);

  const board = await fx.board(fx.tokens.carrierB);
  assert.equal(fx.f.store.shipments.get(booked.body.shipment.id)?.status, "FAILED_CARRIER_REFUNDED", "the unpaid booking closed");
  assert.deepEqual(board.body.loads.map((load: any) => load.id), [loadId], "the load is open again, in the same request");
  const load = fx.f.store.postedLoads.get(loadId)!;
  assert.deepEqual([load.state, load.booking, load.closedAtUtcMs], ["OPEN", undefined, undefined]);
  assert.ok([...fx.f.store.auditEvents.values()].some((row) => row.action === "POSTED_LOAD_REOPENED" && row.actorUserId === "system:posted-load-sweep"));
});

test("another live booking keeps the load booked when the one it recorded is not paid", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const firstTrip = await routeFor(fx, loadId);
  const secondTrip = await routeFor(fx, loadId);
  const first = await bookRoute(fx, firstTrip, fx.tokens.shipperA);
  const second = await bookRoute(fx, secondTrip, fx.tokens.shipperA);
  assert.equal(fx.f.store.postedLoads.get(loadId)?.booking?.shipmentId, first.body.shipment.id, "the first booking is the one My loads recorded");
  leaveUnpaid(fx, first.body.shipment.id);
  // The pickup days are already over. That must not expire a load that still has a booking.
  const posted = fx.f.store.postedLoads.get(loadId)!;
  fx.f.store.postedLoads.set(loadId, { ...posted, earliestPickupDate: indiaDay(-3), latestPickupDate: indiaDay(-1) });

  assert.deepEqual((await fx.board(fx.tokens.carrierB)).body.loads, [], "a booked load stays off the board");
  const load = fx.f.store.postedLoads.get(loadId)!;
  assert.equal(fx.f.store.shipments.get(first.body.shipment.id)?.status, "FAILED_CARRIER_REFUNDED");
  assert.deepEqual([load.state, load.booking?.shipmentId], ["BOOKED", second.body.shipment.id]);
  assert.equal(typeof load.closedAtUtcMs, "number");
  const mine = (await fx.f.request("/v1/posted-loads", "GET", undefined, fx.tokens.shipperA)).body.loads[0];
  assert.equal(mine.booking.shipmentId, second.body.shipment.id, "My loads opens the booking that is still live");
  assert.ok([...fx.f.store.auditEvents.values()].some((row) =>
    row.action === "POSTED_LOAD_BOOKING_KEPT" && row.actorUserId === "system:posted-load-sweep"
    && row.previousState === first.body.shipment.id && row.newState === second.body.shipment.id));
});

test("another company's booking of a route does not keep the load when the posting company's booking falls through", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const firstTrip = await routeFor(fx, loadId);
  const secondTrip = await routeFor(fx, loadId);
  const first = await bookRoute(fx, firstTrip, fx.tokens.shipperA);
  assert.equal((await bookRoute(fx, secondTrip, fx.tokens.shipperB)).status, 201);
  leaveUnpaid(fx, first.body.shipment.id);

  const board = await fx.board(fx.tokens.carrierB);
  assert.deepEqual(board.body.loads.map((load: any) => load.id), [loadId], "the other company's booking leaves this load open");
  assert.deepEqual([fx.f.store.postedLoads.get(loadId)?.state, fx.f.store.postedLoads.get(loadId)?.booking], ["OPEN", undefined]);
});

test("a booking that falls through after the pickup window closes the load as expired", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const tripId = await routeFor(fx, loadId);
  const booked = await bookRoute(fx, tripId, fx.tokens.shipperA);
  leaveUnpaid(fx, booked.body.shipment.id);
  const load = fx.f.store.postedLoads.get(loadId)!;
  fx.f.store.postedLoads.set(loadId, { ...load, earliestPickupDate: indiaDay(-3), latestPickupDate: indiaDay(-1) });

  assert.deepEqual((await fx.board(fx.tokens.carrierB)).body.loads, []);
  assert.equal(fx.f.store.postedLoads.get(loadId)?.state, "EXPIRED");
});

test("an open load expires the day after its latest pickup day, and is kept", async t => {
  const fx = await loadBoardFixture(t);
  const stale = await postedLoadId(fx);
  const fresh = await postedLoadId(fx);
  const load = fx.f.store.postedLoads.get(stale)!;
  fx.f.store.postedLoads.set(stale, { ...load, earliestPickupDate: indiaDay(-2), latestPickupDate: indiaDay(-1) });
  const today = fx.f.store.postedLoads.get(fresh)!;
  fx.f.store.postedLoads.set(fresh, { ...today, earliestPickupDate: indiaDay(-1), latestPickupDate: indiaDay(0) });

  assert.deepEqual((await fx.board(fx.tokens.carrierB)).body.loads.map((row: any) => row.id), [fresh], "a load whose last pickup day is today stays");
  assert.equal(fx.f.store.postedLoads.get(stale)?.state, "EXPIRED");
  assert.equal(typeof fx.f.store.postedLoads.get(stale)?.closedAtUtcMs, "number");
  const mine = (await fx.f.request("/v1/posted-loads", "GET", undefined, fx.tokens.shipperA)).body.loads;
  assert.equal(mine.find((row: any) => row.id === stale)?.state, "EXPIRED", "closed loads are kept for the counts");
});

test("load alerts: on by default, changed only for yourself, and off means no notice and no push", async t => {
  const fx = await loadBoardFixture(t);
  withPushQueue(t);
  assert.deepEqual((await fx.f.request("/v1/me/settings", "GET", undefined, fx.tokens.dispatcher)).body, { loadAlerts: true });
  assert.equal((await fx.f.request("/v1/me/settings", "PATCH", { loadAlerts: "no" }, fx.tokens.dispatcher)).status, 400);
  assert.equal((await fx.f.request("/v1/me/settings", "GET")).status, 401);
  assert.deepEqual((await fx.f.request("/v1/me/settings", "PATCH", { loadAlerts: false }, fx.tokens.dispatcher)).body, { loadAlerts: false });
  assert.deepEqual((await fx.f.request("/v1/me/settings", "GET", undefined, fx.tokens.carrierB)).body, { loadAlerts: true }, "the owner's own stays on");

  await postedLoadId(fx);
  const dispatcherId = [...fx.f.store.users.values()].find((u) => u.phone === "8000000021")!.id;
  const intents = [...fx.f.store.pushIntents.values()].map((intent) => intent.recipientUserId);
  assert.ok(intents.includes(fx.f.carrierB.user.id), "the owner's alert is queued for push");
  assert.ok(!intents.includes(dispatcherId), "nothing queued for the dispatcher");
  assert.ok(!intents.includes(fx.driver.user.id), "nor the driver");
  assert.deepEqual((await fx.notices(fx.tokens.dispatcher)).filter((n) => n.eventKey === "posted_load.new"), []);
});

test("a Load Board notice opens My loads for the shipper and the board for the carrier, and leaves once its reader leaves the office", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  await routeFor(fx, loadId);
  const carrierNotice = (await fx.notices(fx.tokens.dispatcher)).find((n) => n.eventKey === "posted_load.new")!;
  const shipperNotice = (await fx.notices(fx.tokens.shipperA)).find((n) => n.eventKey === "posted_load.route_made")!;

  const opened = await fx.f.request(`/v1/notifications/${carrierNotice.id}/open`, "POST", {}, fx.tokens.dispatcher);
  assert.deepEqual(opened.body, { organizationId: fx.carrierOrgId, postedLoadId: loadId, screen: "LOAD_BOARD" });
  const shipperOpened = await fx.f.request(`/v1/notifications/${shipperNotice.id}/open`, "POST", {}, fx.tokens.shipperA);
  assert.deepEqual(shipperOpened.body, { organizationId: fx.f.shipperA.org.id, postedLoadId: loadId, screen: "MY_LOADS" });

  const inbox = await fx.f.request("/v1/notifications/shipments", "GET", undefined, fx.tokens.shipperA);
  const row = inbox.body.shipments.find((item: any) => item.postedLoadId === loadId);
  assert.deepEqual({ loadRoute: row?.loadRoute, notificationId: row?.notificationId, unreadCount: row?.unreadCount }, { loadRoute: "Pune to Mumbai", notificationId: shipperNotice.id, unreadCount: 1 });
  assert.equal((await fx.f.request(`/v1/notifications/${shipperNotice.id}/read`, "PATCH", {}, fx.tokens.shipperA)).status, 200);

  // Made a driver: the board is no longer theirs, so neither is its notice.
  const dispatcherId = [...fx.f.store.users.values()].find((u) => u.phone === "8000000021")!.id;
  const key = `${dispatcherId}:${fx.carrierOrgId}`;
  fx.f.store.memberships.set(key, { ...fx.f.store.memberships.get(key)!, role: "DRIVER" });
  assert.deepEqual((await fx.notices(fx.tokens.dispatcher)).filter((n) => n.postedLoadId), []);
  assert.equal((await fx.f.request(`/v1/notifications/${carrierNotice.id}/open`, "POST", {}, fx.tokens.dispatcher)).status, 404);
});

test("staff read every posted load with its state and times, and no amount", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  await routeFor(fx, loadId);
  const out = await fx.f.request("/ops/posted-loads", "GET", undefined, fx.tokens.ops);
  assert.equal(out.status, 200);
  const [row] = out.body.loads;
  assert.deepEqual([row.id, row.state, row.shipperName, row.routes.length, row.routes[0].carrierName], [loadId, "OPEN", "Synthetic Shipper A", 1, "Synthetic Carrier B"]);
  assert.equal(typeof row.postedAtUtcMs, "number");
  assert.ok(!/Paise|price|note/i.test(JSON.stringify(out.body)));
  assert.equal((await fx.f.request("/ops/posted-loads", "GET", undefined, fx.tokens.finance)).status, 200, "every operator role reads it");
  for (const who of ["shipperA", "carrierB", "dispatcher"] as const) {
    assert.equal((await fx.f.request("/ops/posted-loads", "GET", undefined, fx.tokens[who])).status, 403, who);
  }
});

const SHORT_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function shortDay(day: string): string {
  const [, month, date] = day.split("-").map(Number);
  return `${date} ${SHORT_MONTHS[month! - 1]}`;
}

function withPushQueue(t: TestContext): void {
  const saved = process.env.PUSH_ENQUEUE_ENABLED;
  process.env.PUSH_ENQUEUE_ENABLED = "1";
  t.after(() => {
    if (saved === undefined) delete process.env.PUSH_ENQUEUE_ENABLED;
    else process.env.PUSH_ENQUEUE_ENABLED = saved;
  });
}

test("a booking from the posting company's ERP connection books the load too", async t => {
  const fx = await loadBoardFixture(t);
  const loadId = await postedLoadId(fx);
  const tripId = await routeFor(fx, loadId);
  const { token } = createIntegrationApiKey(fx.f.store, fx.f.shipperA.org.id);
  const ctx = resolveIntegrationAuth(fx.f.store, { bearerToken: token });
  const body = loadBody();
  const { shipment } = await createIntegrationLoad(fx.f.store, ctx, {
    externalLoadId: "ERP-LOAD-1", weightKg: 400, pickupAddress: "Synthetic pickup", dropAddress: "Synthetic drop",
    pickup: { lat: body.from.lat, lng: body.from.lng }, drop: { lat: body.to.lat, lng: body.to.lng }, lanePreference: "explicit", anchorTripId: tripId,
  });
  const load = fx.f.store.postedLoads.get(loadId)!;
  assert.deepEqual([load.state, load.booking?.shipmentId], ["BOOKED", shipment.id]);
  assert.ok([...fx.f.store.auditEvents.values()].some((row) => row.action === "POSTED_LOAD_BOOKED" && row.actorUserId === "system:erp-booking"),
    "an ERP request has no signed-in user, so the audit row names the ERP booking");
});
