import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  acceptCarrierShipment,
  bookShipment,
  failCarrierAndRefund,
  inviteCarrierDriver,
  pilotSubmitPayoutSetup,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,
  registerCustomerUser,
  registerSoloOwnerOperatorDriver,
  releasePaymentAndDeliver,
  shipmentVisibleToCustomerUser,
  startAnchorTripAsPilot,
  submitDriverPod,
} from "./services.ts";
import {
  isRazorpayAlreadyCapturedError,
  isRazorpayAlreadyRefundedError,
} from "./razorpayPayments.ts";

test("DRIVER cannot submit carrier payout bank setup", async () => {
  const store = createStore();
  const owner = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9000000101",
    orgDisplayName: "Fleet Co",
    vehicleRegistrationNumber: "HR01AA0101",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const driverUser = registerCustomerUser(store, { fullName: "Driver", phone: "9000000102" });
  inviteCarrierDriver(store, owner.user.id, {
    orgId: owner.org.id,
    phone: driverUser.user.phone,
    role: "DRIVER",
    vehicleRegistrationNumber: "HR01BB0102",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 2000,
  });

  await assert.rejects(
    () =>
      pilotSubmitPayoutSetup(store, driverUser.user.id, {
        orgId: owner.org.id,
        accountHolderName: "Evil Driver",
        ifsc: "HDFC0001234",
        accountNumber: "1234567890",
      }),
    (e: unknown) => e instanceof Error && e.message === "forbidden",
  );

  const ownerOut = await pilotSubmitPayoutSetup(store, owner.user.id, {
    orgId: owner.org.id,
    accountHolderName: "Owner",
    ifsc: "HDFC0001234",
  });
  assert.equal(ownerOut.org.kycStatus, "SUBMITTED");
});

test("failCarrierAndRefund works for PENDING_RELEASE (false POD recovery)", async () => {
  const store = createStore();
  const owner = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9000000201",
    orgDisplayName: "Carrier",
    vehicleRegistrationNumber: "HR01CC0201",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: owner.user.id,
    orgId: owner.org.id,
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
  // MOCK bookings are CAPTURED at create time.
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: owner.user.id });
  startAnchorTripAsPilot(store, { userId: owner.user.id, tripId: trip.id });
  submitDriverPod(store, { shipmentId: shipment.id, userId: owner.user.id });
  assert.equal(store.shipments.get(shipment.id)?.status, "PENDING_RELEASE");

  const out = await failCarrierAndRefund(store, { shipmentId: shipment.id });
  assert.equal(out.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(store.payments.get(shipment.paymentId)?.status, "REFUNDED");
  assert.equal(store.anchorTrips.get(trip.id)?.reservedKg, 0);
});

test("Razorpay already-captured / already-refunded errors are recognized", () => {
  assert.equal(
    isRazorpayAlreadyCapturedError(new Error("bad_request: This payment has already been captured")),
    true,
  );
  assert.equal(isRazorpayAlreadyCapturedError(new Error("network_error")), false);
  assert.equal(
    isRazorpayAlreadyRefundedError(new Error("The payment has been fully refunded already")),
    true,
  );
  assert.equal(isRazorpayAlreadyRefundedError(new Error("insufficient_funds")), false);
});

test("releasePaymentAndDeliver is idempotent when shipment already DELIVERED", async () => {
  const store = createStore();
  const owner = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9000000401",
    orgDisplayName: "Carrier",
    vehicleRegistrationNumber: "HR01EE0401",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: owner.user.id,
    orgId: owner.org.id,
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
    weightKg: 40,
    pickupAddress: "A",
    dropAddress: "B",
  });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: owner.user.id });
  startAnchorTripAsPilot(store, { userId: owner.user.id, tripId: trip.id });
  submitDriverPod(store, { shipmentId: shipment.id, userId: owner.user.id });
  const first = await releasePaymentAndDeliver(store, { shipmentId: shipment.id });
  const second = await releasePaymentAndDeliver(store, { shipmentId: shipment.id });
  assert.equal(first.ledgerLine.id, second.ledgerLine.id);
  assert.equal(
    [...store.ledgerLines.values()].filter((l) => l.shipmentId === shipment.id).length,
    1,
  );
});

test("fleet invite does not overwrite existing driverProfile for another org", () => {
  const store = createStore();
  const solo = registerSoloOwnerOperatorDriver(store, {
    fullName: "Solo",
    phone: "9000000701",
    orgDisplayName: "Solo Transport",
    vehicleRegistrationNumber: "HR01HH0701",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const fleet = registerSoloOwnerOperatorDriver(store, {
    fullName: "Fleet Owner",
    phone: "9000000702",
    orgDisplayName: "Big Fleet",
    vehicleRegistrationNumber: "HR01II0702",
    vehicleClass: "LARGE",
    vehicleCapacityKg: 10000,
  });
  const before = store.driverProfiles.get(solo.user.id)!;
  inviteCarrierDriver(store, fleet.user.id, {
    orgId: fleet.org.id,
    phone: solo.user.phone,
    role: "DRIVER",
    vehicleRegistrationNumber: "HR01JJ0703",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 2000,
  });
  const after = store.driverProfiles.get(solo.user.id)!;
  assert.equal(after.orgId, before.orgId);
  assert.equal(after.primaryVehicleId, before.primaryVehicleId);
  assert.ok(store.memberships.get(`${solo.user.id}:${fleet.org.id}`));
});

test("org displayName alone does not grant shipment visibility or refund rights", () => {
  const store = createStore();
  const owner = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9000000601",
    orgDisplayName: "Carrier",
    vehicleRegistrationNumber: "HR01GG0601",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: owner.user.id,
    orgId: owner.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  // Anonymous booking with a business name string only (no customerOrgId).
  const victimShipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 40,
    pickupAddress: "A",
    dropAddress: "B",
  });
  assert.equal(victimShipment.customerOrgId, undefined);

  const attacker = registerCustomerOrgAdmin(store, {
    fullName: "Attacker",
    phone: "9000000602",
    orgDisplayName: "ACME Manufacturing",
  });
  assert.equal(shipmentVisibleToCustomerUser(store, victimShipment, attacker.user.id), false);
});

test("submitDriverPod requires IN_PROGRESS trip", () => {
  const store = createStore();
  const owner = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9000000501",
    orgDisplayName: "Carrier",
    vehicleRegistrationNumber: "HR01FF0501",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: owner.user.id,
    orgId: owner.org.id,
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
    weightKg: 40,
    pickupAddress: "A",
    dropAddress: "B",
  });
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, status: "AUTHORIZED", razorpayPaymentId: "pay_x" });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: owner.user.id });
  assert.throws(
    () => submitDriverPod(store, { shipmentId: shipment.id, userId: owner.user.id }),
    (e: unknown) => e instanceof ApiError && (e as ApiError).message === "trip_not_started_for_pod",
  );
});
