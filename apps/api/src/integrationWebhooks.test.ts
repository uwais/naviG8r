import { bookTestShipment, internalUser, registerCompliantCarrier } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import dns from "node:dns";
import test, { mock } from "node:test";
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

test("deliverIntegrationWebhook attaches valid HMAC signature", async () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const secret = "whsec_test_secret";
  const payloadJson = JSON.stringify({ eventId: "evt_1", eventType: "load.created" });
  let capturedSig: string | undefined;
  let capturedBody: string | undefined;

  const lookupMock = mockWebhookAddressLookup();
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
    lookupMock.mock.restore();
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
  const lookupMock = mockWebhookAddressLookup();
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
    lookupMock.mock.restore();
  }
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

const WEBHOOK_TEST_ADDRESSES: Record<string, string[]> = {
  "erp.example.com": ["93.184.215.14"],
  "internal.example.com": ["10.1.2.3"],
  "mixed.example.com": ["93.184.215.14", "127.0.0.1"],
};

function mockWebhookAddressLookup() {
  return mock.method(dns.promises, "lookup", async (host: string) =>
    (WEBHOOK_TEST_ADDRESSES[host] ?? []).map((address) => ({ address, family: address.includes(":") ? 6 : 4 })));
}

function webhookDeliveryTo(webhookUrl: string): IntegrationWebhookDelivery {
  return {
    id: "whd_address",
    eventId: "evt_address",
    orgId: "org_address",
    connectionId: "conn_address",
    webhookUrl,
    payloadJson: "{}",
    status: "PENDING",
    attempts: 0,
    nextRetryAtUtcMs: Date.now(),
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: Date.now(),
    updatedAtUtcMs: Date.now(),
  };
}

test("a webhook is sent only to a public address", async () => {
  const lookupMock = mockWebhookAddressLookup();
  const sentTo: string[] = [];
  const fetchMock = mock.method(globalThis, "fetch", async (url: string) => {
    sentTo.push(String(url));
    return new Response("ok", { status: 200 });
  });
  try {
    for (const url of [
      "http://127.0.0.1:3000/hook",
      "http://0.0.0.0/hook",
      "http://[::1]/hook",
      "http://[::ffff:127.0.0.1]/hook",
      "http://10.0.0.5/hook",
      "http://172.16.0.1/hook",
      "http://192.168.1.1/hook",
      "http://100.100.100.200/hook",
      "http://169.254.169.254/latest/meta-data",
      "http://[fe80::1]/hook",
      "http://[fd00:ec2::254]/hook",
      "https://internal.example.com/hook",
      "https://mixed.example.com/hook",
    ]) {
      const result = await deliverIntegrationWebhook(webhookDeliveryTo(url), undefined);
      assert.deepEqual(result, { ok: false, httpStatus: 0, error: "webhook_address_not_allowed" }, url);
    }
    assert.deepEqual(sentTo, []);

    const result = await deliverIntegrationWebhook(webhookDeliveryTo("https://erp.example.com/hook"), undefined);
    assert.equal(result.ok, true);
    assert.deepEqual(sentTo, ["https://erp.example.com/hook"]);
  } finally {
    fetchMock.mock.restore();
    lookupMock.mock.restore();
  }
});

test("a webhook redirect is not followed and counts as a failed delivery", async () => {
  const lookupMock = mockWebhookAddressLookup();
  let redirectOption: RequestRedirect | undefined;
  const fetchMock = mock.method(globalThis, "fetch", async (_url: string, init?: RequestInit) => {
    redirectOption = init?.redirect;
    if (init?.redirect === "manual") {
      return new Response(null, { status: 302, headers: { location: "https://erp.example.com/elsewhere" } });
    }
    return new Response("ok", { status: 200 });
  });
  try {
    const result = await deliverIntegrationWebhook(webhookDeliveryTo("https://erp.example.com/hook"), undefined);
    assert.equal(redirectOption, "manual");
    assert.equal(result.ok, false);
    assert.equal(result.httpStatus, 302);
  } finally {
    fetchMock.mock.restore();
    lookupMock.mock.restore();
  }
});

test("only the first 4 KB of a failed webhook reply is read", async () => {
  const lookupMock = mockWebhookAddressLookup();
  const chunk = new TextEncoder().encode("x".repeat(64 * 1024));
  let bytesPulled = 0;
  const fetchMock = mock.method(globalThis, "fetch", async () => {
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (bytesPulled >= 50 * 1024 * 1024) return controller.close();
        bytesPulled += chunk.length;
        controller.enqueue(chunk);
      },
    });
    return new Response(body, { status: 500 });
  });
  try {
    const result = await deliverIntegrationWebhook(webhookDeliveryTo("https://erp.example.com/hook"), undefined);
    assert.equal(result.ok, false);
    assert.equal(result.httpStatus, 500);
    assert.equal(result.error, "x".repeat(500));
    assert.ok(bytesPulled <= 2 * chunk.length, `read ${bytesPulled} bytes`);
  } finally {
    fetchMock.mock.restore();
    lookupMock.mock.restore();
  }
});
