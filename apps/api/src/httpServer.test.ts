import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { createApp } from "./httpServer.ts";
import { bookShipment, createCarrier, publishAnchorTrip, registerCustomerOrgAdmin } from "./services.ts";

type AppBundle = Awaited<ReturnType<typeof createApp>>;

async function withApp<T>(
  t: { after(fn: () => void): void },
  fn: (baseUrl: string, app: AppBundle) => Promise<T>,
): Promise<T> {
  const app = await createApp();
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  t.after(() => app.server.close());

  const address = app.server.address();
  assert.ok(address && typeof address === "object");
  return fn(`http://127.0.0.1:${address.port}`, app);
}

async function postJson(baseUrl: string, path: string, body: unknown): Promise<Response> {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function postJsonWithToken(baseUrl: string, path: string, token: string, body: unknown): Promise<Response> {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

async function loginWithOtp(baseUrl: string, phone: string): Promise<string> {
  const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone });
  assert.equal(start.status, 200);
  const started = (await start.json()) as { challengeId: string; debugCode?: string };
  const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
    phone,
    challengeId: started.challengeId,
    code: started.debugCode ?? "123456",
  });
  assert.equal(verify.status, 200);
  const verified = (await verify.json()) as { accessToken?: string };
  assert.ok(verified.accessToken);
  return verified.accessToken;
}

function restoreEnv(prev: Record<string, string | undefined>): void {
  for (const [key, value] of Object.entries(prev)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
}

/**
 * In production, legacy demo/admin routes return 403.
 * Public marketplace routes (anchor-trips, quote, book, customer shipments with Bearer) stay enabled;
 * unauthenticated shipment reads/mutations return 401 (not 403).
 */
test("production disables legacy demo routes that expose or mutate operator state", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;

  await withApp(t, async (baseUrl) => {
    const users = await fetch(`${baseUrl}/v1/users`);
    assert.equal(users.status, 403);
    assert.deepEqual(await users.json(), { error: "legacy_demo_surface_disabled" });

    const carriers = await fetch(`${baseUrl}/carriers`);
    assert.equal(carriers.status, 403);

    const detail = await fetch(`${baseUrl}/shipments/shp_123`);
    assert.equal(detail.status, 401);
    assert.deepEqual(await detail.json(), { error: "unauthorized" });

    const shipments = await fetch(`${baseUrl}/shipments`);
    assert.equal(shipments.status, 401);
    assert.deepEqual(await shipments.json(), { error: "unauthorized" });

    const pod = await postJson(baseUrl, "/shipments/shp_123/pod", {});
    assert.equal(pod.status, 401);
    assert.deepEqual(await pod.json(), { error: "unauthorized" });

    const refund = await postJson(baseUrl, "/shipments/shp_123/fail-refund", {});
    assert.equal(refund.status, 401);
    assert.deepEqual(await refund.json(), { error: "unauthorized" });

    const login = await postJson(baseUrl, "/v1/pilot/driver/login", { phone: "9876543210" });
    assert.equal(login.status, 403);
    assert.deepEqual(await login.json(), { error: "legacy_demo_surface_disabled" });
  });
});

test("legacy demo surface remains available outside production", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "test";
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;

  await withApp(t, async (baseUrl) => {
    const res = await postJson(baseUrl, "/carriers", { name: "Carrier One" });
    assert.equal(res.status, 201);
    const body = (await res.json()) as { carrier?: { name?: string } };
    assert.equal(body.carrier?.name, "Carrier One");
  });
});

test("production shipment POD and fail-refund require ops admin bearer", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    OPS_ADMIN_PHONES: process.env.OPS_ADMIN_PHONES,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
    PAYMENT_PROVIDER: process.env.PAYMENT_PROVIDER,
    PERSISTENCE: process.env.PERSISTENCE,
  };
  t.after(() => restoreEnv(prev));

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;
  process.env.NODE_ENV = "production";
  process.env.OPS_ADMIN_PHONES = "9000000001";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  delete process.env.PAYMENT_PROVIDER;
  delete process.env.PERSISTENCE;

  await withApp(t, async (baseUrl, app) => {
    const carrier = createCarrier(app.store, "Carrier One");
    const trip = publishAnchorTrip(app.store, {
      carrierId: carrier.id,
      originCity: "Gurugram",
      destCity: "Jaipur",
      windowStart: "2026-04-24T00:00:00+05:30",
      windowEnd: "2026-04-25T23:59:59+05:30",
      vehicleClass: "MEDIUM",
      capacityKg: 1000,
    });
    const customer = registerCustomerOrgAdmin(app.store, {
      fullName: "Customer User",
      phone: "9000000002",
      orgDisplayName: "Customer Org",
    });
    registerCustomerOrgAdmin(app.store, {
      fullName: "Ops User",
      phone: "9000000001",
      orgDisplayName: "Ops Bootstrap Org",
    });
    const shipmentForPod = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "ignored",
      customerOrg: { id: customer.org.id, displayName: customer.org.displayName },
      weightKg: 100,
      pickupAddress: "Pickup",
      dropAddress: "Drop",
    });
    const shipmentForRefund = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "ignored",
      customerOrg: { id: customer.org.id, displayName: customer.org.displayName },
      weightKg: 100,
      pickupAddress: "Pickup",
      dropAddress: "Drop",
    });

    const customerToken = await loginWithOtp(baseUrl, customer.user.phone);
    const deniedPod = await postJsonWithToken(baseUrl, `/shipments/${shipmentForPod.id}/pod`, customerToken, {});
    assert.equal(deniedPod.status, 403);
    assert.deepEqual(await deniedPod.json(), { error: "forbidden" });
    assert.equal(app.store.shipments.get(shipmentForPod.id)?.status, "BOOKED");
    assert.equal(app.store.ledgerLines.size, 0);

    const deniedRefund = await postJsonWithToken(
      baseUrl,
      `/shipments/${shipmentForRefund.id}/fail-refund`,
      customerToken,
      {},
    );
    assert.equal(deniedRefund.status, 403);
    assert.deepEqual(await deniedRefund.json(), { error: "forbidden" });
    assert.equal(app.store.shipments.get(shipmentForRefund.id)?.status, "BOOKED");

    const opsToken = await loginWithOtp(baseUrl, "9000000001");
    const allowedPod = await postJsonWithToken(baseUrl, `/shipments/${shipmentForPod.id}/pod`, opsToken, {});
    assert.equal(allowedPod.status, 200);
    assert.equal(app.store.shipments.get(shipmentForPod.id)?.status, "DELIVERED");
    assert.equal(app.store.ledgerLines.size, 1);

    const allowedRefund = await postJsonWithToken(
      baseUrl,
      `/shipments/${shipmentForRefund.id}/fail-refund`,
      opsToken,
      {},
    );
    assert.equal(allowedRefund.status, 200);
    assert.equal(app.store.shipments.get(shipmentForRefund.id)?.status, "FAILED_CARRIER_REFUNDED");
  });
});
