import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { createApp } from "./httpServer.ts";

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

async function postJsonWithHeaders(
  baseUrl: string,
  path: string,
  body: unknown,
  headers: Record<string, string>,
): Promise<Response> {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
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

    const ledger = await fetch(`${baseUrl}/carriers/car_123/ledger`);
    assert.equal(ledger.status, 401);
    assert.deepEqual(await ledger.json(), { error: "unauthorized" });

    const payoutRun = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: 9_999_999_999_999 });
    assert.equal(payoutRun.status, 401);
    assert.deepEqual(await payoutRun.json(), { error: "unauthorized" });

    const payoutBatches = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(payoutBatches.status, 401);
    assert.deepEqual(await payoutBatches.json(), { error: "unauthorized" });
  });
});

test("production payout run ignores client supplied cutoff even for ops admin", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    OPS_ADMIN_PHONES: process.env.OPS_ADMIN_PHONES,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OPS_ADMIN_PHONES = prev.OPS_ADMIN_PHONES;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = "test-secret-at-least-16-bytes";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;
  process.env.OPS_ADMIN_PHONES = "9876543210";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const register = await postJson(baseUrl, "/v1/pilot/driver/register", {
      fullName: "Ops Admin",
      phone: "9876543210",
      orgDisplayName: "Ops Transport",
      vehicleRegistrationNumber: "HR26AB1234",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    assert.equal(register.status, 201);

    const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone: "9876543210" });
    assert.equal(start.status, 200);
    const startBody = (await start.json()) as { challengeId: string };
    const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
      phone: "9876543210",
      challengeId: startBody.challengeId,
      code: "123456",
    });
    assert.equal(verify.status, 200);
    const verifyBody = (await verify.json()) as { accessToken: string; isOpsAdmin: boolean };
    assert.equal(verifyBody.isOpsAdmin, true);

    const now = Date.now();
    app.store.ledgerLines.set("led_due", {
      id: "led_due",
      shipmentId: "shp_due",
      carrierId: "car_123",
      grossPaise: 1000,
      commissionPaise: 100,
      netToCarrierPaise: 900,
      podAtUtcMs: now - 10_000,
      firstPayoutEligibleAtUtcMs: now - 5_000,
      payoutBatchCutoffUtcMs: now - 1_000,
      status: "ACCRUED",
      createdAtUtcMs: now - 10_000,
      paidAtUtcMs: null,
    });
    app.store.ledgerLines.set("led_future", {
      id: "led_future",
      shipmentId: "shp_future",
      carrierId: "car_123",
      grossPaise: 2000,
      commissionPaise: 200,
      netToCarrierPaise: 1800,
      podAtUtcMs: now,
      firstPayoutEligibleAtUtcMs: now + 60_000,
      payoutBatchCutoffUtcMs: now + 60_000,
      status: "ACCRUED",
      createdAtUtcMs: now,
      paidAtUtcMs: null,
    });

    const payoutRun = await postJsonWithHeaders(
      baseUrl,
      "/payout-batches/run",
      { nowUtcMs: now + 120_000 },
      { authorization: `Bearer ${verifyBody.accessToken}` },
    );
    assert.equal(payoutRun.status, 200);
    const payoutBody = (await payoutRun.json()) as { batch: { lineIds: string[] } };
    assert.deepEqual(payoutBody.batch.lineIds, ["led_due"]);
    assert.equal(app.store.ledgerLines.get("led_due")?.status, "PAID");
    assert.equal(app.store.ledgerLines.get("led_future")?.status, "ACCRUED");
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
