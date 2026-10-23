// Owner decision, 15 Oct 2026: a driver never sees carrier earnings, nor when they are paid. Owners, owner-drivers
// and dispatchers keep them, as do finance and ops. Shippers keep only their own payment hold.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { addTestPodPhoto } from "../test/fixtures.ts";
import { authorizationContext, effectivePermissions, resolvePrincipal } from "./rbac.ts";
import { serializeResponse } from "./rbacResponses.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

const payoutFields = ["firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "paidAtUtcMs", "paymentReady", "paymentHoldUntilUtcMs"];

/** Carrier A with a driver on the fixture's trip, plus a dispatcher and an owner, all signed in. */
async function carrierWithStaff(t: TestContext) {
  const f = await httpFixture(t);
  const orgId = f.carrierA.org.id;
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000015", role: "DISPATCHER" });
  // No route invites an OWNER; ops onboarding makes one, so the membership is written directly.
  const owner = registerCustomerUser(f.store, { fullName: "Synthetic Owner", phone: "8000000016" });
  f.store.memberships.set(`${owner.user.id}:${orgId}`, { userId: owner.user.id, orgId, role: "OWNER", createdAtUtcMs: Date.now() });
  const tokens = { driver: await f.login("8000000013"), dispatcher: await f.login("8000000015"), owner: await f.login("8000000016"), ownerDriver: f.tokens.carrierA };
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, tokens.ownerDriver)).status, 200);
  return { f, orgId, driver, tokens };
}

test("only a driver loses payment.read", () => {
  assert.equal(effectivePermissions(["CARRIER"], "DRIVER").includes("payment.read"), false);
  for (const subrole of ["OWNER_DRIVER", "OWNER", "DISPATCHER"]) {
    assert.equal(effectivePermissions(["CARRIER"], subrole).includes("payment.read"), true, subrole);
  }
  assert.equal(effectivePermissions(["SHIPPER"], "CUSTOMER_ADMIN").includes("payment.read"), true);
});

test("a driver gets 403 on earnings, ledger and payout batches, and no carrier money or payment event anywhere; the office keeps them", async t => {
  const { f, orgId, tokens } = await carrierWithStaff(t);
  const delivered = (await f.book()).body.shipment.id as string;
  const accepted = await f.request(`/v1/pilot/carrier/shipments/${delivered}/accept`, "POST", {}, tokens.driver);
  assert.equal(accepted.status, 200);
  const refunded = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${refunded}/accept`, "POST", {}, tokens.ownerDriver)).status, 200);
  addTestPodPhoto(f.store, delivered);
  const delivery = await f.request(`/shipments/${delivered}/driver-pod`, "POST", {}, tokens.driver);
  assert.equal(delivery.status, 200);
  assert.equal((await f.request(`/shipments/${refunded}/fail-refund`, "POST", {}, f.tokens.finance)).status, 200, "a payment status changes");

  for (const route of ["earnings", "ledger", "payout-batches"]) {
    const path = `/v1/pilot/carrier/${route}?orgId=${orgId}`;
    assert.equal((await f.request(path, "GET", undefined, tokens.driver)).status, 403, route);
    for (const [who, token] of Object.entries({ owner: tokens.owner, ownerDriver: tokens.ownerDriver, dispatcher: tokens.dispatcher })) {
      assert.equal((await f.request(path, "GET", undefined, token)).status, 200, `${who} ${route}`);
    }
  }

  const get = async (path: string, token: string) => {
    const response = await f.request(path, "GET", undefined, token);
    assert.equal(response.status, 200, path);
    return response.body;
  };
  assert.equal(((await get("/v1/pilot/carrier/shipments", tokens.driver)).shipments as unknown[]).length, 2, "the driver sees both shipments");
  const driverSees = [
    accepted.body, delivery.body,
    await get("/v1/pilot/carrier/shipments", tokens.driver),
    await get(`/v1/pilot/carrier/shipments?anchorTripId=${f.trip.id}`, tokens.driver),
    await get(`/shipments/${delivered}/tracking`, tokens.driver),
    await get("/v1/pilot/anchor-trips", tokens.driver),
    await get(`/v1/pilot/anchor-trips/${f.trip.id}`, tokens.driver),
    await get("/v1/pilot/me", tokens.driver),
    await get("/v1/notifications", tokens.driver),
    await get("/v1/notifications/shipments", tokens.driver),
    await get(`/v1/shipments/${refunded}/conversation/timeline`, tokens.driver),
  ];
  const driverText = JSON.stringify(driverSees);
  for (const money of ["Paise", "₹", "payment.status_changed", "Payment status", ...payoutFields]) {
    assert.equal(driverText.includes(money), false, `${money} reached the driver`);
  }
  assert.ok(((await get("/v1/notifications", tokens.driver)).notifications as unknown[]).length > 0, "the driver still hears about the trip");

  for (const [who, token] of Object.entries({ owner: tokens.owner, ownerDriver: tokens.ownerDriver, dispatcher: tokens.dispatcher })) {
    const rows = (await get("/v1/pilot/carrier/shipments", token)).shipments as Array<{ id: string; netToCarrierPaise?: number }>;
    assert.equal(typeof rows.find((row) => row.id === delivered)?.netToCarrierPaise, "number", `${who} still sees net to carrier`);
    const heard = (await get("/v1/notifications", token)).notifications as Array<{ eventKey: string; shipmentId: string }>;
    // Owner, 21 Oct 2026: dispatchers keep the money figures but get no payment notices.
    const toldOfPayment = heard.some((item) => item.eventKey === "payment.status_changed" && item.shipmentId === refunded);
    assert.equal(toldOfPayment, who !== "dispatcher", `${who} ${who === "dispatcher" ? "is not" : "is"} told about the payment`);
  }
  const summary = (await get(`/v1/pilot/carrier/earnings?orgId=${orgId}`, tokens.ownerDriver)).summary as Record<string, unknown>;
  assert.equal(typeof summary.pendingAccruedPaise, "number");
});

test("a driver gets no payout dates or payment hold, even once delivered; the office, finance and ops keep them, and the shipper keeps only its payment hold", async t => {
  const { f, tokens } = await carrierWithStaff(t);
  const id = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, tokens.driver)).status, 200);
  addTestPodPhoto(f.store, id);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, tokens.driver)).status, 200);
  assert.equal((await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperA)).status, 200);
  assert.equal((await f.request(`/ops/shipments/${id}/release`, "POST", {}, f.tokens.finance)).status, 200, "delivered, so the payout dates are set");
  const shipmentFor = async (path: string, token: string): Promise<Record<string, unknown>> => {
    const response = await f.request(path, "GET", undefined, token);
    assert.equal(response.status, 200, path);
    const body = response.body as { shipment?: Record<string, unknown>; shipments?: Array<Record<string, unknown>> };
    const shipment = body.shipment ?? body.shipments?.find((row) => row.id === id);
    if (!shipment) throw new Error(`${path} has no shipment ${id}`);
    return shipment;
  };

  for (const path of ["/v1/pilot/carrier/shipments", `/shipments/${id}/tracking`]) {
    const shipment = await shipmentFor(path, tokens.driver);
    assert.equal(shipment.status, "DELIVERED");
    for (const field of payoutFields) assert.equal(field in shipment, false, `${field} reached the driver on ${path}`);
  }
  const keepers: Array<[string, string, string]> = [
    ["owner", "/v1/pilot/carrier/shipments", tokens.owner],
    ["owner-driver", "/v1/pilot/carrier/shipments", tokens.ownerDriver],
    ["dispatcher", "/v1/pilot/carrier/shipments", tokens.dispatcher],
    ["shipper", `/shipments/${id}`, f.tokens.shipperA],
    ["finance", `/ops/shipments/${id}`, f.tokens.finance],
    ["ops", `/ops/shipments/${id}`, f.tokens.ops],
  ];
  for (const [who, path, token] of keepers) {
    const shipment = await shipmentFor(path, token);
    for (const field of ["firstPayoutEligibleAtUtcMs", "payoutBatchCutoffUtcMs", "paymentHoldUntilUtcMs"]) {
      // When the carrier is paid is not the shipper's business (owner hard rule, 21 Oct 2026).
      const kept = who !== "shipper" || field === "paymentHoldUntilUtcMs";
      assert.equal(typeof shipment[field], kept ? "number" : "undefined", `${who} ${kept ? "keeps" : "does not get"} ${field}`);
    }
    assert.equal(shipment.paymentReady, true, `${who} keeps paymentReady`);
  }
});

test("pay fields with no branch of their own are dropped for a driver and kept for the office", async t => {
  const { f, driver } = await carrierWithStaff(t);
  const payouts = {
    summary: { pendingAccruedPaise: 100, paidPaise: 200, bookedCount: 1 },
    lines: [{ id: "line-1", shipmentId: "shipment-1", carrierId: f.carrierA.org.id, status: "PAID", podAtUtcMs: 1, firstPayoutEligibleAtUtcMs: 2, payoutBatchCutoffUtcMs: 3, paidAtUtcMs: 4, createdAtUtcMs: 1, netToCarrierPaise: 300 }],
    payoutBatches: [{ id: "batch-1", cutoffUtcMs: 3, createdAtUtcMs: 4, totalNetToCarrierPaise: 300, transfers: [{ carrierId: f.carrierA.org.id, netToCarrierPaise: 300 }] }],
  };
  const serializedFor = (userId: string) => JSON.stringify(authorizationContext.run({ principal: resolvePrincipal(f.store, userId), requestId: "synthetic" }, () => serializeResponse(payouts)));
  const forDriver = serializedFor(driver.user.id);
  for (const field of ["Paise", "cutoffUtcMs", ...payoutFields]) assert.equal(forDriver.includes(field), false, `${field}: ${forDriver}`);
  for (const kept of ["bookedCount", "line-1", "batch-1", "transfers"]) assert.ok(forDriver.includes(kept), `${kept} stays`);
  assert.equal(serializedFor(f.carrierA.user.id), JSON.stringify(payouts), "the owner-driver gets it all");
});

test("a payment notice written to a driver before 15 Oct is never returned to them", async t => {
  const { f, orgId, driver, tokens } = await carrierWithStaff(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, tokens.driver)).status, 200);
  const before = await f.request("/v1/notifications", "GET", undefined, tokens.driver);
  const groupedBefore = await f.request("/v1/notifications/shipments", "GET", undefined, tokens.driver);
  // Rows from before the owner's decision still sit in the store, addressed to the driver.
  f.store.notifications.set("old-payment-notice", {
    id: "old-payment-notice", recipientSequence: ++f.store.notificationSequence,
    eventId: `payment:old:${shipmentId}`, eventKey: "payment.status_changed",
    recipientUserId: driver.user.id, recipientOrgId: orgId,
    shipmentId, conversationId: shipmentId, createdAtUtcMs: Date.now(),
    data: { shipmentId, audience: "CARRIER", title: "Payment status changed", body: "Payment status changed" },
  });

  const flat = await f.request("/v1/notifications", "GET", undefined, tokens.driver);
  assert.equal(flat.status, 200);
  assert.equal(JSON.stringify(flat.body).includes("payment."), false, "no payment notice in the list");
  assert.equal(flat.body.unreadCount, before.body.unreadCount, "nor in the unread count");
  const grouped = await f.request("/v1/notifications/shipments", "GET", undefined, tokens.driver);
  assert.equal(grouped.body.unreadCount, groupedBefore.body.unreadCount, "nor in the inbox count");
  const timeline = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, tokens.driver);
  assert.equal(timeline.status, 200);
  assert.equal(JSON.stringify(timeline.body).includes("payment."), false, "nor in the shipment's messages");
});

test("a stored payment notice cannot be opened or marked read by a driver or dispatcher; the owner's can", async t => {
  const { f, orgId, driver, tokens } = await carrierWithStaff(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, tokens.driver)).status, 200);
  const memberWith = (role: string) => [...f.store.memberships.values()].find(m => m.orgId === orgId && m.role === role)!.userId;
  const dispatcherId = memberWith("DISPATCHER");
  const ownerId = memberWith("OWNER");
  for (const [id, userId] of [["driver-payment", driver.user.id], ["dispatcher-payment", dispatcherId], ["owner-payment", ownerId]] as const) {
    f.store.notifications.set(id, {
      id, recipientSequence: ++f.store.notificationSequence,
      eventId: `payment:${id}:${shipmentId}`, eventKey: "payment.status_changed",
      recipientUserId: userId, recipientOrgId: orgId,
      shipmentId, conversationId: shipmentId, createdAtUtcMs: Date.now(),
      data: { shipmentId, audience: "CARRIER", title: "Payment status changed", body: "Payment status changed" },
    });
  }

  for (const [who, id] of [["driver", "driver-payment"], ["dispatcher", "dispatcher-payment"]] as const) {
    const opened = await f.request(`/v1/notifications/${id}/open`, "POST", {}, tokens[who]);
    assert.equal(opened.status, 404, `${who}: an old push for it opens nothing`);
    const marked = await f.request(`/v1/notifications/${id}/read`, "PATCH", {}, tokens[who]);
    assert.equal(marked.status, 404, `${who}: it does not exist to mark`);
    assert.equal(f.store.notifications.get(id)!.readAtUtcMs, undefined, `${who}: the row is untouched`);
  }
  assert.equal((await f.request("/v1/notifications/owner-payment/open", "POST", {}, tokens.owner)).status, 200, "the owner opens theirs");
  const ownerMarked = await f.request("/v1/notifications/owner-payment/read", "PATCH", {}, tokens.owner);
  assert.equal(ownerMarked.status, 200, "and marks it read");
});

test("a driver's refused delivery confirmation says nothing of the payment's state", async t => {
  const { f, tokens } = await carrierWithStaff(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, tokens.driver)).status, 200);
  // The payment has not gone through: a Razorpay order still waiting for the shipper.
  const shipment = f.store.shipments.get(shipmentId)!;
  const payment = f.store.payments.get(shipment.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, provider: "RAZORPAY", status: "CREATED" });

  const refused = await f.request(`/shipments/${shipmentId}/driver-pod`, "POST", {}, tokens.driver);
  assert.equal(refused.status, 400);
  assert.equal(refused.body.error, "checkout_not_completed_for_pod");
  assert.equal("status" in refused.body, false, "no payment status");
  assert.doesNotMatch(JSON.stringify(refused.body), /CREATED|payment/i, "no payment words");
});
