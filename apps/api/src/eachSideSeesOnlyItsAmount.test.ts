// Owner hard rule, 21 Oct 2026: each side sees only its own amount. Only NaviG8r's own logins see both.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";
import { authorizationContext, resolvePrincipal } from "./rbac.ts";
import { leaveOutCarrierSide, serializeResponse } from "./rbacResponses.ts";
import { createIntegrationApiKey, getIntegrationShipmentSnapshot, getIntegrationShipmentTracking, listIntegrationEvents, updateIntegrationConnection } from "./integrationServices.ts";

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

/** Every response that carries a forbidden key, so one failure names all of them. */
function responsesWithKeys(seen: Record<string, unknown>, forbiddenKeys: (body: unknown) => string[]): Record<string, string[]> {
  return Object.fromEntries(Object.entries(seen).map(([what, body]) => [what, forbiddenKeys(body)]).filter(([, keys]) => keys.length > 0));
}

/** A delivered shipment on carrier A's trip, driven by its driver, with an owner, a dispatcher and an ERP webhook. */
async function deliveredShipment(t: TestContext) {
  const f = await httpFixture(t);
  const orgId = f.carrierA.org.id;
  updateIntegrationConnection(f.store, f.shipperA.org.id, { webhookUrl: "https://erp.example.com/hook", paymentPolicy: "erp_preauthorized" });
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
  const delivery = await f.request(`/shipments/${id}/driver-pod`, "POST", {}, carrier.driver);
  assert.equal(delivery.status, 200);
  const podAccepted = await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperA);
  assert.equal(podAccepted.status, 200);
  assert.equal((await f.request(`/ops/shipments/${id}/release`, "POST", {}, f.tokens.finance)).status, 200, "delivered: ledger line and payout dates exist");
  await f.request(`/v1/shipments/${id}/conversation/messages`, "POST", { body: "Reached the gate.", clientRequestId: "synthetic-1" }, carrier.ownerDriver);
  return { f, id, orgId, carrier, responses: { booked: booked.body, accepted: accepted.body, delivery: delivery.body, podAccepted: podAccepted.body } };
}

test("a carrier login sees only the carrier's own amount, on any route it can reach", async t => {
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
    assert.deepEqual(responsesWithKeys(seen, shipperPriceKeys), {}, who);
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

test("a shipper login sees only the shipper's own amount, on any route it can reach", async t => {
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
  assert.deepEqual(responsesWithKeys(seen, carrierAmountKeysIn), {});
  const shipment = (seen[`/shipments/${id}`] as { shipment: Record<string, unknown> }).shipment;
  assert.equal(typeof shipment.grossPaise, "number", "the shipper still sees its own price");
  assert.equal(shipment.paymentReady, true, "and when its payment is taken");
});

test("a shipper's ERP sees only the shipper's own amount, from the API or the webhook", async t => {
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
  assert.deepEqual(responsesWithKeys(seen, carrierAmountKeysIn), {});
  assert.equal(typeof (seen.snapshot as { grossPaise?: number }).grossPaise, "number", "the ERP still sees the shipper's price");
});

test("an object with no branch of its own still gives each side only its own amount", async t => {
  const f = await httpFixture(t);
  const unbranched = { estimate: { weightKg: 10, grossPaise: 1000, commissionPaise: 100, amountPaise: 1000, netToCarrierPaise: 900, totalNetToCarrierPaise: 900, firstPayoutEligibleAtUtcMs: 1 } };
  const serializedFor = (userId: string) => authorizationContext.run({ principal: resolvePrincipal(f.store, userId), requestId: "synthetic" }, () => serializeResponse(unbranched));
  assert.deepEqual(serializedFor(f.carrierA.user.id), { estimate: { weightKg: 10, netToCarrierPaise: 900, totalNetToCarrierPaise: 900, firstPayoutEligibleAtUtcMs: 1 } });
  assert.deepEqual(serializedFor(f.shipperA.user.id), { estimate: { weightKg: 10, grossPaise: 1000, amountPaise: 1000 } });
  assert.deepEqual(serializedFor(f.finance.user.id), unbranched, "NaviG8r's own logins keep both");
});

test("a quote needs a signed-in shipper or ops; a carrier login or no sign-in is refused", async t => {
  const { f, carrier } = await deliveredShipment(t);
  const quote = (token?: string) => f.request("/shipments/quote", "POST", { weightKg: 10, pickup: { lat: 12.97, lng: 77.59 }, drop: { lat: 13.08, lng: 80.27 }, anchorTripId: f.trip.id }, token);
  const anonymous = await quote();
  assert.equal(anonymous.status, 401);
  assert.equal(anonymous.body.error, "unauthorized");
  for (const [who, token] of Object.entries(carrier)) {
    const refused = await quote(token);
    assert.equal(refused.status, 403, who);
    assert.equal(refused.body.error, "quote_requires_shipper", who);
  }
  for (const token of [f.tokens.shipperA, f.tokens.ops]) {
    const quoted = await quote(token);
    assert.equal(quoted.status, 200);
    assert.equal(typeof quoted.body.quote.grossPaise, "number");
  }
});

test("a carrier never gets the shipper's price breakdown or any part of it", async t => {
  const f = await httpFixture(t);
  const quoted = { quote: { grossPaise: 1000, breakdown: { pricingMode: "distance_weight", paisePerKm: 10, distanceComponentPaise: 600, weightComponentPaise: 400 } }, paisePerKm: 10, distanceComponentPaise: 600, weightComponentPaise: 400, laneKm: 5 };
  const serializedFor = (userId: string) => authorizationContext.run({ principal: resolvePrincipal(f.store, userId), requestId: "synthetic" }, () => serializeResponse(quoted));
  assert.deepEqual(serializedFor(f.carrierA.user.id), { quote: {}, laneKm: 5 });
});

test("no sign-in gets no amount and no payout date, on any object", () => {
  const unbranched = { estimate: { weightKg: 10, grossPaise: 1000, commissionPaise: 100, amountPaise: 1000, netToCarrierPaise: 900, totalNetToCarrierPaise: 900, pendingAccruedPaise: 1, paidPaise: 1, firstPayoutEligibleAtUtcMs: 1, payoutBatchCutoffUtcMs: 1, paidAtUtcMs: 1, cutoffUtcMs: 1, breakdown: { paisePerKm: 10 } } };
  const shipment = { id: "shp_synthetic", customerOrgName: "Synthetic", paymentId: "payin_synthetic", status: "DELIVERED", grossPaise: 1000, commissionPaise: 100, netToCarrierPaise: 900, firstPayoutEligibleAtUtcMs: 1, payoutBatchCutoffUtcMs: 1, podAtUtcMs: 1 };
  for (const serialize of [() => serializeResponse(unbranched), () => authorizationContext.run({ requestId: "synthetic" }, () => serializeResponse(unbranched))]) {
    assert.deepEqual(serialize(), { estimate: { weightKg: 10 } });
  }
  assert.deepEqual(serializeResponse(shipment), { id: "shp_synthetic", customerOrgName: "Synthetic", status: "DELIVERED", podAtUtcMs: 1 });
});

test("every ERP route leaves out the carrier's amount, the cut and payout fields, even ones no service strips", async t => {
  const { f, id } = await deliveredShipment(t);
  const orgId = f.shipperA.org.id;
  const { token } = createIntegrationApiKey(f.store, orgId);
  // As a new storage field would: present on a stored record, unknown to every service.
  const carrierSide = { netToCarrierPaise: 1, totalNetToCarrierPaise: 1, pendingAccruedPaise: 1, paidPaise: 1, commissionPaise: 1, firstPayoutEligibleAtUtcMs: 1, payoutBatchCutoffUtcMs: 1, paidAtUtcMs: 1 };
  f.store.anchorTrips.set(f.trip.id, { ...f.store.anchorTrips.get(f.trip.id)!, ...carrierSide });
  const seen: Record<string, unknown> = {};
  for (const path of [`/v1/integrations/shipments/${id}`, `/v1/integrations/shipments/${id}/tracking`, "/v1/integrations/loads", `/v1/integrations/events?shipmentId=${id}`]) {
    const response = await f.request(path, "GET", undefined, token);
    assert.equal(response.status, 200, path);
    seen[path] = response.body;
  }
  for (const path of [`/v1/pilot/customer/integrations?orgId=${orgId}`, `/v1/pilot/customer/integrations/deliveries?orgId=${orgId}`]) {
    const response = await f.request(path, "GET", undefined, f.tokens.shipperA);
    assert.equal(response.status, 200, path);
    seen[path] = response.body;
  }
  assert.deepEqual(responsesWithKeys(seen, carrierAmountKeysIn), {});
  assert.equal(typeof (seen[`/v1/integrations/shipments/${id}`] as { grossPaise?: number }).grossPaise, "number", "the ERP still sees the shipper's price");
});

const throughErpFilter = (body: unknown) => JSON.parse(JSON.stringify(body, leaveOutCarrierSide()));

test("the ERP filter passes a shipment's own metadata back exactly as sent, and no other metadata", () => {
  const metadata = { poNumber: "PO-1", commissionPaise: "kept", netToCarrierPaise: "kept", nested: { paidAtUtcMs: "kept" } };
  const shipment = { id: "shp_synthetic", customerOrgName: "Synthetic", paymentId: "payin_synthetic", grossPaise: 1000, netToCarrierPaise: 900, commissionPaise: 100, metadata };
  const load = { shipmentId: "shp_synthetic", trackingUrl: "https://example.com/track", grossPaise: 1000, metadata, shipment, paidAtUtcMs: 1 };
  assert.deepEqual(throughErpFilter(load), {
    shipmentId: "shp_synthetic", trackingUrl: "https://example.com/track", grossPaise: 1000, metadata,
    shipment: { id: "shp_synthetic", customerOrgName: "Synthetic", paymentId: "payin_synthetic", grossPaise: 1000, metadata },
  });
  const trip = { trip: { id: "trip_synthetic", metadata: { poNumber: "PO-1", netToCarrierPaise: 900, nested: { paidAtUtcMs: 1 } } } };
  assert.deepEqual(throughErpFilter(trip), { trip: { id: "trip_synthetic", metadata: { poNumber: "PO-1", nested: {} } } });
});

test("each ERP response gets its own filter, so an object kept as metadata in one is filtered in the next", () => {
  const shared = { poNumber: "PO-1", netToCarrierPaise: 900 };
  assert.deepEqual(throughErpFilter({ shipmentId: "shp_synthetic", trackingUrl: "https://example.com/track", metadata: shared }), { shipmentId: "shp_synthetic", trackingUrl: "https://example.com/track", metadata: shared });
  assert.deepEqual(throughErpFilter({ trip: shared }), { trip: { poNumber: "PO-1" } });
});
