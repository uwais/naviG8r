import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  assertOpsAgent,
  bookShipment,
  createCarrier,
  grantOpsAdmin,
  publishAnchorTrip,
  registerSoloOwnerOperatorDriver,
  releasePaymentAndDeliver,
  submitDriverPod,
  registerCustomerOrgAdmin,
} from "./services.ts";

function seedBookedShipment(store: ReturnType<typeof createStore>) {
  const carrier = createCarrier(store, "Carrier One");
  const trip = publishAnchorTrip(store, {
    carrierId: carrier.id,
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
  return { carrier, trip, shipment };
}

test("submitDriverPod: driver on carrier org moves BOOKED to PENDING_RELEASE", () => {
  const store = createStore();
  const { shipment } = seedBookedShipment(store);
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9100000001",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR01",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  store.shipments.get(shipment.id)!.carrierId = driver.org.id;
  const s = store.shipments.get(shipment.id)!;
  store.shipments.set(s.id, { ...s, carrierId: driver.org.id });

  const out = submitDriverPod(store, {
    shipmentId: shipment.id,
    userId: driver.user.id,
    notes: "Left at gate",
  });
  assert.equal(out.status, "PENDING_RELEASE");
  assert.equal(out.podSubmittedByUserId, driver.user.id);
  assert.equal(out.podNotes, "Left at gate");
});

test("submitDriverPod: customer user forbidden", () => {
  const store = createStore();
  const { shipment } = seedBookedShipment(store);
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
  const { shipment } = seedBookedShipment(store);
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9100000011",
    orgDisplayName: "Ravi2",
    vehicleRegistrationNumber: "HR02",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  const s0 = store.shipments.get(shipment.id)!;
  store.shipments.set(s0.id, { ...s0, carrierId: driver.org.id });

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

test("releasePaymentAndDeliver: concurrent releases accrue a single ledger line", async () => {
  const store = createStore();
  const { shipment } = seedBookedShipment(store);
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9100000021",
    orgDisplayName: "Ravi3",
    vehicleRegistrationNumber: "HR03",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  const s0 = store.shipments.get(shipment.id)!;
  store.shipments.set(s0.id, { ...s0, carrierId: driver.org.id });

  submitDriverPod(store, { shipmentId: shipment.id, userId: driver.user.id });

  const [a, b] = await Promise.all([
    releasePaymentAndDeliver(store, { shipmentId: shipment.id }),
    releasePaymentAndDeliver(store, { shipmentId: shipment.id }),
  ]);

  assert.equal(a.shipment.status, "DELIVERED");
  assert.equal(b.shipment.status, "DELIVERED");
  assert.equal(a.ledgerLine.id, b.ledgerLine.id);
  assert.equal(
    [...store.ledgerLines.values()].filter((line) => line.shipmentId === shipment.id).length,
    1,
  );
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
