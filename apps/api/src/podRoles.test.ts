import { asFinance, asUser } from "../test/fixtures.ts";
import { acceptPod } from "./rbac.ts";
import { bookTestShipment, registerCompliantCarrier } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  acceptCarrierShipment,
  assertOpsAgent,

  grantOpsAdmin,
  publishAnchorTrip,

  releasePaymentAndDeliver,
  submitDriverPod,
  registerCustomerOrgAdmin,
} from "./services.ts";

function seedBookedShipment(store: ReturnType<typeof createStore>) {
  const driver = registerCompliantCarrier(store, {
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
  const shipment = bookTestShipment(store, {
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

test("submitDriverPod: driver on carrier org moves BOOKED to PENDING_RELEASE", () => {
  const store = createStore();
  const { driver, shipment } = seedBookedShipment(store);

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
    (e: Error) => e.message === "not_found",
  );
});

test("releasePaymentAndDeliver: requires PENDING_RELEASE then DELIVERED", async () => {
  const store = createStore();
  const { driver, shipment } = seedBookedShipment(store);

  submitDriverPod(store, { shipmentId: shipment.id, userId: driver.user.id });

  await assert.rejects(() => asFinance(store, () => releasePaymentAndDeliver(store, { shipmentId: shipment.id })), /payment_hold_active/);
  const shipper = [...store.memberships.values()].find(m => m.orgId === shipment.customerOrgId)!;
  asUser(store, shipper.userId, () => acceptPod(store, shipment.id));
  const out = await asFinance(store, () => releasePaymentAndDeliver(store, { shipmentId: shipment.id }));
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
