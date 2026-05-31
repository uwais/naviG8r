import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import {
  bookShipment,
  grantOpsAdmin,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
} from "./services.ts";

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

function issueTestToken(app: AppBundle, phone: string): string {
  const start = pilotOtpStart(app.store, { phone });
  return pilotOtpVerify(app.store, {
    phone,
    challengeId: start.challengeId,
    code: "123456",
  }).accessToken;
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

    const ledger = await fetch(`${baseUrl}/carriers/carrier_123/ledger`);
    assert.equal(ledger.status, 401);
    assert.deepEqual(await ledger.json(), { error: "unauthorized" });

    const runBatch = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: 9999999999999 });
    assert.equal(runBatch.status, 401);
    assert.deepEqual(await runBatch.json(), { error: "unauthorized" });

    const batches = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(batches.status, 401);
    assert.deepEqual(await batches.json(), { error: "unauthorized" });
  });
});

test("production ignores x-user-id impersonation for pilot routes", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    AUTH_SECRET: process.env.AUTH_SECRET,
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.ALLOW_X_USER_ID = "1";

  await withApp(t, async (baseUrl, app) => {
    const onboard = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Ravi Kumar",
      phone: "9876543210",
      orgDisplayName: "Ravi Transport",
      vehicleRegistrationNumber: "HR26AB1234",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });

    const res = await fetch(`${baseUrl}/v1/pilot/me`, {
      headers: { "x-user-id": onboard.user.id },
    });
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "unauthorized" });
  });
});

test("production ignores client-supplied POD and payout batch clocks", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const driver = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Ravi Kumar",
      phone: "9876543211",
      orgDisplayName: "Ravi Transport",
      vehicleRegistrationNumber: "HR26AB1234",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    const trip = publishAnchorTripAsPilotDriver(app.store, {
      userId: driver.user.id,
      orgId: driver.org.id,
      originCity: "Gurugram",
      destCity: "Jaipur",
      windowStart: "2026-04-24T00:00:00+05:30",
      windowEnd: "2026-04-25T23:59:59+05:30",
      vehicleClass: "MEDIUM",
      capacityKg: 1000,
    });
    const shipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "ACME",
      weightKg: 100,
      pickupAddress: "Gurugram",
      dropAddress: "Jaipur",
    });

    const driverToken = issueTestToken(app, driver.user.phone);
    const forgedPodAtUtcMs = 0;
    const podStartedAt = Date.now();
    const pod = await fetch(`${baseUrl}/shipments/${shipment.id}/pod`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${driverToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ podAtUtcMs: forgedPodAtUtcMs }),
    });
    assert.equal(pod.status, 200);
    const podBody = (await pod.json()) as { ledgerLine: { id: string; podAtUtcMs: number } };
    assert.notEqual(podBody.ledgerLine.podAtUtcMs, forgedPodAtUtcMs);
    assert.ok(podBody.ledgerLine.podAtUtcMs >= podStartedAt);

    const admin = registerCustomerOrgAdmin(app.store, {
      fullName: "Ops Admin",
      phone: "9876543212",
      orgDisplayName: "naviG8r Ops Customer",
    });
    grantOpsAdmin(app.store, { phone: admin.user.phone });
    const adminToken = issueTestToken(app, admin.user.phone);

    const runBatch = await fetch(`${baseUrl}/payout-batches/run`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${adminToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ nowUtcMs: 9999999999999 }),
    });
    assert.equal(runBatch.status, 200);
    const runBody = (await runBatch.json()) as { batch: { totalNetToCarrierPaise: number } };
    assert.equal(runBody.batch.totalNetToCarrierPaise, 0);
    assert.equal(app.store.ledgerLines.get(podBody.ledgerLine.id)?.status, "ACCRUED");
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
