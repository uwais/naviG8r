import assert from "node:assert/strict";
import test, { mock } from "node:test";
import { createStore } from "./store.ts";
import {
  acceptCarrierShipment,
  bookShipment,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
} from "./services.ts";
import { updateIntegrationConnection } from "./integrationServices.ts";
import {
  deliverIntegrationWebhook,
  processPendingWebhookDeliveries,
  emitIntegrationEvent,
} from "./integrationWebhooks.ts";
import { signWebhookPayload, verifyWebhookSignature } from "./integrationAuth.ts";
import type { IntegrationWebhookDelivery } from "./types.ts";

const GURGAON = { lat: 28.4595, lng: 77.0266, label: "Gurugram" };
const JAIPUR = { lat: 26.9124, lng: 75.7873, label: "Jaipur" };

function seedShipmentWithWebhook(store: ReturnType<typeof createStore>) {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const driver = registerSoloOwnerOperatorDriver(store, {
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
    webhookSecret: "whsec_test_secret",
    paymentPolicy: "erp_preauthorized",
  });
  const shipment = bookShipment(store, {
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

test("deliverIntegrationWebhook attaches valid HMAC signature", async () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const secret = "whsec_test_secret";
  const payloadJson = JSON.stringify({ eventId: "evt_1", eventType: "load.created" });
  let capturedSig: string | undefined;
  let capturedBody: string | undefined;

  const fetchMock = mock.method(globalThis, "fetch", async (_url: string, init?: RequestInit) => {
    const headers = init?.headers as Record<string, string>;
    capturedSig = headers["x-navig8r-signature"];
    capturedBody = String(init?.body ?? "");
    return new Response("ok", { status: 200 });
  });

  try {
    const delivery: IntegrationWebhookDelivery = {
      id: "whd_1",
      eventId: "evt_1",
      orgId: "org_1",
      connectionId: "conn_1",
      webhookUrl: "https://erp.example.com/hook",
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
  } finally {
    fetchMock.mock.restore();
  }
});

test("processPendingWebhookDeliveries retries failed delivery with backoff", async () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const store = createStore();
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Retry Admin",
    phone: "9111007711",
    orgDisplayName: "Retry Shipper",
  });
  const conn = updateIntegrationConnection(store, admin.org.id, {
    webhookUrl: "https://erp.example.com/hook",
    paymentPolicy: "erp_preauthorized",
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
  const fetchMock = mock.method(globalThis, "fetch", async () => {
    calls += 1;
    if (calls === 1) return new Response("fail", { status: 500 });
    return new Response("ok", { status: 200 });
  });

  try {
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
  } finally {
    fetchMock.mock.restore();
  }
});
