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

/**
 * In production, legacy demo/admin routes return 403.
 * Public marketplace routes (anchor-trips, quote, book, customer shipments with Bearer) stay enabled;
 * unauthenticated shipment reads/mutations return 401 (not 403).
 */
test("production disables legacy demo routes that expose or mutate operator state", async (t) => {
  const prev = {
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
  };
  t.after(() => {
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
  });

  process.env.ALLOW_X_USER_ID = "1";
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

    const ledger = await fetch(`${baseUrl}/carriers/car_123/ledger`);
    assert.equal(ledger.status, 401);
    assert.deepEqual(await ledger.json(), { error: "unauthorized" });

    const payoutRun = await postJson(baseUrl, "/payout-batches/run", {});
    assert.equal(payoutRun.status, 401);
    assert.deepEqual(await payoutRun.json(), { error: "unauthorized" });

    const payoutList = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(payoutList.status, 401);
    assert.deepEqual(await payoutList.json(), { error: "unauthorized" });

    const pilotMe = await fetch(`${baseUrl}/v1/pilot/me`, { headers: { "x-user-id": "usr_spoofed" } });
    assert.equal(pilotMe.status, 401);
    assert.deepEqual(await pilotMe.json(), { error: "unauthorized" });

    const login = await postJson(baseUrl, "/v1/pilot/driver/login", { phone: "9876543210" });
    assert.equal(login.status, 403);
    assert.deepEqual(await login.json(), { error: "legacy_demo_surface_disabled" });
  });
});

test("ledger and payout endpoints require ops-admin bearer access", async (t) => {
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

  process.env.AUTH_SECRET = "test-auth-secret-at-least-16";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;
  process.env.NODE_ENV = "production";
  process.env.OPS_ADMIN_PHONES = "9876543210";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "654321";

  await withApp(t, async (baseUrl) => {
    const nonOpsRegister = await postJson(baseUrl, "/v1/pilot/customer/register", {
      fullName: "Customer User",
      phone: "9123456701",
      orgDisplayName: "Customer Co",
    });
    assert.equal(nonOpsRegister.status, 201);

    const adminRegister = await postJson(baseUrl, "/v1/pilot/customer/register", {
      fullName: "Ops User",
      phone: "9876543210",
      orgDisplayName: "Ops Co",
    });
    assert.equal(adminRegister.status, 201);

    const tokenFor = async (phone: string): Promise<string> => {
      const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone });
      assert.equal(start.status, 200);
      const startBody = (await start.json()) as { challengeId: string; debugCode?: string };
      const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
        phone,
        challengeId: startBody.challengeId,
        code: startBody.debugCode,
      });
      assert.equal(verify.status, 200);
      const verifyBody = (await verify.json()) as { accessToken?: string };
      assert.ok(verifyBody.accessToken);
      return verifyBody.accessToken;
    };

    const nonOpsToken = await tokenFor("9123456701");
    const forbiddenLedger = await fetch(`${baseUrl}/carriers/car_123/ledger`, {
      headers: { authorization: `Bearer ${nonOpsToken}` },
    });
    assert.equal(forbiddenLedger.status, 403);
    assert.deepEqual(await forbiddenLedger.json(), { error: "forbidden" });

    const opsToken = await tokenFor("9876543210");
    const authHeaders = { authorization: `Bearer ${opsToken}` };

    const ledger = await fetch(`${baseUrl}/carriers/car_123/ledger`, { headers: authHeaders });
    assert.equal(ledger.status, 200);
    assert.deepEqual(await ledger.json(), { lines: [] });

    const payoutRun = await fetch(`${baseUrl}/payout-batches/run`, {
      method: "POST",
      headers: { ...authHeaders, "content-type": "application/json" },
      body: JSON.stringify({ nowUtcMs: 123 }),
    });
    assert.equal(payoutRun.status, 200);
    const payoutRunBody = (await payoutRun.json()) as { batch?: { lineIds?: string[] } };
    assert.deepEqual(payoutRunBody.batch?.lineIds, []);

    const payoutList = await fetch(`${baseUrl}/payout-batches`, { headers: authHeaders });
    assert.equal(payoutList.status, 200);
    const payoutListBody = (await payoutList.json()) as { payoutBatches?: unknown[] };
    assert.equal(payoutListBody.payoutBatches?.length, 1);
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
