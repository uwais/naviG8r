import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  acceptCarrierShipment,
  assertOpsAgent,
  bookShipment,
  grantOpsAdmin,
  publishAnchorTrip,
  registerSoloOwnerOperatorDriver,
  releasePaymentAndDeliver,
  startAnchorTripAsPilot,
  submitDriverPod,
  registerCustomerOrgAdmin,
  ApiError,
} from "./services.ts";

function seedBookedShipment(store: ReturnType<typeof createStore>) {
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Carrier Driver",
    phone: "9100000000",
    orgDisplayName: "Carrier One",
    vehicleRegistrationNumber: "HR01",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  const trip = publishAnchorTrip(store, {
    carrierId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME",
    weightKg: 100,
    pickupAddress: "A",
    dropAddress: "B",
  });
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, status: "AUTHORIZED", razorpayPaymentId: "pay_test_1" });
  const booked = acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });
  return { driver, trip, shipment: booked };
}

function seedInProgressShipment(store: ReturnType<typeof createStore>) {
  const seeded = seedBookedShipment(store);
  startAnchorTripAsPilot(store, { userId: seeded.driver.user.id, tripId: seeded.trip.id });
  return seeded;
}

test("submitDriverPod: driver on carrier org moves BOOKED to PENDING_RELEASE", () => {
  const store = createStore();
  const { driver, shipment } = seedInProgressShipment(store);

  const out = submitDriverPod(store, {
    shipmentId: shipment.id,
    userId: driver.user.id,
    notes: "Left at gate",
  });
  assert.equal(out.status, "PENDING_RELEASE");
  assert.equal(out.podSubmittedByUserId, driver.user.id);
  assert.equal(out.podNotes, "Left at gate");
});

test("submitDriverPod: rejects POD before trip start", () => {
  const store = createStore();
  const { driver, shipment, trip } = seedBookedShipment(store);
  assert.equal(store.anchorTrips.get(trip.id)?.status, "OPEN");
  assert.throws(
    () => submitDriverPod(store, { shipmentId: shipment.id, userId: driver.user.id }),
    (e: unknown) => e instanceof ApiError && (e as ApiError).message === "trip_not_started_for_pod",
  );
});

test("submitDriverPod: customer user forbidden", () => {
  const store = createStore();
  const { shipment } = seedInProgressShipment(store);
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "Buyer",
    phone: "9100000002",
    orgDisplayName: "ACME Buyer",
  });
  assert.throws(
    () => submitDriverPod(store, { shipmentId: shipment.id, userId: cust.user.id }),
    (e: Error) => e.message === "forbidden",
  );
});

test("releasePaymentAndDeliver: requires PENDING_RELEASE then DELIVERED", async () => {
  const store = createStore();
  const { driver, shipment } = seedInProgressShipment(store);

  submitDriverPod(store, { shipmentId: shipment.id, userId: driver.user.id });

  const ops = registerCustomerOrgAdmin(store, {
    fullName: "Ops",
    phone: "9100000099",
    orgDisplayName: "Ops Co",
  });
  grantOpsAdmin(store, { phone: ops.user.phone });
  assertOpsAgent(store, ops.user.id);

  const out = await releasePaymentAndDeliver(store, { shipmentId: shipment.id });
  assert.equal(out.shipment.status, "DELIVERED");
  assert.ok(out.ledgerLine.id);
});

test("assertOpsAgent rejects non-ops user", () => {
  const store = createStore();
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "X",
    phone: "9100000088",
    orgDisplayName: "X Org",
  });
  assert.throws(() => assertOpsAgent(store, cust.user.id), (e: Error) => e.message === "forbidden");
});
