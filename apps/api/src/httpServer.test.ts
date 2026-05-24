import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import { grantOpsAdmin, registerSoloOwnerOperatorDriver } from "./services.ts";

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

async function postJson(baseUrl: string, path: string, body: unknown, headers?: Record<string, string>): Promise<Response> {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(headers ?? {}) },
    body: JSON.stringify(body),
  });
}

function restoreEnv(prev: Record<string, string | undefined>): void {
  for (const [key, value] of Object.entries(prev)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
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

test("production requires ops-admin bearer for legacy payout and ledger routes", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => restoreEnv(prev));

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const noAuthLedger = await fetch(`${baseUrl}/carriers/org_missing/ledger`);
    assert.equal(noAuthLedger.status, 401);
    assert.deepEqual(await noAuthLedger.json(), { error: "unauthorized" });

    const noAuthBatches = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(noAuthBatches.status, 401);
    assert.deepEqual(await noAuthBatches.json(), { error: "unauthorized" });

    const noAuthRun = await postJson(baseUrl, "/payout-batches/run", {});
    assert.equal(noAuthRun.status, 401);
    assert.deepEqual(await noAuthRun.json(), { error: "unauthorized" });

    const driver = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Non Ops Driver",
      phone: "9876543201",
      orgDisplayName: "Non Ops Transport",
      vehicleRegistrationNumber: "HR26AA0001",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    const nonOpsChallenge = pilotOtpStart(app.store, { phone: driver.user.phone });
    const nonOpsToken = pilotOtpVerify(app.store, {
      phone: driver.user.phone,
      challengeId: nonOpsChallenge.challengeId,
      code: "123456",
    }).accessToken;

    const nonOps = await fetch(`${baseUrl}/payout-batches`, {
      headers: { authorization: `Bearer ${nonOpsToken}` },
    });
    assert.equal(nonOps.status, 403);
    assert.deepEqual(await nonOps.json(), { error: "forbidden" });

    const ops = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Ops Driver",
      phone: "9876543202",
      orgDisplayName: "Ops Transport",
      vehicleRegistrationNumber: "HR26AA0002",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    grantOpsAdmin(app.store, { phone: ops.user.phone });
    const opsChallenge = pilotOtpStart(app.store, { phone: ops.user.phone });
    const opsToken = pilotOtpVerify(app.store, {
      phone: ops.user.phone,
      challengeId: opsChallenge.challengeId,
      code: "123456",
    }).accessToken;

    const futureCutoffUtcMs = Date.now() + 24 * 60 * 60 * 1000;
    app.store.ledgerLines.set("ll_future", {
      id: "ll_future",
      shipmentId: "shp_future",
      carrierId: ops.org.id,
      grossPaise: 100_00,
      commissionPaise: 10_00,
      netToCarrierPaise: 90_00,
      podAtUtcMs: Date.now(),
      firstPayoutEligibleAtUtcMs: futureCutoffUtcMs,
      payoutBatchCutoffUtcMs: futureCutoffUtcMs,
      status: "ACCRUED",
      createdAtUtcMs: Date.now(),
      paidAtUtcMs: null,
    });

    const ledger = await fetch(`${baseUrl}/carriers/${ops.org.id}/ledger`, {
      headers: { authorization: `Bearer ${opsToken}` },
    });
    assert.equal(ledger.status, 200);
    const ledgerBody = (await ledger.json()) as { lines?: unknown[] };
    assert.equal(ledgerBody.lines?.length, 1);

    const run = await postJson(
      baseUrl,
      "/payout-batches/run",
      { nowUtcMs: futureCutoffUtcMs + 1 },
      { authorization: `Bearer ${opsToken}` },
    );
    assert.equal(run.status, 200);
    const runBody = (await run.json()) as { batch?: { lineIds?: string[]; totalNetToCarrierPaise?: number } };
    assert.deepEqual(runBody.batch?.lineIds, []);
    assert.equal(runBody.batch?.totalNetToCarrierPaise, 0);
    assert.equal(app.store.ledgerLines.get("ll_future")?.status, "ACCRUED");
  });
});
