import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { createStore } from "./store.ts";
import { MAX_WEIGHT_KG } from "./config.ts";
import {
  computeFreightGrossPaise,
  customerEligibleAnchorTripsPhaseA,
  quoteShipmentMarketplace,
  registerSoloOwnerOperatorDriver,
} from "./services.ts";

const notWeights = [Number.NaN, Number("x"), Number.POSITIVE_INFINITY, -5, 0, MAX_WEIGHT_KG + 1];

test("a booking takes only a positive weight up to the limit, and a refused one holds no room", async t => {
  const f = await httpFixture(t);
  for (const weightKg of ["x", -5, 0, MAX_WEIGHT_KG + 1, "1e400"]) {
    const refused = await f.book(f.tokens.shipperA, { weightKg });
    assert.deepEqual([refused.status, refused.body.error], [400, "invalid_weightKg"], String(weightKg));
  }
  const trip = f.store.anchorTrips.get(f.trip.id)!;
  assert.deepEqual([trip.reservedKg, trip.status], [0, "OPEN"]);
  assert.equal((await f.book(f.tokens.shipperA, { weightKg: 10 })).status, 201);
});

test("a trip is published only with a positive capacity up to the limit", async t => {
  const f = await httpFixture(t);
  const trip = { orgId: f.carrierA.org.id, originCity: "A", destCity: "B", windowStart: "2026-09-16", windowEnd: "2026-09-17", vehicleClass: "MEDIUM" };
  for (const capacityKg of ["x", -1, MAX_WEIGHT_KG + 1]) {
    const refused = await f.request("/v1/pilot/anchor-trips", "POST", { ...trip, capacityKg }, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.error], [400, "invalid_capacityKg"], String(capacityKg));
  }
  assert.equal((await f.request("/v1/pilot/anchor-trips", "POST", { ...trip, capacityKg: MAX_WEIGHT_KG }, f.tokens.carrierA)).status, 201);
});

test("price, matching and truck capacity refuse a weight that is not a positive number up to the limit", () => {
  const store = createStore();
  const point = { lat: 28.4595, lng: 77.0266 };
  for (const weightKg of notWeights) {
    assert.throws(() => computeFreightGrossPaise({ weightKg, vehicleClass: "MEDIUM" }), /invalid_weightKg/, String(weightKg));
    assert.throws(() => customerEligibleAnchorTripsPhaseA(store, { pickup: point, drop: point, weightKg }), /invalid_weightKg/, String(weightKg));
    assert.throws(() => quoteShipmentMarketplace(store, { weightKg }), /invalid_weightKg/, String(weightKg));
    assert.throws(() => registerSoloOwnerOperatorDriver(store, { fullName: "Synthetic", phone: "8000000099", orgDisplayName: "Synthetic", vehicleRegistrationNumber: "TEST-Z", vehicleClass: "MEDIUM", vehicleCapacityKg: weightKg }), /invalid_vehicleCapacityKg/, String(weightKg));
  }
  assert.equal(store.users.size, 0, "no refused sign-up is saved");
});

test("a carrier's rate estimate leaves out sample weights above the limit", async t => {
  const f = await httpFixture(t);
  const ask = (sampleWeightsKg: unknown[]) => f.request("/v1/pilot/rates/estimate", "POST",
    { origin: { lat: 12.97, lng: 77.59 }, destination: { lat: 13.08, lng: 80.27 }, vehicleClass: "MEDIUM", sampleWeightsKg }, f.tokens.carrierA);
  const mixed = await ask([100, MAX_WEIGHT_KG, MAX_WEIGHT_KG + 1, 1e300]);
  assert.equal(mixed.status, 200, JSON.stringify(mixed.body));
  assert.deepEqual(mixed.body.samples.map((s: { weightKg: number }) => s.weightKg), [100, MAX_WEIGHT_KG]);
  const allTooHeavy = await ask([MAX_WEIGHT_KG + 1]);
  assert.equal(allTooHeavy.status, 200);
  assert.deepEqual(allTooHeavy.body.samples.map((s: { weightKg: number }) => s.weightKg), [100, 250, 500], "the usual samples, as for no valid weight");
});
