import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";
import { FakePage, inlineScript } from "../test/fakePage.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

const rupees = (paise: number) => "₹" + (paise / 100).toLocaleString("en-IN", { minimumFractionDigits: paise % 100 ? 2 : 0, maximumFractionDigits: 2 });

/** Two bookings on the fixture's trip, then the carrier asks NaviG8r to cancel it. */
async function requestedTrip(f: Fixture): Promise<string[]> {
  const ids: string[] = [];
  for (const weightKg of [10, 20]) {
    const booked = await f.book(f.tokens.shipperA, { weightKg });
    assert.equal(booked.status, 201);
    ids.push(booked.body.shipment.id);
  }
  const asked = await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/cancel-request`, "POST", { reasonCode: "ROUTE_CHANGED", note: "Client moved the date" }, f.tokens.carrierA);
  assert.equal(asked.status, 200);
  return ids;
}

async function openOpsBeta(f: Fixture, token: string): Promise<FakePage> {
  const page = new FakePage(f.base);
  page.session.set("navig8r_access", token);
  page.run(inlineScript(await (await fetch(f.base + "/ops/beta")).text()));
  await page.settle();
  return page;
}

test("/ops/beta lists each trip a carrier asked to cancel, with its reason, note and bookings; only FINANCE gets Cancel shipment, and it asks in the page first", async t => {
  const f = await httpFixture(t);
  const [first, second] = await requestedTrip(f);
  const heldPayment = f.store.payments.get(f.store.shipments.get(second)!.paymentId)!;
  f.store.payments.set(heldPayment.id, { ...heldPayment, provider: "RAZORPAY", status: "AUTHORIZED", razorpayPaymentId: "pay_held" });
  const page = await openOpsBeta(f, f.tokens.finance);
  const body = page.byId("tripCancelsBody");
  for (const words of ["A to B", "Synthetic Carrier A", "Reason: Route changed", "Note from the carrier: Client moved the date", first, second, "Synthetic Shipper A", "Payment collected", "Payment held, not collected",
    "The trip takes no new bookings. When the last shipment below is cancelled, the trip is cancelled too."]) {
    assert.ok(body.textContent.includes(words), `the card shows: ${words}`);
  }
  assert.equal(page.byId("countTripCancels").textContent, "1");
  const row = body.descendants().find((node) => node.tagName === "tr" && node.textContent.includes(first))!;

  await page.click(page.visibleButton("Cancel shipment…", row)!);
  const amount = rupees(f.store.payments.get(f.store.shipments.get(first)!.paymentId)!.amountPaise);
  assert.ok(row.textContent.includes(`Cancel shipment ${first} for Synthetic Shipper A? ${amount} is refunded to the shipper. The shipper is told. This can't be undone from the console.`), row.textContent);
  assert.equal(page.focused?.textContent, "Keep shipment", "a stray Enter keeps the shipment");
  await page.click(page.visibleButton("Keep shipment", row)!);
  assert.equal(page.requests.some((request) => request.path.endsWith("/fail-refund")), false, "asking sends nothing");
  assert.equal(f.store.shipments.get(first)?.status, "PENDING_CARRIER_ACCEPT");

  await page.click(page.visibleButton("Cancel shipment…", row)!);
  await page.click(page.visibleButton("Cancel shipment", row)!);
  assert.deepEqual(page.requests.filter((request) => request.method === "POST").map((request) => request.path), [`/shipments/${first}/fail-refund`]);
  assert.equal(f.store.shipments.get(first)?.status, "FAILED_CARRIER_REFUNDED");
  assert.ok(row.textContent.includes("The shipper is told."), row.textContent);
  assert.equal(page.nativeDialogs, 0, "no browser confirm or alert");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "CANCEL_REQUESTED", "one booking is still on the trip");

  const heldRow = body.descendants().find((node) => node.tagName === "tr" && node.textContent.includes(second))!;
  await page.click(page.visibleButton("Cancel shipment…", heldRow)!);
  assert.ok(heldRow.textContent.includes(`${rupees(heldPayment.amountPaise)} was never collected. Nothing is sent to Razorpay: it returns the money within 3 days of when the shipper paid.`), heldRow.textContent);
  await page.click(page.visibleButton("Cancel shipment", heldRow)!);
  assert.ok(heldRow.textContent.includes("Hold released"), heldRow.textContent);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "CANCELLED", "the last booking cancelled ends the trip");
});

test("/ops/beta shows OPS the requests but no way to cancel a shipment, and says FINANCE does it", async t => {
  const f = await httpFixture(t);
  const [first] = await requestedTrip(f);
  const page = await openOpsBeta(f, f.tokens.ops);
  const body = page.byId("tripCancelsBody");
  assert.ok(body.textContent.includes(first) && body.textContent.includes("Reason: Route changed"), body.textContent);
  assert.equal(page.visibleButton("Cancel shipment…", body), undefined);
  const off = body.querySelectorAll("button").filter((button) => button.textContent === "Cancel shipment");
  assert.equal(off.length, 2);
  assert.ok(off.every((button) => button.disabled), "shown, but off");
  assert.ok(body.textContent.includes("Finance cancels each shipment. You hold OPS."), body.textContent);
});

test("/ops/beta: Cancel shipment after the carrier withdrew says so and changes nothing; a failed Razorpay refund sends Finance to the dashboard", async t => {
  const f = await httpFixture(t);
  const [first, second] = await requestedTrip(f);
  const collected = f.store.payments.get(f.store.shipments.get(second)!.paymentId)!;
  f.store.payments.set(collected.id, { ...collected, provider: "RAZORPAY", status: "CAPTURED", razorpayPaymentId: "pay_collected" });
  const saved = { id: process.env.RAZORPAY_KEY_ID, secret: process.env.RAZORPAY_KEY_SECRET };
  delete process.env.RAZORPAY_KEY_ID;
  delete process.env.RAZORPAY_KEY_SECRET;
  t.after(() => {
    if (saved.id !== undefined) process.env.RAZORPAY_KEY_ID = saved.id;
    if (saved.secret !== undefined) process.env.RAZORPAY_KEY_SECRET = saved.secret;
  });
  const page = await openOpsBeta(f, f.tokens.finance);
  const body = page.byId("tripCancelsBody");
  const rowOf = (id: string) => body.descendants().find((node) => node.tagName === "tr" && node.textContent.includes(id))!;

  const failing = rowOf(second);
  await page.click(page.visibleButton("Cancel shipment…", failing)!);
  await page.click(page.visibleButton("Cancel shipment", failing)!);
  assert.ok(failing.textContent.includes("Couldn't cancel the shipment: the refund call to Razorpay failed. Check the payment in the Razorpay dashboard before trying again."), failing.textContent);
  assert.equal(failing.textContent.includes("Nothing changed."), false, "the call may have reached Razorpay");

  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/cancel-request/withdraw`, "POST", {}, f.tokens.carrierA)).status, 200);
  const stale = rowOf(first);
  await page.click(page.visibleButton("Cancel shipment…", stale)!);
  await page.click(page.visibleButton("Cancel shipment", stale)!);
  assert.ok(stale.textContent.includes("Couldn't cancel the shipment: the carrier withdrew this request. Nothing changed."), stale.textContent);
  assert.equal(f.store.shipments.get(first)?.status, "PENDING_CARRIER_ACCEPT", "the withdrawn request cancels nothing");
});

/** The first booking cancelled, then Razorpay captured its money: the payment as the webhook leaves it. */
async function collectedAfterCancel(f: Fixture): Promise<{ shipmentId: string; amountPaise: number }> {
  const [first] = await requestedTrip(f);
  const payment = f.store.payments.get(f.store.shipments.get(first)!.paymentId)!;
  f.store.shipments.set(first, { ...f.store.shipments.get(first)!, status: "FAILED_CARRIER_REFUNDED" });
  f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", status: "CAPTURED_AFTER_CANCEL", razorpayOrderId: "order_late", razorpayPaymentId: "pay_earlier", capturedAfterCancelRazorpayPaymentId: "pay_late" });
  return { shipmentId: first!, amountPaise: payment.amountPaise };
}

test("/ops/beta shows Finance a payment Razorpay captured after its shipment was cancelled, with its Razorpay ids", async t => {
  const f = await httpFixture(t);
  const { shipmentId, amountPaise } = await collectedAfterCancel(f);
  const page = await openOpsBeta(f, f.tokens.finance);
  const body = page.byId("tripCancelsBody");
  for (const words of [shipmentId, "Synthetic Shipper A, " + rupees(amountPaise), "Money collected after cancel. Refund it in the Razorpay dashboard, then mark it refunded here.",
    "Razorpay order order_late · payment pay_late"]) {
    assert.ok(body.textContent.includes(words), `the card shows: ${words}`);
  }
  assert.equal(body.textContent.includes("pay_earlier"), false, "the capture's own id, not the earlier one");
  assert.equal(page.byId("countTripCancels").textContent, "2", "one trip and one payment to refund");
});

test("/ops/beta: Finance marks it refunded in Razorpay after a question naming the payment and amount; the row and its count go", async t => {
  const f = await httpFixture(t);
  const { shipmentId, amountPaise } = await collectedAfterCancel(f);
  const page = await openOpsBeta(f, f.tokens.finance);
  const body = page.byId("tripCancelsBody");
  const row = body.descendants().find((node) => node.getAttribute?.("aria-label") === "Money collected after cancel, " + shipmentId)!;
  assert.ok(row, "the row");

  await page.click(page.visibleButton("Mark refunded in Razorpay…", row)!);
  assert.ok(row.textContent.includes(`Mark payment pay_late of ${rupees(amountPaise)} as refunded? Do this only once you have refunded it in the Razorpay dashboard. The shipper's screen then says it is refunded. This can't be undone from the console.`), row.textContent);
  assert.equal(page.focused?.textContent, "Not yet", "a stray Enter changes nothing");
  await page.click(page.visibleButton("Not yet", row)!);
  assert.equal(page.requests.some((request) => request.path.endsWith("/mark-refunded")), false, "asking sends nothing");

  await page.click(page.visibleButton("Mark refunded in Razorpay…", row)!);
  await page.click(page.visibleButton("Mark refunded", row)!);
  assert.deepEqual(page.requests.filter((request) => request.method === "POST").map((request) => request.path), [`/shipments/${shipmentId}/mark-refunded`]);
  assert.equal(f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!.status, "REFUNDED");
  assert.ok(row.textContent.includes("Marked refunded by you at"), row.textContent);
  assert.equal(page.visibleButton("Mark refunded in Razorpay…", row), undefined, "the row's action is gone");
  assert.equal(page.byId("countTripCancels").textContent, "1", "only the trip is left");
  assert.equal(page.byId("tripCancelsCount").textContent, "1 trip");
  assert.equal(page.nativeDialogs, 0);
});

test("/ops/beta: when Razorpay captured a second payment on the shipment, marking the first says the second is still to refund", async t => {
  const f = await httpFixture(t);
  const { shipmentId } = await collectedAfterCancel(f);
  applyRazorpayWebhookPayload(f.store, { event: "payment.captured", payload: { payment: { entity: { id: "pay_later", order_id: "order_late" } } } });
  const page = await openOpsBeta(f, f.tokens.finance);
  const row = page.byId("tripCancelsBody").descendants().find((node) => node.getAttribute?.("aria-label") === "Money collected after cancel, " + shipmentId)!;
  await page.click(page.visibleButton("Mark refunded in Razorpay…", row)!);
  await page.click(page.visibleButton("Mark refunded", row)!);
  const payment = f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;
  assert.deepEqual([payment.status, payment.capturedAfterCancelRazorpayPaymentId], ["CAPTURED_AFTER_CANCEL", "pay_later"]);
  assert.ok(row.textContent.includes("Razorpay also collected payment pay_later on this shipment. It shows here to refund on the next reload."), row.textContent);
  assert.equal(page.byId("countTripCancels").textContent, "2", "the shipment still has money to refund");
});

test("/ops/beta shows OPS the payment collected after the cancel, but only Finance gets the action", async t => {
  const f = await httpFixture(t);
  const { shipmentId } = await collectedAfterCancel(f);
  const page = await openOpsBeta(f, f.tokens.ops);
  const body = page.byId("tripCancelsBody");
  assert.ok(body.textContent.includes(shipmentId), body.textContent);
  assert.ok(body.textContent.includes("Money collected after cancel. Finance refunds this in the Razorpay dashboard."), body.textContent);
  assert.equal(page.visibleButton("Mark refunded in Razorpay…", body), undefined);
});

test("/ops/beta: a booking the partner settles outside NaviG8r claims no Razorpay hold and its Cancel shipment is off, saying why", async t => {
  const f = await httpFixture(t);
  const [first] = await requestedTrip(f);
  const payment = f.store.payments.get(f.store.shipments.get(first)!.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", status: "AUTHORIZED", razorpayOrderId: undefined, razorpayPaymentId: undefined });
  const page = await openOpsBeta(f, f.tokens.finance);
  const row = page.byId("tripCancelsBody").descendants().find((node) => node.tagName === "tr" && node.textContent.includes(first!))!;
  assert.equal(row.textContent.includes("Payment held"), false, row.textContent);
  assert.ok(row.textContent.includes("Settled outside NaviG8r"), row.textContent);
  assert.equal(page.visibleButton("Cancel shipment…", row), undefined);
  const off = row.querySelectorAll("button").filter((button) => button.textContent === "Cancel shipment");
  assert.ok(off.length === 1 && off[0]!.disabled, "shown, but off");
  assert.ok(row.textContent.includes("This load's payment is settled outside NaviG8r through the partner's system, so it cannot be cancelled here. Ask the carrier to withdraw the request, or settle it with the partner."), row.textContent);
});

test("/ops/beta says so when no carrier has asked to cancel a trip", async t => {
  const f = await httpFixture(t);
  const page = await openOpsBeta(f, f.tokens.ops);
  assert.ok(page.byId("tripCancelsBody").textContent.includes("No carrier has asked to cancel a trip."));
  assert.equal(page.byId("countTripCancels").textContent, "0");
});
