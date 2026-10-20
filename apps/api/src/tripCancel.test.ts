import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { inviteCarrierDriver, publishAnchorTrip, registerCustomerUser } from "./services.ts";
import type { Payment } from "./types.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

const lane = {
  originCity: "Bengaluru", destCity: "Chennai", origin: { lat: 12.97, lng: 77.59 }, destination: { lat: 13.08, lng: 80.27 },
  windowStart: "2026-10-20", windowEnd: "2026-10-21", vehicleClass: "MEDIUM", capacityKg: 1000,
};
const nearTheLane = { pickup: { lat: 12.97, lng: 77.59 }, drop: { lat: 13.08, lng: 80.27 } };
const search = "/v1/customer/eligible-anchor-trips?pickupLat=12.97&pickupLng=77.59&dropLat=13.08&dropLng=80.27&weightKg=10";

const cancel = (f: Fixture, tripId: string, token: string) => f.request(`/v1/pilot/anchor-trips/${tripId}/cancel`, "POST", {}, token);
const askToCancel = (f: Fixture, tripId: string, body: unknown, token: string) => f.request(`/v1/pilot/anchor-trips/${tripId}/cancel-request`, "POST", body, token);
const withdraw = (f: Fixture, tripId: string, token: string) => f.request(`/v1/pilot/anchor-trips/${tripId}/cancel-request/withdraw`, "POST", {}, token);
const failAndRefund = (f: Fixture, shipmentId: string) => f.request(`/shipments/${shipmentId}/fail-refund`, "POST", {}, f.tokens.finance);

async function hireDriver(f: Fixture) {
  registerCustomerUser(f.store, { fullName: "Synthetic Driver One", phone: "8000000013" });
  const hired = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA01AB1234", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  return { userId: hired.user.id, vehicleId: hired.vehicle.id, token: await f.login("8000000013") };
}

async function book(f: Fixture, tripId: string, weightKg = 10): Promise<string> {
  const booked = await f.book(f.tokens.shipperA, { anchorTripId: tripId, weightKg });
  assert.equal(booked.status, 201, JSON.stringify(booked.body));
  return booked.body.shipment.id as string;
}

/** The payment as the Razorpay flow leaves it; the fixture books with the mock provider, which collects at once. */
function setPayment(f: Fixture, shipmentId: string, fields: Partial<Payment>): void {
  const payment = f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, ...fields });
}
const paymentOf = (f: Fixture, shipmentId: string) => f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;

function tripAudit(f: Fixture, tripId: string) {
  return [...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()]
    .filter((event) => event.resourceId === tripId && event.action === "TRIP_STATUS_CHANGED")
    .map((event) => [event.previousState, event.newState, event.reasonCode ?? null]);
}

/** Refund calls fail in tests (no Razorpay keys), so a refund attempt shows up as razorpay_refund_failed. */
function withoutRazorpayKeys(t: TestContext): void {
  const saved = { id: process.env.RAZORPAY_KEY_ID, secret: process.env.RAZORPAY_KEY_SECRET };
  delete process.env.RAZORPAY_KEY_ID;
  delete process.env.RAZORPAY_KEY_SECRET;
  t.after(() => {
    if (saved.id !== undefined) process.env.RAZORPAY_KEY_ID = saved.id;
    if (saved.secret !== undefined) process.env.RAZORPAY_KEY_SECRET = saved.secret;
  });
}

test("a carrier cancels an empty trip: one audit row, off the public list and Match, booking, start, complete, location and assignment refused, its truck free, and it survives a reload", async t => {
  const f = await httpFixture(t);
  const driver = await hireDriver(f);
  const published = await f.request("/v1/pilot/anchor-trips", "POST", { orgId: f.carrierA.org.id, ...lane }, f.tokens.carrierA);
  const tripId = published.body.trip.id as string;
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${tripId}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA)).status, 200);
  const editTruck = () => f.request("/v1/pilot/me/vehicle", "PATCH", { vehicleRegistrationNumber: "KA05AA0001" }, driver.token);
  assert.equal((await editTruck()).status, 409, "precondition: the driver's truck is locked while the trip is open");
  assert.ok(JSON.stringify((await f.request(search)).body).includes(tripId), "precondition: Match finds the trip");

  const cancelled = await cancel(f, tripId, f.tokens.carrierA);
  assert.deepEqual([cancelled.status, cancelled.body.trip.status], [200, "CANCELLED"]);
  const again = await cancel(f, tripId, f.tokens.carrierA);
  assert.deepEqual([again.status, again.body.trip.status], [200, "CANCELLED"], "asking again changes nothing");
  assert.deepEqual(tripAudit(f, tripId), [["OPEN", "CANCELLED", null]], "one audit row, as Start writes");

  assert.equal(JSON.stringify((await f.request("/anchor-trips")).body).includes(tripId), false, "gone from the public list");
  assert.equal(JSON.stringify((await f.request(search)).body).includes(tripId), false, "gone from Match");
  const booking = await f.book(f.tokens.shipperA, { anchorTripId: tripId, ...nearTheLane });
  assert.deepEqual([booking.status, booking.body.error], [400, "anchor_trip_not_open"]);
  const started = await f.request(`/v1/pilot/anchor-trips/${tripId}/start`, "POST", {}, f.tokens.carrierA);
  assert.deepEqual([started.status, started.body.error], [400, "trip_not_startable"]);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${tripId}/complete`, "POST", {}, f.tokens.carrierA)).body.error, "trip_not_completable");
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${tripId}/location`, "POST", { lat: 12.97, lng: 77.59 }, driver.token)).body.error, "trip_not_started");
  const assigned = await f.request(`/v1/pilot/anchor-trips/${tripId}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA);
  assert.deepEqual([assigned.status, assigned.body.error], [409, "trip_cancelled"]);
  assert.equal((await editTruck()).status, 200, "a cancelled trip no longer holds the truck");

  assert.equal(loadStoreFromDisk(f.dataFilePath!).anchorTrips.get(tripId)?.status, "CANCELLED", "the file keeps it");
});

test("cancelling: a driver gets 403 and another carrier 404; unpaid, failed and accepted bookings refuse it; it works once the only booking is cancelled; never after the start", async t => {
  const f = await httpFixture(t);
  const driver = await hireDriver(f);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA)).status, 200);
  assert.equal((await cancel(f, f.trip.id, driver.token)).status, 403, "the driver of the trip only reads it");
  assert.equal((await cancel(f, f.trip.id, f.tokens.carrierB)).status, 404, "another carrier's trip does not exist for them");
  assert.equal((await cancel(f, f.trip.id, f.tokens.shipperA)).status, 404, "nor for a shipper");

  const shipmentId = await book(f, f.trip.id);
  for (const status of ["CREATED", "FAILED"] as const) {
    setPayment(f, shipmentId, { provider: "RAZORPAY", status });
    const refused = await cancel(f, f.trip.id, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.error, refused.body.detail], [409, "trip_has_bookings", "This trip has bookings, so it cannot be cancelled here."], status);
  }
  setPayment(f, shipmentId, { provider: "MOCK", status: "CAPTURED" });
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal((await cancel(f, f.trip.id, f.tokens.carrierA)).body.error, "trip_has_bookings", "an accepted booking");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "OPEN");

  assert.equal((await failAndRefund(f, shipmentId)).status, 200);
  assert.deepEqual((await cancel(f, f.trip.id, f.tokens.carrierA)).body.trip?.status, "CANCELLED", "a cancelled booking no longer counts");

  for (const status of ["IN_PROGRESS", "COMPLETED"] as const) {
    const trip = publishAnchorTrip(f.store, { carrierId: f.carrierA.org.id, ...lane });
    f.store.anchorTrips.set(trip.id, { ...trip, status });
    const refused = await cancel(f, trip.id, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.error], [409, "trip_not_cancellable"], status);
  }
});

test("asking NaviG8r to cancel needs a booking and a reason from the list, stops new bookings, shows to operations, and withdrawing puts the trip back as OPEN or FULL", async t => {
  const f = await httpFixture(t);
  const driver = await hireDriver(f);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA)).status, 200);
  const reason = { reasonCode: "TRUCK_UNAVAILABLE", note: "  Gearbox failed  " };
  const empty = await askToCancel(f, f.trip.id, reason, f.tokens.carrierA);
  assert.deepEqual([empty.status, empty.body.error], [409, "trip_has_no_bookings"], "an empty trip is cancelled directly");

  const shipmentId = await book(f, f.trip.id, 400);
  for (const [body, field] of [[{}, "reasonCode"], [{ reasonCode: "BORED" }, "reasonCode"], [{ reasonCode: "OTHER", note: "x".repeat(501) }, "note"]] as const) {
    const refused = await askToCancel(f, f.trip.id, body, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.error, refused.body.field], [400, "invalid_cancel_request", field], JSON.stringify(body).slice(0, 40));
  }
  assert.equal((await askToCancel(f, f.trip.id, reason, driver.token)).status, 403);
  assert.equal((await askToCancel(f, f.trip.id, reason, f.tokens.carrierB)).status, 404);

  const asked = await askToCancel(f, f.trip.id, reason, f.tokens.carrierA);
  assert.deepEqual([asked.status, asked.body.trip.status, asked.body.trip.cancelRequest], [200, "CANCEL_REQUESTED", undefined], "the reason and note are for operations, not the app");
  const kept = f.store.anchorTrips.get(f.trip.id)!.cancelRequest!;
  assert.deepEqual([kept.reasonCode, kept.note], ["TRUCK_UNAVAILABLE", "Gearbox failed"]);
  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "OTHER" }, f.tokens.carrierA)).status, 200, "asking twice is fine");
  assert.equal(f.store.anchorTrips.get(f.trip.id)!.cancelRequest!.reasonCode, "TRUCK_UNAVAILABLE", "and keeps the first reason");
  assert.deepEqual(tripAudit(f, f.trip.id), [["OPEN", "CANCEL_REQUESTED", "TRUCK_UNAVAILABLE"]]);

  const booking = await f.book(f.tokens.shipperA, { anchorTripId: f.trip.id });
  assert.deepEqual([booking.status, booking.body.error], [400, "anchor_trip_not_open"], "no new bookings");
  assert.equal(JSON.stringify((await f.request("/anchor-trips")).body).includes(f.trip.id), false, "off the public list");
  assert.equal((await cancel(f, f.trip.id, f.tokens.carrierA)).body.error, "trip_not_cancellable");

  const forOps = await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.ops);
  assert.equal(forOps.status, 200);
  const listed = forOps.body.requests as Array<{ trip: Record<string, any>; shipments: Array<{ shipment: Record<string, any>; payment: Record<string, any> }> }>;
  assert.deepEqual(listed.map((item) => [item.trip.id, item.trip.carrierDisplayName, item.trip.cancelRequest.reasonCode, item.trip.cancelRequest.note]),
    [[f.trip.id, "Synthetic Carrier A", "TRUCK_UNAVAILABLE", "Gearbox failed"]]);
  assert.deepEqual(listed[0]!.shipments.map((row) => [row.shipment.id, row.shipment.customerOrgName, row.payment.status]), [[shipmentId, "Synthetic Shipper A", "CAPTURED"]]);
  assert.equal(listed[0]!.shipments[0]!.shipment.grossPaise, undefined, "ops does not get the amount");
  const forFinance = (await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.finance)).body.requests;
  assert.equal(typeof forFinance[0].shipments[0].payment.amountPaise, "number", "finance does");
  assert.equal((await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.carrierA)).status, 403);

  assert.equal((await withdraw(f, f.trip.id, driver.token)).status, 403);
  const withdrawn = await withdraw(f, f.trip.id, f.tokens.carrierA);
  assert.deepEqual([withdrawn.status, withdrawn.body.trip.status], [200, "OPEN"]);
  assert.equal(f.store.anchorTrips.get(f.trip.id)!.cancelRequest, undefined);
  assert.equal((await withdraw(f, f.trip.id, f.tokens.carrierA)).status, 200, "withdrawing twice is fine");
  assert.deepEqual(tripAudit(f, f.trip.id).at(-1), ["CANCEL_REQUESTED", "OPEN", null]);

  await book(f, f.trip.id, 600);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "FULL", "precondition");
  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "ROUTE_CHANGED" }, f.tokens.carrierA)).body.trip.status, "CANCEL_REQUESTED", "a full trip can be asked about too");
  assert.equal((await withdraw(f, f.trip.id, f.tokens.carrierA)).body.trip.status, "FULL", "and goes back to FULL");
  assert.equal(loadStoreFromDisk(f.dataFilePath!).anchorTrips.get(f.trip.id)?.status, "FULL");
});

test("Finance cancelling a held payment sends no Razorpay refund and records the hold as released; a collected one still refunds; the trip never reopens and is cancelled after its last shipment", async t => {
  const f = await httpFixture(t);
  withoutRazorpayKeys(t);
  const held = await book(f, f.trip.id, 10);
  const taken = await book(f, f.trip.id, 990);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "FULL", "precondition");
  setPayment(f, held, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: "order_held", razorpayPaymentId: "pay_held" });
  setPayment(f, taken, { provider: "RAZORPAY", status: "CAPTURED", razorpayOrderId: "order_taken", razorpayPaymentId: "pay_taken" });
  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "DRIVER_UNAVAILABLE" }, f.tokens.carrierA)).status, 200);

  const released = await failAndRefund(f, held);
  assert.deepEqual([released.status, released.body.shipment?.status], [200, "FAILED_CARRIER_REFUNDED"], JSON.stringify(released.body));
  assert.equal(paymentOf(f, held).status, "HOLD_RELEASED");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "CANCEL_REQUESTED", "a requested trip does not reopen when room frees up");
  const audit = [...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()].filter((event) => event.resourceId === held).map((event) => event.action);
  assert.deepEqual(audit, ["SHIPMENT_BOOKED", "PAYMENT_HOLD_RELEASED"], "the hold is not recorded as a refund");

  const tried = await failAndRefund(f, taken);
  assert.deepEqual([tried.status, tried.body.error], [400, "razorpay_refund_failed"], "a collected payment is still sent to Razorpay to refund");
  assert.equal(f.store.shipments.get(taken)?.status, "PENDING_CARRIER_ACCEPT", "and nothing changes when Razorpay refuses");
  setPayment(f, taken, { provider: "MOCK" });
  assert.equal((await failAndRefund(f, taken)).status, 200);
  assert.equal(paymentOf(f, taken).status, "REFUNDED");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "CANCELLED", "the last cancelled shipment cancels the trip");
  assert.deepEqual(tripAudit(f, f.trip.id), [["FULL", "CANCEL_REQUESTED", "DRIVER_UNAVAILABLE"], ["CANCEL_REQUESTED", "CANCELLED", null]]);
  assert.deepEqual((await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.finance)).body.requests, [], "and it leaves the operations list");
});

test("a full trip nobody asked to cancel still reopens when Finance cancels a booking", async t => {
  const f = await httpFixture(t);
  const shipmentId = await book(f, f.trip.id, 1000);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "FULL");
  assert.equal((await failAndRefund(f, shipmentId)).status, 200);
  assert.deepEqual([f.store.anchorTrips.get(f.trip.id)?.status, f.store.anchorTrips.get(f.trip.id)?.reservedKg], ["OPEN", 0]);
});

test("the shipper is told the shipment was cancelled, with the route and what happens to the money", async t => {
  const f = await httpFixture(t);
  withoutRazorpayKeys(t);
  const held = await book(f, f.trip.id);
  const taken = await book(f, f.trip.id);
  const unpaid = await book(f, f.trip.id);
  setPayment(f, held, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayPaymentId: "pay_held" });
  setPayment(f, unpaid, { provider: "RAZORPAY", status: "CREATED" });
  for (const id of [held, taken, unpaid]) assert.equal((await failAndRefund(f, id)).status, 200, id);

  const inbox = (await f.request("/v1/notifications", "GET", undefined, f.tokens.shipperA)).body.notifications as Array<{ eventKey: string; shipmentId: string; data: { title: string; body: string } }>;
  const told = (id: string) => inbox.filter((item) => item.eventKey === "shipment.cancelled" && item.shipmentId === id).map((item) => [item.data.title, item.data.body]);
  const cancelled = "The carrier cannot carry your load from A to B, so it was cancelled.";
  assert.deepEqual(told(held), [["Shipment cancelled", `${cancelled} NaviG8r never collected this payment. Razorpay returns it within 3 days of when you paid; your bank may take 5-7 working days after that.`]]);
  assert.deepEqual(told(taken), [["Shipment cancelled", `${cancelled} Your refund has started.`]]);
  assert.deepEqual(told(unpaid), [["Shipment cancelled", `${cancelled} Nothing was charged.`]]);

  const carrierInbox = (await f.request("/v1/notifications", "GET", undefined, f.tokens.carrierA)).body.notifications as Array<{ eventKey: string; data: { body: string } }>;
  assert.deepEqual([...new Set(carrierInbox.filter((item) => item.eventKey === "shipment.cancelled").map((item) => item.data.body))], ["NaviG8r cancelled this shipment on your trip."]);
});

const webhook = (f: Fixture, event: string, id: string, orderId: string) =>
  applyRazorpayWebhookPayload(f.store, { event, payload: { payment: { entity: { id, order_id: orderId } } } });
const afterCancelAudit = (f: Fixture, shipmentId: string) => [...f.store.auditEvents.values()]
  .filter((event) => event.resourceId === shipmentId && event.action === "PAYMENT_AFTER_CANCEL")
  .map((event) => [event.previousState, event.newState, event.reasonCode, event.source]);

test("a late Razorpay event never brings back a cancelled shipment, and money moving after the cancel is recorded once for Finance", async t => {
  const f = await httpFixture(t);
  const held = await book(f, f.trip.id);
  setPayment(f, held, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: "order_held", razorpayPaymentId: "pay_held" });
  assert.equal((await failAndRefund(f, held)).status, 200);
  for (const event of ["payment.authorized", "payment.failed"]) {
    webhook(f, event, "pay_held", "order_held");
    assert.deepEqual([paymentOf(f, held).status, f.store.shipments.get(held)?.status], ["HOLD_RELEASED", "FAILED_CARRIER_REFUNDED"], event);
  }
  assert.deepEqual(afterCancelAudit(f, held), [], "the authorization NaviG8r already held is not new money");
  webhook(f, "payment.captured", "pay_held", "order_held");
  webhook(f, "payment.captured", "pay_held", "order_held");
  assert.deepEqual([paymentOf(f, held).status, f.store.shipments.get(held)?.status], ["CAPTURED_AFTER_CANCEL", "FAILED_CARRIER_REFUNDED"], "Razorpay captured the released hold");
  assert.deepEqual(afterCancelAudit(f, held), [["HOLD_RELEASED", "CAPTURED_AFTER_CANCEL", "CAPTURED", "SYSTEM"]], "one row, though Razorpay sent the event twice");

  const unpaid = await book(f, f.trip.id);
  setPayment(f, unpaid, { provider: "RAZORPAY", status: "CREATED", razorpayOrderId: "order_unpaid" });
  assert.equal((await failAndRefund(f, unpaid)).status, 200);
  webhook(f, "payment.authorized", "pay_late", "order_unpaid");
  assert.deepEqual([paymentOf(f, unpaid).status, f.store.shipments.get(unpaid)?.status], ["REFUNDED", "FAILED_CARRIER_REFUNDED"], "paying after the cancel does not revive the booking");
  assert.deepEqual(afterCancelAudit(f, unpaid), [["REFUNDED", "REFUNDED", "AUTHORIZED", "SYSTEM"]], "but the payment is recorded");

  const refunded = await book(f, f.trip.id);
  setPayment(f, refunded, { provider: "MOCK", status: "CAPTURED", razorpayOrderId: "order_refunded", razorpayPaymentId: "pay_refunded" });
  assert.equal((await failAndRefund(f, refunded)).status, 200);
  setPayment(f, refunded, { provider: "RAZORPAY" });
  webhook(f, "payment.captured", "pay_refunded", "order_refunded");
  assert.deepEqual([paymentOf(f, refunded).status, afterCancelAudit(f, refunded)], ["REFUNDED", []], "the capture NaviG8r already refunded, sent again");

  const forFinance = (await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.finance)).body;
  assert.deepEqual(forFinance.collectedAfterCancel.map((row: { shipment: { id: string }; payment: { status: string } }) => [row.shipment.id, row.payment.status]), [[held, "CAPTURED_AFTER_CANCEL"]]);
  const audit = (await f.request("/v1/audit", "GET", undefined, f.tokens.finance)).body.events as Array<{ action: string }>;
  assert.equal(audit.filter((event) => event.action === "PAYMENT_AFTER_CANCEL").length, 2, "Finance reads the rows");
});

test("an ERP-preauthorized payment, AUTHORIZED with no Razorpay payment or order, is no hold: cancelling it is refused as before", async t => {
  const f = await httpFixture(t);
  const shipmentId = await book(f, f.trip.id);
  setPayment(f, shipmentId, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: undefined, razorpayPaymentId: undefined });
  const refused = await failAndRefund(f, shipmentId);
  assert.deepEqual([refused.status, refused.body.error], [400, "razorpay_payment_id_missing"]);
  assert.deepEqual([paymentOf(f, shipmentId).status, f.store.shipments.get(shipmentId)?.status], ["AUTHORIZED", "PENDING_CARRIER_ACCEPT"]);
});

test("Finance cancelling from a cancel request is refused once the carrier withdrew it; the general fail-refund still works", async t => {
  const f = await httpFixture(t);
  const first = await book(f, f.trip.id);
  const second = await book(f, f.trip.id);
  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "ROUTE_CHANGED" }, f.tokens.carrierA)).status, 200);
  assert.equal((await withdraw(f, f.trip.id, f.tokens.carrierA)).status, 200);
  const refused = await f.request(`/shipments/${first}/fail-refund`, "POST", { fromCancelRequest: true }, f.tokens.finance);
  assert.deepEqual([refused.status, refused.body.error, refused.body.detail], [409, "cancel_request_withdrawn", "The carrier withdrew this request. Nothing changed."]);
  assert.deepEqual([f.store.shipments.get(first)?.status, paymentOf(f, first).status], ["PENDING_CARRIER_ACCEPT", "CAPTURED"]);

  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "ROUTE_CHANGED" }, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/shipments/${first}/fail-refund`, "POST", { fromCancelRequest: true }, f.tokens.finance)).status, 200, "while the request stands");
  assert.equal((await withdraw(f, f.trip.id, f.tokens.carrierA)).status, 200);
  assert.equal((await failAndRefund(f, second)).status, 200, "the general action is unchanged");
});

test("a late capture keeps its own Razorpay payment id beside the earlier one, each Razorpay payment is recorded once, and the rows name the webhook", async t => {
  const f = await httpFixture(t);
  const retried = await book(f, f.trip.id);
  setPayment(f, retried, { provider: "RAZORPAY", status: "FAILED", razorpayOrderId: "order_retried", razorpayPaymentId: "pay_failed" });
  assert.equal((await failAndRefund(f, retried)).status, 200);
  webhook(f, "payment.authorized", "pay_first", "order_retried");
  webhook(f, "payment.authorized", "pay_second", "order_retried");
  webhook(f, "payment.authorized", "pay_second", "order_retried");
  webhook(f, "payment.captured", "pay_second", "order_retried");
  webhook(f, "payment.captured", "pay_second", "order_retried");

  const payment = paymentOf(f, retried);
  assert.deepEqual([payment.status, payment.razorpayPaymentId, payment.capturedAfterCancelRazorpayPaymentId], ["CAPTURED_AFTER_CANCEL", "pay_failed", "pay_second"], "the earlier id is kept");
  const rows = [...f.store.auditEvents.values()].filter((event) => event.resourceId === retried && event.action === "PAYMENT_AFTER_CANCEL");
  assert.deepEqual(rows.map((event) => [event.reasonCode, event.razorpayPaymentId]), [["AUTHORIZED", "pay_first"], ["AUTHORIZED", "pay_second"], ["CAPTURED", "pay_second"]],
    "two Razorpay payments on one shipment are two rows; an event sent twice is one");
  assert.deepEqual([...new Set(rows.map((event) => [event.actorUserId, event.source].join(" ")))], ["system:razorpay-webhook SYSTEM"]);
});

test("Finance marks money collected after the cancel as refunded in Razorpay: REFUNDED, an audit row naming who, off the list; nobody else can", async t => {
  const f = await httpFixture(t);
  const held = await book(f, f.trip.id);
  setPayment(f, held, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: "order_held", razorpayPaymentId: "pay_held" });
  assert.equal((await failAndRefund(f, held)).status, 200);
  const markRefunded = (token: string) => f.request(`/shipments/${held}/mark-refunded`, "POST", {}, token);
  const early = await markRefunded(f.tokens.finance);
  assert.deepEqual([early.status, early.body.error], [409, "payment_not_captured_after_cancel"], "nothing was collected yet");

  webhook(f, "payment.captured", "pay_held", "order_held");
  for (const token of [f.tokens.ops, f.tokens.admin, f.tokens.carrierA, f.tokens.shipperA]) {
    assert.equal((await markRefunded(token)).status, 403);
  }
  assert.equal(paymentOf(f, held).status, "CAPTURED_AFTER_CANCEL");
  const forOps = (await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.ops)).body.collectedAfterCancel;
  assert.deepEqual([forOps.length, forOps[0].payment.razorpayOrderId, forOps[0].payment.capturedAfterCancelRazorpayPaymentId], [1, undefined, undefined], "staff see it to triage; the Razorpay ids are Finance's");
  const forFinance = (await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.finance)).body.collectedAfterCancel;
  assert.deepEqual([forFinance[0].payment.razorpayOrderId, forFinance[0].payment.capturedAfterCancelRazorpayPaymentId], ["order_held", "pay_held"]);

  const marked = await markRefunded(f.tokens.finance);
  assert.deepEqual([marked.status, marked.body.payment?.status], [200, "REFUNDED"], JSON.stringify(marked.body));
  assert.equal((await markRefunded(f.tokens.finance)).status, 200, "marking twice changes nothing");
  const audit = [...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()].filter((event) => event.action === "PAYMENT_MARKED_REFUNDED");
  assert.deepEqual(audit.map((event) => [event.resourceId, event.previousState, event.newState, event.actorUserId, event.razorpayPaymentId, event.source]),
    [[held, "CAPTURED_AFTER_CANCEL", "REFUNDED", f.finance.user.id, "pay_held", "USER"]]);
  const financeAudit = (await f.request("/v1/audit", "GET", undefined, f.tokens.finance)).body.events as Array<{ action: string }>;
  assert.equal(financeAudit.filter((event) => event.action === "PAYMENT_MARKED_REFUNDED").length, 1, "Finance reads the row");
  assert.deepEqual((await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.finance)).body.collectedAfterCancel, [], "off the list");

  webhook(f, "payment.captured", "pay_held", "order_held");
  assert.equal(paymentOf(f, held).status, "REFUNDED", "the same capture sent again does not bring it back");
});

test("the operations list marks a booking whose payment the partner settles outside NaviG8r", async t => {
  const f = await httpFixture(t);
  const erp = await book(f, f.trip.id);
  const held = await book(f, f.trip.id);
  setPayment(f, erp, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: undefined, razorpayPaymentId: undefined });
  setPayment(f, held, { provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: "order_held", razorpayPaymentId: "pay_held" });
  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "ROUTE_CHANGED" }, f.tokens.carrierA)).status, 200);
  const listed = (await f.request("/ops/trip-cancel-requests", "GET", undefined, f.tokens.ops)).body.requests[0].shipments as Array<{ shipment: { id: string }; settledOutsideNaviG8r: boolean }>;
  assert.deepEqual(listed.map((row) => [row.shipment.id, row.settledOutsideNaviG8r]), [[erp, true], [held, false]]);
});

test("a booking on a trip its carrier asked to cancel cannot be accepted or delivered until the request is withdrawn", async t => {
  const f = await httpFixture(t);
  const driver = await hireDriver(f);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA)).status, 200);
  const accepted = await book(f, f.trip.id);
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${accepted}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  const waiting = await book(f, f.trip.id);
  assert.equal((await askToCancel(f, f.trip.id, { reasonCode: "TRUCK_UNAVAILABLE" }, f.tokens.carrierA)).status, 200);

  const accept = await f.request(`/v1/pilot/carrier/shipments/${waiting}/accept`, "POST", {}, f.tokens.carrierA);
  assert.deepEqual([accept.status, accept.body.error, accept.body.detail],
    [409, "trip_cancel_requested", "This trip's carrier asked NaviG8r to cancel it, so it cannot take this booking now."]);
  const byDriver = await f.request(`/v1/pilot/carrier/shipments/${waiting}/accept`, "POST", {}, driver.token);
  assert.deepEqual([byDriver.status, byDriver.body.detail], [409, "This trip's carrier asked NaviG8r to cancel it, so it cannot take this booking now."],
    "the driver did not ask and cannot withdraw, so the sentence tells nobody to");
  assert.equal(f.store.shipments.get(waiting)?.status, "PENDING_CARRIER_ACCEPT");
  const pod = await f.request(`/shipments/${accepted}/driver-pod`, "POST", {}, driver.token);
  assert.deepEqual([pod.status, pod.body.error, pod.body.detail],
    [409, "trip_cancel_requested", "This trip's carrier asked NaviG8r to cancel it, so delivery cannot be confirmed now."]);
  assert.equal(f.store.shipments.get(accepted)?.status, "BOOKED", "so the trip is never left waiting with no booking to cancel");

  assert.equal((await withdraw(f, f.trip.id, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${waiting}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
});
