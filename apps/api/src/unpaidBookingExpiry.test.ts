import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { httpFixture } from "../test/httpFixtures.ts";
import { BOOKING_EXPIRED_EVENT } from "./notifications.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { UNPAID_BOOKING_EXPIRY_MS } from "./config.ts";
import type { Payment } from "./types.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

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
  assert.equal(UNPAID_BOOKING_EXPIRY_MS, 30 * 60 * 1000);
  const expired = await book(f, f.tokens.shipperB, 1000);
  waitingForPayment(f, expired, UNPAID_BOOKING_EXPIRY_MS + 1000);
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
    [[BOOKING_EXPIRED_EVENT, "This booking expired", "This booking expired because it was not paid within 30 minutes."]], "no Shipment cancelled notice");
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
  waitingForPayment(f, authorized, UNPAID_BOOKING_EXPIRY_MS + 1000, { status: "AUTHORIZED", razorpayPaymentId: "pay_held" });
  const collectedShipment = f.store.shipments.get(collected)!;
  f.store.shipments.set(collected, { ...collectedShipment, createdAtUtcMs: Date.now() - UNPAID_BOOKING_EXPIRY_MS - 1000 });

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
  waitingForPayment(f, late, UNPAID_BOOKING_EXPIRY_MS + 1000, { razorpayOrderId: "order_late" });
  // Booking itself would ask Razorpay for an order, which tests cannot, so Razorpay is on only from here.
  withRazorpay(t);

  const refused = await f.request("/v1/payments/razorpay/confirm", "POST",
    { shipmentId: late, razorpayOrderId: "order_late", razorpayPaymentId: "pay_late", razorpaySignature: signed("order_late", "pay_late") }, f.tokens.shipperB);
  assert.equal(refused.status, 409);
  assert.deepEqual(refused.body, { error: "booking_expired", detail: "This booking expired because it was not paid within 30 minutes. If your bank shows a payment, it comes back within 3 days." });
  assert.deepEqual([paymentOf(f, late).status, f.store.shipments.get(late)?.status], ["CREATED", "FAILED_CARRIER_REFUNDED"]);
});
