import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  acceptCarrierShipment,
  bookShipment,
  customerPrimaryOrgForUser,
  failCarrierAndRefund,
  inviteCustomerMember,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,
  registerCustomerUser,
  registerSoloOwnerOperatorDriver,
  startAnchorTripAsPilot,
  submitDriverPod,
} from "./services.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";

function seedDriverTrip(phone: string, capacityKg = 1000) {
  const store = createStore();
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Driver",
    phone,
    orgDisplayName: "Carrier Co",
    vehicleRegistrationNumber: `HR26${phone.slice(-4)}`,
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: driver.user.id,
    orgId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Agra",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg,
  });
  return { store, driver, trip };
}

test("Razorpay CAPTURED allows carrier accept and driver POD", () => {
  process.env.PAYMENT_PROVIDER = "RAZORPAY";
  process.env.RAZORPAY_KEY_ID = "rzp_test_captured";
  process.env.RAZORPAY_KEY_SECRET = "captured_test_secret";

  const { store, driver, trip } = seedDriverTrip("9876510001");
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 100,
    pickupAddress: "A",
    dropAddress: "B",
  });
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, {
    ...pay,
    razorpayOrderId: "order_cap_1",
    razorpayPaymentId: "pay_cap_1",
    status: "CAPTURED",
  });

  const accepted = acceptCarrierShipment(store, {
    shipmentId: shipment.id,
    userId: driver.user.id,
  });
  assert.equal(accepted.status, "BOOKED");

  const pod = submitDriverPod(store, {
    shipmentId: shipment.id,
    userId: driver.user.id,
  });
  assert.equal(pod.status, "PENDING_RELEASE");
});

test("failCarrierAndRefund rejects after trip start", async () => {
  process.env.PAYMENT_PROVIDER = "MOCK";
  const { store, driver, trip } = seedDriverTrip("9876510002");
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 150,
    pickupAddress: "A",
    dropAddress: "B",
  });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });
  startAnchorTripAsPilot(store, { userId: driver.user.id, tripId: trip.id });
  assert.equal(store.anchorTrips.get(trip.id)!.status, "IN_PROGRESS");

  await assert.rejects(
    () => failCarrierAndRefund(store, { shipmentId: shipment.id }),
    (e: unknown) => e instanceof ApiError && e.message === "trip_already_started",
  );
  assert.equal(store.shipments.get(shipment.id)!.status, "BOOKED");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 150);
});

test("failCarrierAndRefund still works before trip start", async () => {
  process.env.PAYMENT_PROVIDER = "MOCK";
  const { store, driver, trip } = seedDriverTrip("9876510003");
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 120,
    pickupAddress: "A",
    dropAddress: "B",
  });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });

  const out = await failCarrierAndRefund(store, { shipmentId: shipment.id });
  assert.equal(out.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 0);
});

test("payment.failed frees reserved capacity for pending checkout", () => {
  process.env.PAYMENT_PROVIDER = "RAZORPAY";
  process.env.RAZORPAY_KEY_ID = "rzp_test_failed";
  process.env.RAZORPAY_KEY_SECRET = "failed_test_secret";

  const { store, trip } = seedDriverTrip("9876510004", 500);
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 500,
    pickupAddress: "A",
    dropAddress: "B",
  });
  assert.equal(store.anchorTrips.get(trip.id)!.status, "FULL");
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, razorpayOrderId: "order_fail_1", status: "CREATED" });

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: {
      payment: { entity: { id: "pay_fail_1", order_id: "order_fail_1", status: "failed" } },
    },
  });

  assert.equal(store.payments.get(pay.id)!.status, "FAILED");
  assert.equal(store.shipments.get(shipment.id)!.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 0);
  assert.equal(store.anchorTrips.get(trip.id)!.status, "OPEN");
});

test("customerPrimaryOrgForUser prefers earliest membership over lexicographic org id", () => {
  const store = createStore();
  const first = registerCustomerOrgAdmin(store, {
    fullName: "Admin",
    phone: "9111002200",
    orgDisplayName: "First Org",
  });
  // Force a second org id that sorts before the first membership's org id.
  const earlierId = "org_aaa_earlier_lex";
  store.organizations.set(earlierId, {
    id: earlierId,
    kind: "CUSTOMER",
    displayName: "Lex Earlier Org",
    kycStatus: "NOT_STARTED",
    createdAtUtcMs: Date.now(),
  });
  const teammate = registerCustomerUser(store, {
    fullName: "Teammate",
    phone: "9222003300",
  });
  // Seed teammate into first org, then into lex-earlier org later.
  inviteCustomerMember(store, first.user.id, {
    orgId: first.org.id,
    phone: teammate.user.phone,
  });
  const firstMembership = store.memberships.get(`${teammate.user.id}:${first.org.id}`)!;
  store.memberships.set(`${teammate.user.id}:${first.org.id}`, {
    ...firstMembership,
    createdAtUtcMs: 1_000,
  });
  store.memberships.set(`${teammate.user.id}:${earlierId}`, {
    userId: teammate.user.id,
    orgId: earlierId,
    role: "CUSTOMER_MEMBER",
    createdAtUtcMs: 2_000,
  });

  const primary = customerPrimaryOrgForUser(store, teammate.user.id);
  assert.equal(primary?.id, first.org.id);
});

test("payment.failed does not downgrade AUTHORIZED or free capacity", () => {
  process.env.PAYMENT_PROVIDER = "RAZORPAY";
  process.env.RAZORPAY_KEY_ID = "rzp_test_auth";
  process.env.RAZORPAY_KEY_SECRET = "auth_test_secret";

  const { store, trip } = seedDriverTrip("9876510005");
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 100,
    pickupAddress: "A",
    dropAddress: "B",
  });
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, {
    ...pay,
    razorpayOrderId: "order_auth_1",
    razorpayPaymentId: "pay_auth_1",
    status: "AUTHORIZED",
  });

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: {
      payment: { entity: { id: "pay_auth_1", order_id: "order_auth_1", status: "failed" } },
    },
  });

  assert.equal(store.payments.get(pay.id)!.status, "AUTHORIZED");
  assert.equal(store.shipments.get(shipment.id)!.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 100);
});
