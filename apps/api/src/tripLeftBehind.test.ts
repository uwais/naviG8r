// A trip that starts closes every waiting booking whose checkout is not done (owner, 23 Oct 2026): the shipper is
// told, no money moves, the room is freed, a payment that still lands goes to Finance, and none is taken after.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { httpFixture } from "../test/httpFixtures.ts";
import { integrationLoadResponse } from "./integrationServices.ts";
import { SHIPMENT_LEFT_BEHIND_EVENT } from "./notifications.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { rollbackBooking } from "./services.ts";
import type { EwayBill, IntegrationConnection, Payment } from "./types.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

const noBillNeeded: EwayBill = { kind: "NOT_NEEDED", notNeededReason: "GOODS_EXEMPT", enteredAtUtcMs: 1, enteredByUserId: "synthetic" };

async function book(f: Fixture, token: string, weightKg = 10): Promise<string> {
  const booked = await f.book(token, { weightKg });
  assert.equal(booked.status, 201, JSON.stringify(booked.body));
  return booked.body.shipment.id as string;
}

/** An accepted booking with no bill needed, so the trip can start. */
async function acceptedBooking(f: Fixture, weightKg = 10): Promise<string> {
  const id = await book(f, f.tokens.shipperA, weightKg);
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  f.store.shipments.set(id, { ...f.store.shipments.get(id)!, ewayBill: noBillNeeded });
  return id;
}

/** The payment as the Razorpay flow leaves it; the fixture books with the mock provider, which collects at once. */
function setPayment(f: Fixture, shipmentId: string, fields: Partial<Payment>): void {
  const payment = f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", ...fields });
}
const paymentOf = (f: Fixture, shipmentId: string) => f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;
const start = (f: Fixture) => f.request(`/v1/pilot/anchor-trips/${f.trip.id}/start`, "POST", {}, f.tokens.carrierA);
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

test("starting closes each waiting booking not paid for: shipper told, no money moved, room freed, one audit row each", async t => {
  const f = await httpFixture(t);
  const accepted = await acceptedBooking(f, 500);
  const unpaid = await book(f, f.tokens.shipperB, 300);
  const failed = await book(f, f.tokens.shipperB, 200);
  setPayment(f, unpaid, { status: "CREATED", razorpayOrderId: "order_unpaid" });
  setPayment(f, failed, { status: "FAILED", razorpayOrderId: "order_failed" });
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "FULL", "precondition: the waiting bookings fill the trip");

  const started = await start(f);
  assert.equal(started.status, 200, JSON.stringify(started.body));
  assert.deepEqual([started.body.trip.status, started.body.trip.reservedKg], ["IN_PROGRESS", 500], "their room is freed");
  for (const id of [unpaid, failed]) {
    const shipment = f.store.shipments.get(id)!;
    assert.equal(shipment.status, "FAILED_CARRIER_REFUNDED", id);
    assert.equal(typeof shipment.leftBehindAtUtcMs, "number");
  }
  assert.deepEqual([paymentOf(f, unpaid).status, paymentOf(f, failed).status], ["CREATED", "FAILED"], "no money moved, so nothing is refunded");
  assert.equal(f.store.shipments.get(accepted)?.status, "BOOKED", "the accepted booking goes on the trip");

  const saved = loadStoreFromDisk(process.env.DATA_FILE!);
  assert.equal(saved.shipments.get(unpaid)?.status, "FAILED_CARRIER_REFUNDED", "saved");
  const rows = [...saved.auditEvents.values()].filter((row) => row.action === "SHIPMENT_LEFT_BEHIND")
    .map((row) => [row.resourceId, row.previousState, row.newState, row.actorUserId]);
  assert.deepEqual(rows.sort(), [[unpaid, "PENDING_CARRIER_ACCEPT", "FAILED_CARRIER_REFUNDED", f.carrierA.user.id], [failed, "PENDING_CARRIER_ACCEPT", "FAILED_CARRIER_REFUNDED", f.carrierA.user.id]].sort());

  const toldB = await inbox(f, f.tokens.shipperB);
  // The test sets each payment straight in the store, which the server reports as a payment change; that notice is the test's own.
  for (const id of [unpaid, failed]) {
    assert.deepEqual(toldB.filter((n) => n.shipmentId === id && n.eventKey !== "payment.status_changed").map((n) => [n.eventKey, n.data.title, n.data.body]),
      [[SHIPMENT_LEFT_BEHIND_EVENT, "This trip left without your shipment", "If your bank shows a payment, it comes back within 3 days. Book another trip when you are ready."]],
      "only this notice: no Trip started, no Shipment cancelled");
  }
  assert.ok((await inbox(f, f.tokens.shipperA)).some((n) => n.shipmentId === accepted && n.eventKey === "trip.started"), "the shipper on the trip is still told");
  const carrierHeard = (await inbox(f, f.tokens.carrierA)).filter((n) => n.shipmentId === unpaid || n.shipmentId === failed);
  assert.deepEqual(carrierHeard.filter((n) => n.eventKey === SHIPMENT_LEFT_BEHIND_EVENT), [], "the carrier started the trip; it is not told");

  const read = await f.request(`/shipments/${unpaid}/tracking`, "GET", undefined, f.tokens.shipperB);
  assert.equal(read.status, 200);
  assert.equal(read.body.shipment.status, "FAILED_CARRIER_REFUNDED");
  assert.equal(typeof read.body.shipment.leftBehindAtUtcMs, "number", "the shipper app reads why it was closed");
});

test("a refused start closes nothing", async t => {
  const f = await httpFixture(t);
  const accepted = await acceptedBooking(f);
  f.store.shipments.set(accepted, { ...f.store.shipments.get(accepted)!, ewayBill: undefined });
  const unpaid = await book(f, f.tokens.shipperB);
  setPayment(f, unpaid, { status: "CREATED" });
  assert.equal((await start(f)).status, 409);
  assert.equal(f.store.shipments.get(unpaid)?.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(f.store.shipments.get(unpaid)?.leftBehindAtUtcMs, undefined);
});

test("money Razorpay collected for a booking the trip left without goes on Finance's after-cancel list, at the start or later", async t => {
  const f = await httpFixture(t);
  await acceptedBooking(f);
  const capturedEarly = await book(f, f.tokens.shipperB);
  const paidLate = await book(f, f.tokens.shipperB);
  const authorizedLate = await book(f, f.tokens.shipperB);
  setPayment(f, capturedEarly, { status: "CAPTURED", razorpayOrderId: "order_early", razorpayPaymentId: "pay_early" });
  setPayment(f, paidLate, { status: "CREATED", razorpayOrderId: "order_late" });
  setPayment(f, authorizedLate, { status: "CREATED", razorpayOrderId: "order_held" });
  assert.equal((await start(f)).status, 200);

  assert.deepEqual([paymentOf(f, capturedEarly).status, paymentOf(f, capturedEarly).capturedAfterCancelRazorpayPaymentId], ["CAPTURED_AFTER_CANCEL", "pay_early"]);
  const told = (await inbox(f, f.tokens.shipperB)).filter((n) => n.shipmentId === capturedEarly && n.eventKey === SHIPMENT_LEFT_BEHIND_EVENT);
  assert.deepEqual(told.map((n) => n.data.body), ["NaviG8r is refunding your payment. Your bank may take 5-7 working days."], "never told it was not charged");

  applyRazorpayWebhookPayload(f.store, { event: "payment.captured", payload: { payment: { entity: { id: "pay_late", order_id: "order_late" } } } });
  assert.deepEqual([paymentOf(f, paidLate).status, f.store.shipments.get(paidLate)?.status], ["CAPTURED_AFTER_CANCEL", "FAILED_CARRIER_REFUNDED"], "a late capture never brings the booking back");
  applyRazorpayWebhookPayload(f.store, { event: "payment.authorized", payload: { payment: { entity: { id: "pay_held", order_id: "order_held" } } } });
  assert.deepEqual([paymentOf(f, authorizedLate).status, f.store.shipments.get(authorizedLate)?.status], ["CREATED", "FAILED_CARRIER_REFUNDED"],
    "an authorization nobody captures is only recorded, as after any cancel: Razorpay releases it");

  const forFinance = (await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.finance)).body.collectedAfterCancel as Array<{ shipment: { id: string } }>;
  assert.deepEqual(forFinance.map((row) => row.shipment.id).sort(), [capturedEarly, paidLate].sort());
  const marked = await f.request(`/shipments/${paidLate}/mark-refunded`, "POST", { razorpayPaymentId: "pay_late" }, f.tokens.finance);
  assert.deepEqual([marked.status, marked.body.payment?.status], [200, "REFUNDED"], "Finance marks it refunded as after any cancel");
});

test("checkout for a booking the trip left without is refused with the server's sentence, and the payment stays as it was", async t => {
  const f = await httpFixture(t);
  await acceptedBooking(f);
  const unpaid = await book(f, f.tokens.shipperB);
  const waiting = await book(f, f.tokens.shipperB);
  setPayment(f, unpaid, { status: "CREATED", razorpayOrderId: "order_unpaid" });
  setPayment(f, waiting, { status: "CREATED", razorpayOrderId: "order_waiting" });
  assert.equal((await start(f)).status, 200);
  // Booking itself would ask Razorpay for an order, which tests cannot, so Razorpay is on only from here.
  withRazorpay(t);

  const confirm = (shipmentId: string, orderId: string) => f.request("/v1/payments/razorpay/confirm", "POST",
    { shipmentId, razorpayOrderId: orderId, razorpayPaymentId: "pay_x", razorpaySignature: signed(orderId, "pay_x") }, f.tokens.shipperB);
  const refused = await confirm(unpaid, "order_unpaid");
  assert.equal(refused.status, 409);
  assert.deepEqual(refused.body, { error: "trip_already_started", detail: "This trip has already left. If your bank shows a payment, it comes back within 3 days." });
  assert.equal(paymentOf(f, unpaid).status, "CREATED");

  // A booking still waiting on a trip already on the road (stored before this rule) is refused the same way.
  f.store.shipments.set(waiting, { ...f.store.shipments.get(waiting)!, status: "PENDING_CARRIER_ACCEPT", leftBehindAtUtcMs: undefined });
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "IN_PROGRESS");
  assert.equal((await confirm(waiting, "order_waiting")).body.error, "trip_already_started");
});

test("booking on a started trip is refused before any checkout, and a partner is not asked to check out a closed booking", async t => {
  const f = await httpFixture(t);
  await acceptedBooking(f);
  const unpaid = await book(f, f.tokens.shipperB);
  setPayment(f, unpaid, { status: "CREATED" });
  assert.equal((await start(f)).status, 200);
  const late = await f.book(f.tokens.shipperB);
  assert.deepEqual([late.status, late.body.error], [400, "anchor_trip_not_open"]);

  withRazorpay(t);
  const connection = { paymentPolicy: "portal_checkout" } as IntegrationConnection;
  assert.equal(integrationLoadResponse(f.store, f.store.shipments.get(unpaid)!, connection).checkoutRequired, false);
});

test("undoing a booking whose order failed keeps one the trip's start already closed", async t => {
  const f = await httpFixture(t);
  await acceptedBooking(f);
  const unpaid = await book(f, f.tokens.shipperB, 300);
  setPayment(f, unpaid, { status: "CREATED" });
  assert.equal((await start(f)).status, 200);
  const reservedKg = f.store.anchorTrips.get(f.trip.id)!.reservedKg;
  rollbackBooking(f.store, unpaid);
  assert.equal(f.store.shipments.get(unpaid)?.status, "FAILED_CARRIER_REFUNDED", "the shipper was told; the record stays");
  assert.equal(f.store.anchorTrips.get(f.trip.id)!.reservedKg, reservedKg, "its room is not freed twice");
});
