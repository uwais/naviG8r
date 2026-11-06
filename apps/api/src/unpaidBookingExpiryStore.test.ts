// Store-level checks of the unpaid booking expiry. They set the Razorpay provider for the whole file, so they
// live apart from unpaidBookingExpiry.test.ts, whose fixture books with the mock provider.
import { asUser, bookTestShipment, registerCompliantCarrier } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { once } from "node:events";
import { createStore } from "./store.ts";
import { createApp } from "./httpServer.ts";
import { confirmRazorpayCheckoutAuthorization, expireUnpaidBookings, publishAnchorTripAsPilotDriver } from "./services.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { serializeResponse } from "./rbacResponses.ts";
import { BOOKING_EXPIRED_EVENT, captureWorkflowNotifications, workflowSnapshot } from "./notifications.ts";
import { UNPAID_BOOKING_EXPIRY_MS, UNPAID_BOOKING_GRACE_MS } from "./config.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { httpFixture } from "../test/httpFixtures.ts";

process.env.PAYMENT_PROVIDER = "RAZORPAY";
process.env.RAZORPAY_KEY_ID = "rzp_test_expiry";
process.env.RAZORPAY_KEY_SECRET = "expiry_test_secret";

const UNPAID_BOOKING_CLOSES_AFTER_MS = UNPAID_BOOKING_EXPIRY_MS + UNPAID_BOOKING_GRACE_MS;
const GURGAON = { lat: 28.4595, lng: 77.0266, label: "Gurugram" };
const JAIPUR = { lat: 26.9124, lng: 75.7873, label: "Jaipur" };

function tripWithBooking(store: ReturnType<typeof createStore>, params: { weightKg: number; ageMs: number }) {
  const carrier = registerCompliantCarrier(store, {
    fullName: "Expiry Carrier",
    phone: "9876500101",
    orgDisplayName: "Expiry Carrier",
    vehicleRegistrationNumber: "HR26EX0101",
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
  const booked = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Expiry Buyer",
    weightKg: params.weightKg,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
    pickup: GURGAON,
    drop: JAIPUR,
  });
  const shipment = { ...booked, createdAtUtcMs: Date.now() - params.ageMs };
  store.shipments.set(shipment.id, shipment);
  const payment = store.payments.get(shipment.paymentId)!;
  store.payments.set(payment.id, { ...payment, razorpayOrderId: `order_${shipment.id}` });
  return { trip, shipment };
}

test("an unpaid booking stops holding trip space 10 minutes after its 30-minute payment window ends", () => {
  const store = createStore();
  const { trip, shipment } = tripWithBooking(store, { weightKg: 1000, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 1000 });
  assert.equal(store.anchorTrips.get(trip.id)!.status, "FULL");

  expireUnpaidBookings(store);

  const closed = store.shipments.get(shipment.id)!;
  assert.equal(closed.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(typeof closed.unpaidBookingExpiredAtUtcMs, "number");
  assert.equal(store.payments.get(shipment.paymentId)!.status, "CREATED", "no money moved, so the payment is left as it was");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 0);
  assert.equal(store.anchorTrips.get(trip.id)!.status, "OPEN");
});

test("a booking under 30 minutes old, or one already paid, keeps its trip space", () => {
  const young = createStore();
  const recent = tripWithBooking(young, { weightKg: 300, ageMs: UNPAID_BOOKING_EXPIRY_MS - 60_000 });
  expireUnpaidBookings(young);
  assert.equal(young.shipments.get(recent.shipment.id)!.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(young.anchorTrips.get(recent.trip.id)!.reservedKg, 300);

  const paid = createStore();
  const old = tripWithBooking(paid, { weightKg: 300, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 60_000 });
  const payment = paid.payments.get(old.shipment.paymentId)!;
  paid.payments.set(payment.id, { ...payment, status: "AUTHORIZED", razorpayPaymentId: "pay_paid_in_time" });
  expireUnpaidBookings(paid);
  assert.equal(paid.shipments.get(old.shipment.id)!.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(paid.anchorTrips.get(old.trip.id)!.reservedKg, 300);
});

test("a payment confirm that arrives after the booking expired is refused with the expired sentence", () => {
  const store = createStore();
  const { shipment } = tripWithBooking(store, { weightKg: 200, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 1000 });
  // The server runs the expiry before every request.
  expireUnpaidBookings(store);
  const orderId = `order_${shipment.id}`;
  const paymentId = "pay_late_confirm";
  const signature = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET!)
    .update(`${orderId}|${paymentId}`)
    .digest("hex");

  assert.throws(
    () => confirmRazorpayCheckoutAuthorization(store, {
      shipmentId: shipment.id,
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: signature,
    }),
    (e: Error & { extra?: Record<string, unknown>; httpStatus?: number }) =>
      e.message === "booking_expired_unpaid" &&
      e.httpStatus === 409 &&
      e.extra?.detail === "This booking expired because it was not paid within 30 minutes. " +
        "If your bank shows a payment, it comes back within 3 days of when you paid. Your bank may take 5-7 more working days.",
  );
  assert.equal(store.payments.get(shipment.paymentId)!.status, "CREATED");
  assert.equal(store.shipments.get(shipment.id)!.status, "FAILED_CARRIER_REFUNDED");
});

test("a payment.authorized webhook after the booking expired leaves it closed and records the payment id for staff", () => {
  const store = createStore();
  const { trip, shipment } = tripWithBooking(store, { weightKg: 200, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 1000 });
  expireUnpaidBookings(store);
  applyRazorpayWebhookPayload(store, {
    event: "payment.authorized",
    payload: { payment: { entity: { id: "pay_late_webhook", order_id: `order_${shipment.id}`, status: "authorized" } } },
  });
  assert.equal(store.payments.get(shipment.paymentId)!.status, "CREATED");
  assert.deepEqual(
    [...store.auditEvents.values()].filter((row) => row.action === "PAYMENT_AFTER_CANCEL" && row.resourceId === shipment.id).map((row) => row.razorpayPaymentId),
    ["pay_late_webhook"],
  );
  assert.equal(store.shipments.get(shipment.id)!.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 0);
});

test("a payment that arrives after the booking closed sends no payment status notice", () => {
  const store = createStore();
  const { shipment } = tripWithBooking(store, { weightKg: 200, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 1000 });
  const snapshot = workflowSnapshot(store);
  const notices = (eventKey: string) =>
    [...store.notifications.values()].filter((n) => n.shipmentId === shipment.id && n.eventKey === eventKey).length;

  expireUnpaidBookings(store);
  captureWorkflowNotifications(store, snapshot);
  assert.ok(notices(BOOKING_EXPIRED_EVENT) > 0, "closing the booking tells the shipper, so the shipper is a recipient");
  const paymentNoticesAfterClose = notices("payment.status_changed");

  applyRazorpayWebhookPayload(store, {
    event: "payment.authorized",
    payload: { payment: { entity: { id: "pay_late_notice", order_id: `order_${shipment.id}`, status: "authorized" } } },
  });
  captureWorkflowNotifications(store, snapshot);
  assert.equal(notices("payment.status_changed"), paymentNoticesAfterClose);
});

test("a booking paid in the 10 minutes after its 30-minute window is still confirmed", () => {
  const store = createStore();
  const { trip, shipment } = tripWithBooking(store, { weightKg: 200, ageMs: UNPAID_BOOKING_EXPIRY_MS + 5 * 60_000 });
  expireUnpaidBookings(store);
  assert.equal(store.shipments.get(shipment.id)!.status, "PENDING_CARRIER_ACCEPT");

  const orderId = `order_${shipment.id}`;
  const paymentId = "pay_in_grace";
  const signature = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET!)
    .update(`${orderId}|${paymentId}`)
    .digest("hex");
  const { payment } = confirmRazorpayCheckoutAuthorization(store, {
    shipmentId: shipment.id,
    razorpayOrderId: orderId,
    razorpayPaymentId: paymentId,
    razorpaySignature: signature,
  });
  assert.equal(payment.status, "AUTHORIZED");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 200);
});

test("a load booked through the ERP integration is not closed by the unpaid expiry", () => {
  const store = createStore();
  const { trip, shipment } = tripWithBooking(store, { weightKg: 200, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 60 * 60_000 });
  store.shipments.set(shipment.id, { ...shipment, integrationConnectionId: "intconn_erp" });
  expireUnpaidBookings(store);
  const kept = store.shipments.get(shipment.id)!;
  assert.equal(kept.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(kept.unpaidBookingExpiredAtUtcMs, undefined);
  assert.equal(store.payments.get(shipment.paymentId)!.status, "CREATED");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 200);
});

test("the shipper sees when an unpaid booking expired", () => {
  const store = createStore();
  const { shipment } = tripWithBooking(store, { weightKg: 200, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 1000 });
  expireUnpaidBookings(store);
  const closed = store.shipments.get(shipment.id)!;
  const shipper = [...store.memberships.values()].find((m) => m.orgId === closed.customerOrgId)!;
  const shown = asUser(store, shipper.userId, () => serializeResponse(closed), shipper.orgId) as Record<string, unknown>;
  assert.equal(shown.unpaidBookingExpiredAtUtcMs, closed.unpaidBookingExpiredAtUtcMs);
});

test("GET /anchor-trips/:id shows the space an expired unpaid booking held as free", async (t) => {
  const previousDataFile = process.env.DATA_FILE;
  t.after(() => { process.env.DATA_FILE = previousDataFile; });
  process.env.DATA_FILE = `/tmp/navig8r-unpaid-expiry-${Date.now()}-${Math.random()}.json`;
  const app = await createApp();
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  t.after(() => app.server.close());
  const address = app.server.address();
  assert.ok(address && typeof address === "object");
  const { trip } = tripWithBooking(app.store, { weightKg: 1000, ageMs: UNPAID_BOOKING_CLOSES_AFTER_MS + 1000 });

  const res = await fetch(`http://127.0.0.1:${address.port}/anchor-trips/${trip.id}`);
  assert.equal(res.status, 200);
  const body = (await res.json()) as { trip: { reservedKg: number; status: string } };
  assert.equal(body.trip.reservedKg, 0);
  assert.equal(body.trip.status, "OPEN");
});

test("POST /v1/payments/razorpay/confirm after the booking expired is refused and the closed booking is saved", async (t) => {
  const f = await httpFixture(t);
  t.after(() => { process.env.PAYMENT_PROVIDER = "RAZORPAY"; });
  const booked = bookTestShipment(f.store, {
    anchorTripId: f.trip.id,
    customerOrg: { id: f.shipperA.org.id, displayName: f.shipperA.org.displayName },
    customerOrgName: f.shipperA.org.displayName,
    weightKg: 10,
    pickupAddress: "Synthetic A",
    dropAddress: "Synthetic B",
  });
  const orderId = `order_${booked.id}`;
  const paymentId = "pay_late_http_confirm";
  f.store.shipments.set(booked.id, { ...booked, createdAtUtcMs: Date.now() - UNPAID_BOOKING_CLOSES_AFTER_MS - 1000 });
  const payment = f.store.payments.get(booked.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", status: "CREATED", razorpayOrderId: orderId });
  process.env.PAYMENT_PROVIDER = "RAZORPAY";

  const signature = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET!)
    .update(`${orderId}|${paymentId}`)
    .digest("hex");
  const refused = await f.request("/v1/payments/razorpay/confirm", "POST", {
    shipmentId: booked.id,
    razorpayOrderId: orderId,
    razorpayPaymentId: paymentId,
    razorpaySignature: signature,
  }, f.tokens.shipperA);
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, "booking_expired_unpaid");

  const saved = loadStoreFromDisk(process.env.DATA_FILE!);
  assert.equal(saved.payments.get(payment.id)!.status, "CREATED");
  assert.equal(saved.shipments.get(booked.id)!.status, "FAILED_CARRIER_REFUNDED");
});
