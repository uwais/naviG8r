import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import { grantOpsAdmin, registerCustomerOrgAdmin } from "./services.ts";

type AppBundle = Awaited<ReturnType<typeof createApp>>;
type EnvSnapshot = Record<string, string | undefined>;

function restoreEnv(snapshot: EnvSnapshot): void {
  for (const [key, value] of Object.entries(snapshot)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
}

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

async function postJson(
  baseUrl: string,
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
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
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
  };
  t.after(() => restoreEnv(prev));

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;
  process.env.ALLOW_X_USER_ID = "1";

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

    const run = await postJson(baseUrl, "/payout-batches/run", {});
    assert.equal(run.status, 401);
    assert.deepEqual(await run.json(), { error: "unauthorized" });

    const batches = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(batches.status, 401);
    assert.deepEqual(await batches.json(), { error: "unauthorized" });

    const me = await fetch(`${baseUrl}/v1/pilot/me`, { headers: { "x-user-id": "usr_victim" } });
    assert.equal(me.status, 401);
    assert.deepEqual(await me.json(), { error: "unauthorized" });
  });
});

test("production keeps shipment settlement mutations authenticated even if demo surface is enabled", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
  };
  t.after(() => restoreEnv(prev));

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";

  await withApp(t, async (baseUrl) => {
    const pod = await postJson(baseUrl, "/shipments/shp_123/pod", {});
    assert.equal(pod.status, 401);
    assert.deepEqual(await pod.json(), { error: "unauthorized" });

    const refund = await postJson(baseUrl, "/shipments/shp_123/fail-refund", {});
    assert.equal(refund.status, 401);
    assert.deepEqual(await refund.json(), { error: "unauthorized" });
  });
});

test("production payout run requires ops admin and ignores client supplied clock", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => restoreEnv(prev));

  process.env.AUTH_SECRET = "0123456789abcdef0123456789abcdef";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const ops = registerCustomerOrgAdmin(app.store, {
      fullName: "Ops Admin",
      phone: "9876500000",
      orgDisplayName: "Ops Customer",
    });
    grantOpsAdmin(app.store, { phone: ops.user.phone });

    const futureCutoff = Date.now() + 24 * 60 * 60 * 1000;
    app.store.ledgerLines.set("led_future", {
      id: "led_future",
      shipmentId: "shp_future",
      carrierId: "car_future",
      grossPaise: 10000,
      commissionPaise: 1000,
      netToCarrierPaise: 9000,
      podAtUtcMs: Date.now(),
      firstPayoutEligibleAtUtcMs: futureCutoff,
      payoutBatchCutoffUtcMs: futureCutoff,
      status: "ACCRUED",
      createdAtUtcMs: Date.now(),
      paidAtUtcMs: null,
    });

    const ch = pilotOtpStart(app.store, { phone: ops.user.phone });
    const session = pilotOtpVerify(app.store, {
      phone: ops.user.phone,
      challengeId: ch.challengeId,
      code: "123456",
    });

    const res = await postJson(
      baseUrl,
      "/payout-batches/run",
      { nowUtcMs: futureCutoff + 1 },
      { authorization: `Bearer ${session.accessToken}` },
    );
    assert.equal(res.status, 200);
    const body = (await res.json()) as { batch: { lineIds: string[] } };
    assert.deepEqual(body.batch.lineIds, []);
    assert.equal(app.store.ledgerLines.get("led_future")?.status, "ACCRUED");
  });
});

test("legacy demo surface remains available outside production", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
  };
  t.after(() => restoreEnv(prev));

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
