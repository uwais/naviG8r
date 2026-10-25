import { bookTestShipment, registerCompliantCarrier } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { createStore } from "./store.ts";
import { createApp } from "./httpServer.ts";
import {
  customerEligibleAnchorTripsPhaseA,
  publishAnchorTripAsPilotDriver,
  quoteShipmentMarketplace,
  registerSoloOwnerOperatorDriver,
} from "./services.ts";

const GURGAON = { lat: 28.4595, lng: 77.0266, label: "Gurugram" };
const JAIPUR = { lat: 26.9124, lng: 75.7873, label: "Jaipur" };
const BAD_KG: unknown[] = [Number.NaN, "x", -5, 0, Number.POSITIVE_INFINITY, 100_001];

function carrierWithTrip(store: ReturnType<typeof createStore>) {
  const carrier = registerCompliantCarrier(store, {
    fullName: "Weight Carrier",
    phone: "9876500011",
    orgDisplayName: "Weight Carrier",
    vehicleRegistrationNumber: "HR26WT0011",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: carrier.user.id,
    orgId: carrier.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    origin: GURGAON,
    destination: JAIPUR,
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  return { carrier, trip };
}

test("booking weight must be a finite number above zero and at most 100000 kg", () => {
  const store = createStore();
  const { trip } = carrierWithTrip(store);
  for (const weightKg of BAD_KG) {
    assert.throws(
      () => bookTestShipment(store, {
        anchorTripId: trip.id,
        customerOrgName: "Buyer",
        weightKg: weightKg as number,
        pickupAddress: "Gurugram",
        dropAddress: "Jaipur",
        pickup: GURGAON,
        drop: JAIPUR,
      }),
      (e: Error) => e.message === "invalid_weightKg",
      `weightKg ${String(weightKg)}`,
    );
  }
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 0);
  assert.equal(store.shipments.size, 0);
});

test("trip capacity must be a finite number above zero and at most 100000 kg", () => {
  const store = createStore();
  const { carrier } = carrierWithTrip(store);
  for (const capacityKg of BAD_KG) {
    assert.throws(
      () => publishAnchorTripAsPilotDriver(store, {
        userId: carrier.user.id,
        orgId: carrier.org.id,
        originCity: "Gurugram",
        destCity: "Jaipur",
        origin: GURGAON,
        destination: JAIPUR,
        windowStart: "2026-04-24T00:00:00+05:30",
        windowEnd: "2026-04-25T23:59:59+05:30",
        vehicleClass: "MEDIUM",
        capacityKg: capacityKg as number,
      }),
      (e: Error) => e.message === "invalid_capacityKg",
      `capacityKg ${String(capacityKg)}`,
    );
  }
});

test("quotes and trip search refuse a weight outside the allowed range", () => {
  const store = createStore();
  carrierWithTrip(store);
  for (const weightKg of BAD_KG) {
    assert.throws(() => quoteShipmentMarketplace(store, { weightKg: weightKg as number }), /invalid_weightKg/);
    assert.throws(
      () => customerEligibleAnchorTripsPhaseA(store, { pickup: GURGAON, drop: JAIPUR, weightKg: weightKg as number }),
      /invalid_weightKg/,
    );
  }
});

test("truck capacity at sign-up must be a finite number above zero and at most 100000 kg", () => {
  const store = createStore();
  for (const [index, vehicleCapacityKg] of BAD_KG.entries()) {
    assert.throws(
      () => registerSoloOwnerOperatorDriver(store, {
        fullName: "Capacity Driver",
        phone: `98765000${20 + index}`,
        orgDisplayName: "Capacity Carrier",
        vehicleRegistrationNumber: "HR26WT0020",
        vehicleClass: "MEDIUM",
        vehicleCapacityKg: vehicleCapacityKg as number,
      }),
      (e: Error) => e.message === "invalid_vehicleCapacityKg",
      `vehicleCapacityKg ${String(vehicleCapacityKg)}`,
    );
  }
});

test("POST /shipments/quote answers 400 for a weight that is not a number", async (t) => {
  const previousDataFile = process.env.DATA_FILE;
  t.after(() => { process.env.DATA_FILE = previousDataFile; });
  process.env.DATA_FILE = `/tmp/navig8r-weight-checks-${Date.now()}-${Math.random()}.json`;
  const app = await createApp();
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  t.after(() => app.server.close());
  const address = app.server.address();
  assert.ok(address && typeof address === "object");

  const res = await fetch(`http://127.0.0.1:${address.port}/shipments/quote`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ weightKg: "x" }),
  });
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: "invalid_weightKg" });
});
