import { bookTestShipment, internalUser, registerCompliantCarrier } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import http from "node:http";
import https from "node:https";
import type { AddressInfo } from "node:net";
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
import { webhookAddressLookup, WEBHOOK_ADDRESS_REFUSED_SENTENCE } from "./integrationWebhookAddress.ts";
import { signWebhookPayload, verifyWebhookSignature } from "./integrationAuth.ts";
import type { IntegrationWebhookDelivery } from "./types.ts";

// No test here makes a DNS query: a name a test does not answer for itself does not resolve.
webhookAddressLookup.addresses = async (hostname) => { throw Object.assign(new Error(`getaddrinfo ENOTFOUND ${hostname}`), { code: "ENOTFOUND" }); };

/** Counts requests the webhook code starts, and starts none. */
function noRequestsMade(t: { after(fn: () => void): void }): () => number {
  const plain = mock.method(http, "request", () => { throw new Error("no request expected"); });
  const secure = mock.method(https, "request", () => { throw new Error("no request expected"); });
  t.after(() => { plain.mock.restore(); secure.mock.restore(); });
  return () => plain.mock.callCount() + secure.mock.callCount();
}

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
    changedByUserId: internalUser(store, "OPS").userId,
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

test("deliverIntegrationWebhook attaches valid HMAC signature", async t => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  withNodeEnv(t, "test");
  const secret = "whsec_test_secret";
  const payloadJson = JSON.stringify({ eventId: "evt_1", eventType: "load.created" });
  let capturedSig: string | undefined;
  let capturedBody: string | undefined;
  const local = await listen(t, (req, res) => {
    capturedSig = String(req.headers["x-navig8r-signature"]);
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => { capturedBody = body; res.end("ok"); });
  });

  const result = await deliverIntegrationWebhook({ ...deliveryTo(`${local}/hook`), payloadJson }, secret);
  assert.equal(result.ok, true);
  assert.equal(capturedBody, payloadJson);
  assert.equal(capturedSig, signWebhookPayload(secret, payloadJson));
  assert.equal(verifyWebhookSignature(secret, payloadJson, capturedSig), true);
});

test("processPendingWebhookDeliveries retries failed delivery with backoff", async t => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  withNodeEnv(t, "test");
  let calls = 0;
  const local = await listen(t, (_req, res) => {
    calls += 1;
    res.writeHead(calls === 1 ? 500 : 200);
    res.end(calls === 1 ? "fail" : "ok");
  });
  const store = createStore();
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Retry Admin",
    phone: "9111007711",
    orgDisplayName: "Retry Shipper",
  });
  const conn = updateIntegrationConnection(store, admin.org.id, {
    webhookUrl: `${local}/hook`,
    paymentPolicy: "erp_preauthorized",
    changedByUserId: internalUser(store, "OPS").userId,
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

test("with OUTBOUND_WEBHOOKS_OFF=1 a queued delivery fails with a sentence and nothing is sent", async t => {
  const store = createStore();
  seedShipmentWithWebhook(store);
  const requestsMade = noRequestsMade(t);
  process.env.OUTBOUND_WEBHOOKS_OFF = "1";
  try {
    assert.ok(await processPendingWebhookDeliveries(store) > 0);
    assert.equal(requestsMade(), 0);
    for (const delivery of store.integrationWebhookDeliveries.values()) {
      assert.equal(delivery.status, "PENDING");
      assert.equal(delivery.lastError, "The practice server does not send webhooks.");
    }
  } finally {
    delete process.env.OUTBOUND_WEBHOOKS_OFF;
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

function deliveryTo(webhookUrl: string): IntegrationWebhookDelivery {
  const now = Date.now();
  return {
    id: "whd_address",
    eventId: "evt_address",
    orgId: "org_address",
    connectionId: "conn_address",
    webhookUrl,
    payloadJson: "{}",
    status: "PENDING",
    attempts: 0,
    nextRetryAtUtcMs: now,
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };
}

/** Tests and the local practice server run with NODE_ENV=test, the one setting that lets a webhook reach this machine. */
function withNodeEnv(t: { after(fn: () => void): void }, value: string | undefined): void {
  const previous = process.env.NODE_ENV;
  if (value === undefined) delete process.env.NODE_ENV;
  else process.env.NODE_ENV = value;
  t.after(() => {
    if (previous === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previous;
  });
}

async function listen(t: { after(fn: () => void): void }, handler: http.RequestListener): Promise<string> {
  const server = http.createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

test("a webhook address that is a private, loopback, link-local or metadata address is not called", async t => {
  withNodeEnv(t, undefined);
  const requestsMade = noRequestsMade(t);
  const answeredBefore = webhookAddressLookup.addresses;
  webhookAddressLookup.addresses = async (hostname) => hostname === "localhost" ? ["127.0.0.1", "::1"] : answeredBefore(hostname);
  t.after(() => { webhookAddressLookup.addresses = answeredBefore; });
  for (const webhookUrl of ["http://127.0.0.1:9/hook", "http://localhost/hook", "http://10.1.2.3/hook", "http://172.16.0.1/hook", "http://192.168.1.1/hook", "http://169.254.169.254/latest/meta-data", "http://100.64.0.1/hook", "http://0.0.0.0/hook", "http://[::1]/hook", "http://[fe80::1]/hook", "http://[fd00:ec2::254]/hook", "http://[::ffff:127.0.0.1]/hook", "http://2130706433/hook"]) {
    const result = await deliverIntegrationWebhook(deliveryTo(webhookUrl), undefined);
    assert.deepEqual([result.ok, result.httpStatus, result.error], [false, 0, WEBHOOK_ADDRESS_REFUSED_SENTENCE], webhookUrl);
  }
  assert.equal(requestsMade(), 0);
});

test("a webhook name that does not resolve fails with the same sentence as a private one, and nothing is sent", async t => {
  withNodeEnv(t, undefined);
  const requestsMade = noRequestsMade(t);
  const result = await deliverIntegrationWebhook(deliveryTo("https://missing.example.com/hook"), undefined);
  assert.deepEqual([result.ok, result.httpStatus, result.error], [false, 0, WEBHOOK_ADDRESS_REFUSED_SENTENCE]);
  assert.equal(requestsMade(), 0);
});

test("a webhook is sent to the address its check resolved, with no second DNS lookup", async t => {
  withNodeEnv(t, "test");
  let hostHeader: string | undefined;
  const local = await listen(t, (req, res) => { hostHeader = req.headers.host; res.end("ok"); });
  const port = new URL(local).port;
  const answeredBefore = webhookAddressLookup.addresses;
  let lookups = 0;
  // A .invalid name never resolves in DNS, so the call can only arrive through the checked answer.
  webhookAddressLookup.addresses = async (hostname) => { lookups += 1; return hostname === "webhook.invalid" ? ["127.0.0.1"] : answeredBefore(hostname); };
  t.after(() => { webhookAddressLookup.addresses = answeredBefore; });
  const result = await deliverIntegrationWebhook(deliveryTo(`http://webhook.invalid:${port}/hook`), undefined);
  assert.deepEqual([result.ok, result.httpStatus], [true, 200]);
  assert.equal(lookups, 1);
  assert.equal(hostHeader, `webhook.invalid:${port}`, "the request still names the webhook's host");
});

test("a webhook that answers with a redirect is a failed delivery, and the redirect is not followed", async t => {
  withNodeEnv(t, "test");
  let targetCalls = 0;
  const target = await listen(t, (_req, res) => { targetCalls += 1; res.end("ok"); });
  const redirecting = await listen(t, (_req, res) => { res.writeHead(307, { location: `${target}/hook` }); res.end(); });
  const result = await deliverIntegrationWebhook(deliveryTo(`${redirecting}/hook`), undefined);
  assert.deepEqual([result.ok, result.httpStatus], [false, 307]);
  assert.equal(targetCalls, 0);
});

test("a failed webhook's error text is taken from the start of its answer; the rest is not read", async t => {
  withNodeEnv(t, "test");
  const endless = await listen(t, (_req, res) => {
    res.writeHead(500);
    const chunk = Buffer.alloc(64 * 1024, "e");
    const timer = setInterval(() => res.write(chunk), 5);
    res.on("close", () => clearInterval(timer));
  });
  const result = await Promise.race([
    deliverIntegrationWebhook(deliveryTo(`${endless}/hook`), undefined),
    new Promise<string>((resolve) => setTimeout(() => resolve("still reading after 3 seconds"), 3000)),
  ]);
  assert.notEqual(result, "still reading after 3 seconds");
  assert.deepEqual(result, { ok: false, httpStatus: 500, error: "e".repeat(500) });
});

test("a webhook host is called only when every address it resolves to is on the public internet", async t => {
  withNodeEnv(t, undefined);
  const answeredBefore = webhookAddressLookup.addresses;
  t.after(() => { webhookAddressLookup.addresses = answeredBefore; });
  const answers: Record<string, string[]> = {
    "metadata.example.com": ["169.254.169.254"],
    "mixed.example.com": ["93.184.216.34", "10.0.0.7"],
    "private-v6.example.com": ["fd00::7"],
    "public.example.com": ["93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"],
  };
  webhookAddressLookup.addresses = async (hostname) => answers[hostname] ?? [];
  const refusedRequests = noRequestsMade(t);
  for (const hostname of ["metadata.example.com", "mixed.example.com", "private-v6.example.com"]) {
    const result = await deliverIntegrationWebhook(deliveryTo(`https://${hostname}/hook`), undefined);
    assert.deepEqual([result.ok, result.error], [false, WEBHOOK_ADDRESS_REFUSED_SENTENCE], hostname);
  }
  assert.equal(refusedRequests(), 0);
  mock.restoreAll();

  // Nothing leaves this machine: the request is caught as it starts, and what it would connect to is read.
  const started: Array<{ url: URL; options: http.RequestOptions }> = [];
  const secure = mock.method(https, "request", (url: URL, options: http.RequestOptions) => { started.push({ url, options }); throw new Error("stopped before connecting"); });
  t.after(() => secure.mock.restore());
  const result = await deliverIntegrationWebhook(deliveryTo("https://public.example.com/hook"), undefined);
  assert.equal(result.ok, false);
  assert.equal(started.length, 1);
  assert.equal(started[0]!.url.hostname, "public.example.com", "TLS checks the certificate against the webhook's host name");
  assert.equal(started[0]!.options.servername, undefined, "no other name is given for TLS");
  const connectsTo = await new Promise((resolve) => started[0]!.options.lookup!("public.example.com", { all: true }, (_error, addresses) => resolve(addresses)));
  assert.deepEqual(connectsTo, [{ address: "93.184.216.34", family: 4 }, { address: "2606:2800:220:1:248:1893:25c8:1946", family: 6 }]);
});
