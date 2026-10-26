import { bookTestShipment, internalUser, registerCompliantCarrier } from "../test/fixtures.ts";
import { mockWebhookAddressLookup, webhookReceiver } from "../test/webhookReceiver.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  acceptCarrierShipment,

  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,

} from "./services.ts";
import { updateIntegrationConnection } from "./integrationServices.ts";
import {
  claimPendingWebhookDeliveries,
  deliverIntegrationWebhook,
  processPendingWebhookDeliveries,
  emitIntegrationEvent,
  retryWebhookDelivery,
} from "./integrationWebhooks.ts";
import { signWebhookPayload, verifyWebhookSignature } from "./integrationAuth.ts";
import type { IntegrationWebhookDelivery } from "./types.ts";

const GURGAON = { lat: 28.4595, lng: 77.0266, label: "Gurugram" };
const JAIPUR = { lat: 26.9124, lng: 75.7873, label: "Jaipur" };

function seedShipmentWithWebhook(store: ReturnType<typeof createStore>) {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const driver = registerCompliantCarrier(store, {
    fullName: "Webhook Driver",
    phone: "9876547700",
    orgDisplayName: "Webhook Carrier",
    vehicleRegistrationNumber: "HR26WH0001",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: driver.user.id,
    orgId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    origin: GURGAON,
    destination: JAIPUR,
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Webhook Admin",
    phone: "9111007700",
    orgDisplayName: "Webhook Shipper",
  });
  const conn = updateIntegrationConnection(store, admin.org.id, {
    webhookUrl: "https://erp.example.com/hook",
    paymentPolicy: "erp_preauthorized",
    changedByUserId: internalUser(store, "ADMIN").userId,
  });
  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: admin.org.displayName,
    customerOrg: { id: admin.org.id, displayName: admin.org.displayName },
    weightKg: 40,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
    pickup: GURGAON,
    drop: JAIPUR,
    externalLoadId: "ERP-WH-001",
    integrationConnectionId: conn.id,
  });
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, status: "AUTHORIZED" });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });
  emitIntegrationEvent(store, { eventType: "load.carrier_accepted", shipmentId: shipment.id });
  return { admin, conn, shipment };
}

test("deliverIntegrationWebhook attaches valid HMAC signature", async (t) => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const secret = "whsec_test_secret";
  const payloadJson = JSON.stringify({ eventId: "evt_1", eventType: "load.created" });
  let capturedSig: string | undefined;
  let capturedBody: string | undefined;

  mockWebhookAddressLookup(t);
  await webhookReceiver(t, (req, res) => {
    capturedSig = String(req.headers["x-navig8r-signature"]);
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => {
      capturedBody = Buffer.concat(chunks).toString("utf8");
      res.end("ok");
    });
  });

  const delivery: IntegrationWebhookDelivery = {
    id: "whd_1",
    eventId: "evt_1",
    orgId: "org_1",
    connectionId: "conn_1",
    webhookUrl: "http://erp.example.com/hook",
    payloadJson,
    status: "PENDING",
    attempts: 0,
    nextRetryAtUtcMs: Date.now(),
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: Date.now(),
    updatedAtUtcMs: Date.now(),
  };

  const result = await deliverIntegrationWebhook(delivery, secret);
  assert.equal(result.ok, true);
  assert.equal(capturedBody, payloadJson);
  assert.equal(capturedSig, signWebhookPayload(secret, payloadJson));
  assert.equal(verifyWebhookSignature(secret, payloadJson, capturedSig), true);
});

test("processPendingWebhookDeliveries retries failed delivery with backoff", async (t) => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const store = createStore();
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Retry Admin",
    phone: "9111007711",
    orgDisplayName: "Retry Shipper",
  });
  const conn = updateIntegrationConnection(store, admin.org.id, {
    webhookUrl: "http://erp.example.com/hook",
    paymentPolicy: "erp_preauthorized",
    changedByUserId: internalUser(store, "ADMIN").userId,
  });
  conn.webhookSecret = "whsec_retry";
  store.integrationConnections.set(conn.id, conn);

  const now = Date.now();
  const delivery: IntegrationWebhookDelivery = {
    id: "whd_retry_test",
    eventId: "evt_retry",
    orgId: admin.org.id,
    connectionId: conn.id,
    webhookUrl: conn.webhookUrl!,
    payloadJson: JSON.stringify({ eventId: "evt_retry", eventType: "load.created" }),
    status: "PENDING",
    attempts: 0,
    nextRetryAtUtcMs: now - 1,
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };
  store.integrationWebhookDeliveries.set(delivery.id, delivery);

  let calls = 0;
  mockWebhookAddressLookup(t);
  await webhookReceiver(t, (_req, res) => {
    calls += 1;
    res.statusCode = calls === 1 ? 500 : 200;
    res.end(calls === 1 ? "fail" : "ok");
  });

  await processPendingWebhookDeliveries(store);
  const afterFirst = store.integrationWebhookDeliveries.get(delivery.id)!;
  assert.equal(afterFirst.status, "PENDING");
  assert.equal(afterFirst.attempts, 1);
  assert.ok(afterFirst.nextRetryAtUtcMs > Date.now());

  afterFirst.nextRetryAtUtcMs = Date.now() - 1;
  store.integrationWebhookDeliveries.set(delivery.id, afterFirst);
  await processPendingWebhookDeliveries(store);
  const afterSecond = store.integrationWebhookDeliveries.get(delivery.id)!;
  assert.equal(afterSecond.status, "DELIVERED");
  assert.equal(calls, 2);
});

test("an explicit webhook retry starts a fresh bounded attempt budget", () => {
  const store = createStore();
  const delivery = {
    id: "whd_manual_retry",
    eventId: "evt_manual_retry",
    orgId: "org_manual_retry",
    connectionId: "conn_manual_retry",
    webhookUrl: "https://erp.example.com/hook",
    payloadJson: "{}",
    status: "DEAD" as const,
    attempts: 10,
    nextRetryAtUtcMs: Date.now(),
    lastHttpStatus: 500,
    lastError: "delivery_failed",
    deliveredAtUtcMs: null,
    createdAtUtcMs: Date.now(),
    updatedAtUtcMs: Date.now(),
  } satisfies IntegrationWebhookDelivery;
  store.integrationWebhookDeliveries.set(delivery.id, delivery);

  const retried = retryWebhookDelivery(store, delivery.id);
  assert.equal(retried.status, "PENDING");
  assert.equal(retried.attempts, 0);
  assert.equal(claimPendingWebhookDeliveries(store, { nowUtcMs: Date.now() }).claims.length, 1);
});

test("expired exhausted webhook lease becomes terminal and is persisted as changed", () => {
  const store = createStore();
  const now = Date.now();
  const delivery = {
    id: "whd_exhausted_lease",
    eventId: "evt_exhausted_lease",
    orgId: "org_exhausted_lease",
    connectionId: "conn_exhausted_lease",
    webhookUrl: "https://erp.example.com/hook",
    payloadJson: "{}",
    status: "PENDING" as const,
    attempts: 10,
    nextRetryAtUtcMs: now - 1,
    leaseId: "crashed-worker",
    leaseUntilUtcMs: now - 1,
    lastHttpStatus: 500,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  } satisfies IntegrationWebhookDelivery;
  store.integrationWebhookDeliveries.set(delivery.id, delivery);

  const result = claimPendingWebhookDeliveries(store, { nowUtcMs: now });
  const recovered = store.integrationWebhookDeliveries.get(delivery.id)!;
  assert.equal(result.claims.length, 0);
  assert.equal(result.changed, true);
  assert.equal(recovered.status, "DEAD");
  assert.equal(recovered.leaseId, null);
  assert.equal(recovered.leaseUntilUtcMs, null);
  assert.equal(recovered.lastError, "delivery_attempts_exhausted");

  const again = claimPendingWebhookDeliveries(store, { nowUtcMs: now + 1 });
  assert.equal(again.claims.length, 0);
  assert.equal(again.changed, false);
});

