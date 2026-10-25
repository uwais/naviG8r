// Owner hard rule, 21 Oct 2026: a carrier never learns what the shipper pays, a shipper never learns what the
// carrier gets, and neither learns NaviG8r's cut. Only NaviG8r's own pages carry both.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { addTestPodPhoto, startTestTrip } from "../test/fixtures.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";
import { authorizationContext, resolvePrincipal } from "./rbac.ts";
import { serializeResponse } from "./rbacResponses.ts";
import { getIntegrationShipmentSnapshot, getIntegrationShipmentTracking, listIntegrationEvents, updateIntegrationConnection } from "./integrationServices.ts";

const carrierAmountKeys = new Set(["netToCarrierPaise", "totalNetToCarrierPaise", "pendingAccruedPaise", "paidPaise"]);

function keysIn(body: unknown): string[] {
  return [...JSON.stringify(body).matchAll(/"([A-Za-z_]+)":/g)].map(match => match[1]!);
}

/** Any amount key other than the carrier's own, or anything naming the cut or the shipper's price. */
function shipperPriceKeys(body: unknown): string[] {
  return keysIn(body).filter(key => (/Paise$/.test(key) && !carrierAmountKeys.has(key)) || /commission|gross|amount|fee|bps/i.test(key));
}

/** The carrier's amount, the cut, and anything about paying the carrier out. */
function carrierAmountKeysIn(body: unknown): string[] {
  return keysIn(body).filter(key => carrierAmountKeys.has(key) || /commission|netToCarrier|payout|ledger|bps/i.test(key));
}

/** A delivered shipment on carrier A's trip, driven by its driver, with an owner, a dispatcher and an ERP webhook. */
async function deliveredShipment(t: TestContext) {
  const f = await httpFixture(t);
  const orgId = f.carrierA.org.id;
  updateIntegrationConnection(f.store, f.shipperA.org.id, { webhookUrl: "https://erp.example.com/hook", paymentPolicy: "erp_preauthorized", changedByUserId: f.ops.userId });
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000015", role: "DISPATCHER" });
  // No route invites an OWNER; ops onboarding makes one, so the membership is written directly.
  const owner = registerCustomerUser(f.store, { fullName: "Synthetic Owner", phone: "8000000016" });
  f.store.memberships.set(`${owner.user.id}:${orgId}`, { userId: owner.user.id, orgId, role: "OWNER", createdAtUtcMs: Date.now() });
  const carrier = { driver: await f.login("8000000013"), dispatcher: await f.login("8000000015"), owner: await f.login("8000000016"), ownerDriver: f.tokens.carrierA };
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, carrier.ownerDriver)).status, 200);

  const booked = await f.book();
  assert.equal(booked.status, 201);
  const id = booked.body.shipment.id as string;
  const accepted = await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, carrier.dispatcher);
  assert.equal(accepted.status, 200);
  startTestTrip(f.store, id);
  addTestPodPhoto(f.store, id);
  const delivery = await f.request(`/shipments/${id}/driver-pod`, "POST", {}, carrier.driver);
  assert.equal(delivery.status, 200);
  const podAccepted = await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperA);
  assert.equal(podAccepted.status, 200);
  assert.equal((await f.request(`/ops/shipments/${id}/release`, "POST", {}, f.tokens.finance)).status, 200, "delivered: ledger line and payout dates exist");
  await f.request(`/v1/shipments/${id}/conversation/messages`, "POST", { body: "Reached the gate.", clientRequestId: "synthetic-1" }, carrier.ownerDriver);
  return { f, id, orgId, carrier, responses: { booked: booked.body, accepted: accepted.body, delivery: delivery.body, podAccepted: podAccepted.body } };
}

test("no carrier login gets the shipper's price, the cut or a fee rate, on any route it can reach", async t => {
  const { f, id, orgId, carrier, responses } = await deliveredShipment(t);
  for (const [who, token] of Object.entries(carrier)) {
    const seen: Record<string, unknown> = who === "dispatcher" ? { accepted: responses.accepted } : who === "driver" ? { delivery: responses.delivery } : {};
    const paths = [
      "/v1/pilot/carrier/shipments", `/v1/pilot/carrier/shipments?anchorTripId=${f.trip.id}`, `/shipments/${id}/tracking`,
      "/v1/pilot/anchor-trips", `/v1/pilot/anchor-trips/${f.trip.id}`, "/v1/pilot/me", "/v1/auth/me",
      "/v1/notifications", "/v1/notifications/shipments",
      `/v1/shipments/${id}/conversation/timeline`, `/v1/shipments/${id}/conversation/messages`,
      ...(who === "driver" ? [] : [`/v1/pilot/carrier/earnings?orgId=${orgId}`, `/v1/pilot/carrier/ledger?orgId=${orgId}`, `/v1/pilot/carrier/payout-batches?orgId=${orgId}`]),
    ];
    for (const path of paths) {
      const response = await f.request(path, "GET", undefined, token);
      assert.equal(response.status, 200, `${who} ${path}`);
      seen[path] = response.body;
    }
    const estimate = await f.request("/v1/pilot/rates/estimate", "POST", { origin: { lat: 12.97, lng: 77.59 }, destination: { lat: 13.08, lng: 80.27 }, vehicleClass: "MEDIUM" }, token);
    assert.equal(estimate.status, 200, `${who} rate estimate`);
    seen.estimate = estimate.body;
    for (const [path, body] of Object.entries(seen)) assert.deepEqual(shipperPriceKeys(body), [], `${who} ${path}`);
    if (who !== "driver") {
      const rows = (seen["/v1/pilot/carrier/shipments"] as { shipments: Array<{ id: string; netToCarrierPaise?: number }> }).shipments;
      assert.equal(typeof rows.find(row => row.id === id)?.netToCarrierPaise, "number", `${who} still sees what the carrier receives`);
    }
  }
});

test("a rate estimate gives the carrier office its own amount, and a driver no amount", async t => {
  const { f, carrier } = await deliveredShipment(t);
  const ask = (token: string) => f.request("/v1/pilot/rates/estimate", "POST", { origin: { lat: 12.97, lng: 77.59 }, destination: { lat: 13.08, lng: 80.27 }, vehicleClass: "MEDIUM", sampleWeightsKg: [100] }, token);
  const office = (await ask(carrier.owner)).body as { samples: Array<Record<string, unknown>> };
  assert.equal(typeof office.samples[0]!.netToCarrierPaise, "number");
  const driver = (await ask(carrier.driver)).body as { samples: Array<Record<string, unknown>> };
  assert.deepEqual(Object.keys(driver.samples[0]!), ["weightKg"]);
});

test("no shipper login gets the carrier's amount, the cut, payout dates or ledger data", async t => {
  const { f, id, responses } = await deliveredShipment(t);
  const seen: Record<string, unknown> = { booked: responses.booked, podAccepted: responses.podAccepted };
  const paths = [
    "/shipments", `/shipments/${id}`, `/shipments/${id}/tracking`, "/v1/pilot/me", "/v1/auth/me",
    "/v1/notifications", "/v1/notifications/shipments",
    `/v1/shipments/${id}/conversation/timeline`, `/v1/shipments/${id}/conversation/messages`,
    `/v1/pilot/customer/integrations?orgId=${f.shipperA.org.id}`,
  ];
  for (const path of paths) {
    const response = await f.request(path, "GET", undefined, f.tokens.shipperA);
    assert.equal(response.status, 200, path);
    seen[path] = response.body;
  }
  for (const [path, body] of Object.entries(seen)) assert.deepEqual(carrierAmountKeysIn(body), [], path);
  const shipment = (seen[`/shipments/${id}`] as { shipment: Record<string, unknown> }).shipment;
  assert.equal(typeof shipment.grossPaise, "number", "the shipper still sees its own price");
  assert.equal(shipment.paymentReady, true, "and when its payment is taken");
});

test("a shipper's ERP gets no carrier amount, cut or payout data from the API or the webhook", async t => {
  const { f, id } = await deliveredShipment(t);
  const orgId = f.shipperA.org.id;
  const deliveries = [...f.store.integrationWebhookDeliveries.values()].filter(delivery => delivery.orgId === orgId);
  assert.ok(deliveries.length >= 3, "webhooks were queued for the shipment's events");
  const seen: Record<string, unknown> = {
    snapshot: getIntegrationShipmentSnapshot(f.store, orgId, id),
    tracking: getIntegrationShipmentTracking(f.store, orgId, id),
    events: listIntegrationEvents(f.store, orgId, { shipmentId: id }),
    webhooks: deliveries.map(delivery => JSON.parse(delivery.payloadJson)),
  };
  for (const [what, body] of Object.entries(seen)) assert.deepEqual(carrierAmountKeysIn(body), [], what);
  assert.equal(typeof (seen.snapshot as { grossPaise?: number }).grossPaise, "number", "the ERP still sees the shipper's price");
});

test("an object with no branch of its own still loses the other side's amounts", async t => {
  const f = await httpFixture(t);
  const unbranched = { estimate: { weightKg: 10, grossPaise: 1000, commissionPaise: 100, amountPaise: 1000, netToCarrierPaise: 900, totalNetToCarrierPaise: 900, firstPayoutEligibleAtUtcMs: 1 } };
  const serializedFor = (userId: string) => authorizationContext.run({ principal: resolvePrincipal(f.store, userId), requestId: "synthetic" }, () => serializeResponse(unbranched));
  assert.deepEqual(serializedFor(f.carrierA.user.id), { estimate: { weightKg: 10, netToCarrierPaise: 900, totalNetToCarrierPaise: 900, firstPayoutEligibleAtUtcMs: 1 } });
  assert.deepEqual(serializedFor(f.shipperA.user.id), { estimate: { weightKg: 10, grossPaise: 1000, amountPaise: 1000 } });
  assert.deepEqual(serializedFor(f.finance.user.id), unbranched, "NaviG8r's own logins keep both");
});
