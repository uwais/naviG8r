import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { httpFixture } from "../test/httpFixtures.ts";
import { BOOKING_EXPIRED_EVENT } from "./notifications.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { UNPAID_BOOKING_EXPIRY_MS, UNPAID_BOOKING_GRACE_MS } from "./config.ts";
import { createIntegrationApiKey, createIntegrationLoad } from "./integrationServices.ts";
import { resolveIntegrationAuth } from "./integrationAuth.ts";
import type { Payment } from "./types.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

/** Old enough to be closed: past the 30 minutes the shipper is told and the 10 minutes after. */
const closedAgeMs = UNPAID_BOOKING_EXPIRY_MS + UNPAID_BOOKING_GRACE_MS + 1000;

const moneyLine = "If your bank shows a payment, it comes back within 3 days of when you paid. Your bank may take 5-7 more working days.";

async function book(f: Fixture, token: string, weightKg = 10): Promise<string> {
  const booked = await f.book(token, { weightKg });
  assert.equal(booked.status, 201, JSON.stringify(booked.body));
  return booked.body.shipment.id as string;
}

/** The fixture books with the mock provider, which collects at once; this leaves the payment as Razorpay checkout does. */
function waitingForPayment(f: Fixture, shipmentId: string, ageMs: number, fields: Partial<Payment> = {}): void {
  const shipment = f.store.shipments.get(shipmentId)!;
  f.store.shipments.set(shipmentId, { ...shipment, createdAtUtcMs: Date.now() - ageMs });
  const payment = f.store.payments.get(shipment.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", status: "CREATED", razorpayOrderId: `order_${shipmentId}`, ...fields });
}
const paymentOf = (f: Fixture, shipmentId: string) => f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;
const inbox = async (f: Fixture, token: string) =>
  (await f.request("/v1/notifications", "GET", undefined, token)).body.notifications as Array<{ eventKey: string; shipmentId: string; data: { title: string; body: string } }>;

function withRazorpay(t: TestContext): void {
  const saved = { provider: process.env.PAYMENT_PROVIDER, secret: process.env.RAZORPAY_KEY_SECRET };
  process.env.PAYMENT_PROVIDER = "RAZORPAY";
  process.env.RAZORPAY_KEY_SECRET = "synthetic_checkout_secret";
  t.after(() => {
    process.env.PAYMENT_PROVIDER = saved.provider;
    if (saved.secret === undefined) delete process.env.RAZORPAY_KEY_SECRET;
    else process.env.RAZORPAY_KEY_SECRET = saved.secret;
  });
}
const signed = (orderId: string, paymentId: string) =>
  crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET!).update(`${orderId}|${paymentId}`).digest("hex");

test("a booking not paid within 30 minutes closes on the next request: room freed, shipper told, no money moved", async t => {
  const f = await httpFixture(t);
  assert.deepEqual([UNPAID_BOOKING_EXPIRY_MS, UNPAID_BOOKING_GRACE_MS], [30 * 60 * 1000, 10 * 60 * 1000]);
  const expired = await book(f, f.tokens.shipperB, 1000);
  waitingForPayment(f, expired, closedAgeMs);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "FULL", "precondition: the unpaid booking fills the trip");

  const read = await f.request(`/shipments/${expired}`, "GET", undefined, f.tokens.shipperB);
  assert.equal(read.status, 200);
  assert.equal(read.body.shipment.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(typeof read.body.shipment.expiredUnpaidAtUtcMs, "number", "the shipper app reads why it was closed");
  assert.deepEqual([f.store.anchorTrips.get(f.trip.id)?.status, f.store.anchorTrips.get(f.trip.id)?.reservedKg], ["OPEN", 0], "its room is freed");
  assert.equal(paymentOf(f, expired).status, "CREATED", "no money moved, so nothing is refunded");

  const saved = loadStoreFromDisk(process.env.DATA_FILE!);
  assert.equal(saved.shipments.get(expired)?.status, "FAILED_CARRIER_REFUNDED", "saved");
  assert.deepEqual([...saved.auditEvents.values()].filter((row) => row.action === "BOOKING_EXPIRED_UNPAID").map((row) => [row.resourceId, row.previousState, row.newState, row.actorUserId]),
    [[expired, "PENDING_CARRIER_ACCEPT", "FAILED_CARRIER_REFUNDED", "system:unpaid-booking-expiry"]]);

  const told = (await inbox(f, f.tokens.shipperB)).filter((n) => n.shipmentId === expired && n.eventKey !== "payment.status_changed");
  assert.deepEqual(told.map((n) => [n.eventKey, n.data.title, n.data.body]),
    [[BOOKING_EXPIRED_EVENT, "This booking expired", `This booking expired because it was not paid within 30 minutes. ${moneyLine}`]], "no Shipment cancelled notice; Razorpay may hold a payment, so the money line");
  assert.deepEqual((await inbox(f, f.tokens.carrierA)).filter((n) => n.shipmentId === expired && n.eventKey === BOOKING_EXPIRED_EVENT), []);

  const rebooked = await f.book(f.tokens.shipperA, { weightKg: 1000 });
  assert.equal(rebooked.status, 201, "another shipper can book the freed room");
});

test("a booking younger than 30 minutes, or already paid, keeps its room", async t => {
  const f = await httpFixture(t);
  const young = await book(f, f.tokens.shipperB, 300);
  const authorized = await book(f, f.tokens.shipperB, 300);
  const collected = await book(f, f.tokens.shipperB, 300);
  waitingForPayment(f, young, UNPAID_BOOKING_EXPIRY_MS - 60_000);
  waitingForPayment(f, authorized, closedAgeMs, { status: "AUTHORIZED", razorpayPaymentId: "pay_held" });
  const collectedShipment = f.store.shipments.get(collected)!;
  f.store.shipments.set(collected, { ...collectedShipment, createdAtUtcMs: Date.now() - closedAgeMs });

  assert.equal((await f.request("/anchor-trips", "GET")).status, 200);
  for (const id of [young, authorized, collected]) {
    assert.equal(f.store.shipments.get(id)?.status, "PENDING_CARRIER_ACCEPT", id);
    assert.equal(f.store.shipments.get(id)?.expiredUnpaidAtUtcMs, undefined, id);
  }
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.reservedKg, 900);
});

test("a payment confirmed after the booking expired is refused with the server's sentence", async t => {
  const f = await httpFixture(t);
  const late = await book(f, f.tokens.shipperB);
  waitingForPayment(f, late, closedAgeMs, { razorpayOrderId: "order_late" });
  // Booking itself would ask Razorpay for an order, which tests cannot, so Razorpay is on only from here.
  withRazorpay(t);

  const refused = await f.request("/v1/payments/razorpay/confirm", "POST",
    { shipmentId: late, razorpayOrderId: "order_late", razorpayPaymentId: "pay_late", razorpaySignature: signed("order_late", "pay_late") }, f.tokens.shipperB);
  assert.equal(refused.status, 409);
  assert.deepEqual(refused.body, { error: "booking_expired", detail: `This booking expired because it was not paid within 30 minutes. ${moneyLine}` });
  assert.deepEqual([paymentOf(f, late).status, f.store.shipments.get(late)?.status], ["CREATED", "FAILED_CARRIER_REFUNDED"]);
});

test("an ERP load is never closed by the unpaid expiry, and an ERP retry never gets back a booking it closed", async t => {
  const f = await httpFixture(t);
  const { token } = createIntegrationApiKey(f.store, f.shipperA.org.id);
  const ctx = resolveIntegrationAuth(f.store, { bearerToken: token });
  const load = (externalLoadId: string, idempotencyKey: string) => createIntegrationLoad(f.store, ctx, {
    externalLoadId, idempotencyKey, weightKg: 10, pickupAddress: "Synthetic A", dropAddress: "Synthetic B",
    pickup: { lat: 28.4595, lng: 77.0266 }, drop: { lat: 26.9124, lng: 75.7873 }, lanePreference: "explicit", anchorTripId: f.trip.id,
  });
  const erp = (await load("ERP-OLD", "key-old")).shipment.id;
  waitingForPayment(f, erp, 24 * 60 * 60 * 1000);
  assert.equal((await f.request("/anchor-trips", "GET")).status, 200);
  assert.deepEqual([f.store.shipments.get(erp)?.status, f.store.shipments.get(erp)?.expiredUnpaidAtUtcMs], ["PENDING_CARRIER_ACCEPT", undefined]);

  // A load closed by the expiry before ERP loads were left out of it.
  const closedEarlier = (await load("ERP-CLOSED", "key-closed")).shipment;
  f.store.shipments.set(closedEarlier.id, { ...closedEarlier, status: "FAILED_CARRIER_REFUNDED", expiredUnpaidAtUtcMs: Date.now() });
  const byKey = await load("ERP-OTHER", "key-closed");
  const byLoadId = await load("ERP-CLOSED", "key-new");
  for (const retry of [byKey, byLoadId]) {
    assert.equal(retry.created, true);
    assert.notEqual(retry.shipment.id, closedEarlier.id);
    assert.equal(retry.shipment.status, "PENDING_CARRIER_ACCEPT");
  }
});

test("the shipper is told 30 minutes, but a booking closes only 10 minutes after that, so a payment just past 30 still goes through", async t => {
  const f = await httpFixture(t);
  const inGrace = await book(f, f.tokens.shipperB);
  waitingForPayment(f, inGrace, UNPAID_BOOKING_EXPIRY_MS + 9 * 60_000, { razorpayOrderId: "order_in_grace" });
  withRazorpay(t);

  const confirmed = await f.request("/v1/payments/razorpay/confirm", "POST",
    { shipmentId: inGrace, razorpayOrderId: "order_in_grace", razorpayPaymentId: "pay_in_grace", razorpaySignature: signed("order_in_grace", "pay_in_grace") }, f.tokens.shipperB);
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.deepEqual([paymentOf(f, inGrace).status, f.store.shipments.get(inGrace)?.status], ["AUTHORIZED", "PENDING_CARRIER_ACCEPT"]);
});

test("a payment Razorpay reports after the booking expired leaves it looking unpaid: the id is kept for staff, and no payment notice goes out", async t => {
  const f = await httpFixture(t);
  const late = await book(f, f.tokens.shipperB);
  waitingForPayment(f, late, closedAgeMs, { razorpayOrderId: "order_after_expiry" });
  assert.equal((await f.request("/anchor-trips", "GET")).status, 200);
  assert.equal(f.store.shipments.get(late)?.status, "FAILED_CARRIER_REFUNDED", "precondition: expired");
  const savedSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  process.env.RAZORPAY_WEBHOOK_SECRET = "synthetic_webhook_secret";
  t.after(() => { if (savedSecret === undefined) delete process.env.RAZORPAY_WEBHOOK_SECRET; else process.env.RAZORPAY_WEBHOOK_SECRET = savedSecret; });

  // The fixture moving the mock payment back to CREATED made one notice already; only what the webhook adds counts.
  const paymentNotices = async () => (await inbox(f, f.tokens.shipperB)).filter((n) => n.shipmentId === late && n.eventKey === "payment.status_changed").length;
  const noticesBefore = await paymentNotices();
  const event = { event: "payment.authorized", payload: { payment: { entity: { id: "pay_after_expiry", order_id: "order_after_expiry" } } } };
  const signature = crypto.createHmac("sha256", process.env.RAZORPAY_WEBHOOK_SECRET).update(JSON.stringify(event)).digest("hex");
  const answered = await f.request("/v1/payments/razorpay/webhook", "POST", event, undefined, { "x-razorpay-signature": signature });
  assert.equal(answered.status, 200);

  assert.deepEqual([paymentOf(f, late).status, f.store.shipments.get(late)?.status], ["CREATED", "FAILED_CARRIER_REFUNDED"]);
  assert.deepEqual([...f.store.auditEvents.values()].filter((row) => row.action === "PAYMENT_AFTER_CANCEL" && row.resourceId === late).map((row) => [row.reasonCode, row.razorpayPaymentId]),
    [["AUTHORIZED", "pay_after_expiry"]], "staff can find the late payment");
  assert.equal(await paymentNotices(), noticesBefore, "no payment status notice for the late payment");
});

test("a booking that expired before Razorpay made its order is told only that it expired: nothing could be paid", async t => {
  const f = await httpFixture(t);
  const noOrder = await book(f, f.tokens.shipperB);
  waitingForPayment(f, noOrder, closedAgeMs, { razorpayOrderId: undefined });
  const told = (await inbox(f, f.tokens.shipperB)).filter((n) => n.shipmentId === noOrder && n.eventKey === BOOKING_EXPIRED_EVENT);
  assert.deepEqual(told.map((n) => n.data.body), ["This booking expired because it was not paid within 30 minutes."]);
});
