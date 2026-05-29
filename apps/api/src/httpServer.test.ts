import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { createApp } from "./httpServer.ts";
import {
  bookShipment,
  createCarrier,
  grantOpsAdmin,
  publishAnchorTrip,
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

async function issueOpsAdminToken(baseUrl: string, app: AppBundle, phone = "9876543210"): Promise<{
  token: string;
  orgId: string;
}> {
  const onboard = registerSoloOwnerOperatorDriver(app.store, {
    fullName: "Ops Driver",
    phone,
    orgDisplayName: "Ops Transport",
    vehicleRegistrationNumber: "HR26AB1234",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  grantOpsAdmin(app.store, { phone: onboard.user.phone });

  const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone: onboard.user.phone });
  assert.equal(start.status, 200);
  const startBody = (await start.json()) as { challengeId: string };

  const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
    phone: onboard.user.phone,
    challengeId: startBody.challengeId,
    code: "123456",
  });
  assert.equal(verify.status, 200);
  const verifyBody = (await verify.json()) as { accessToken: string };
  assert.ok(verifyBody.accessToken);

  return { token: verifyBody.accessToken, orgId: onboard.org.id };
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
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;
  delete process.env.ALLOW_X_USER_ID;

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

    const payouts = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(payouts.status, 401);
    assert.deepEqual(await payouts.json(), { error: "unauthorized" });

    const payoutRun = await postJson(baseUrl, "/payout-batches/run", {});
    assert.equal(payoutRun.status, 401);
    assert.deepEqual(await payoutRun.json(), { error: "unauthorized" });
  });
});

test("production ignores x-user-id shortcut even when ALLOW_X_USER_ID is set", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ALLOW_X_USER_ID = "1";

  await withApp(t, async (baseUrl, app) => {
    const onboard = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Ravi Kumar",
      phone: "9876543211",
      orgDisplayName: "Ravi Transport",
      vehicleRegistrationNumber: "HR26AB1111",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });

    const res = await fetch(`${baseUrl}/v1/pilot/carrier/ledger?orgId=${onboard.org.id}`, {
      headers: { "x-user-id": onboard.user.id },
    });
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "unauthorized" });
  });
});

test("production demo flag does not allow anonymous shipment state mutations", async (t) => {
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

test("production payout run requires ops bearer and ignores client cutoff time", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const { token, orgId } = await issueOpsAdminToken(baseUrl, app, "9876543212");
    const now = Date.now();
    const futureCutoff = now + 30 * 24 * 60 * 60 * 1000;
    app.store.ledgerLines.set("led_future", {
      id: "led_future",
      shipmentId: "shp_future",
      carrierId: orgId,
      grossPaise: 10000,
      commissionPaise: 1000,
      netToCarrierPaise: 9000,
      podAtUtcMs: now,
      firstPayoutEligibleAtUtcMs: futureCutoff,
      payoutBatchCutoffUtcMs: futureCutoff,
      status: "ACCRUED",
      createdAtUtcMs: now,
      paidAtUtcMs: null,
    });

    const res = await postJson(
      baseUrl,
      "/payout-batches/run",
      { nowUtcMs: futureCutoff + 1 },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(res.status, 200);
    const body = (await res.json()) as { batch: { totalNetToCarrierPaise: number; lineIds: string[] } };
    assert.equal(body.batch.totalNetToCarrierPaise, 0);
    assert.deepEqual(body.batch.lineIds, []);
    assert.equal(app.store.ledgerLines.get("led_future")?.status, "ACCRUED");
  });
});

test("production POD ignores client-supplied delivery timestamp", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const { token } = await issueOpsAdminToken(baseUrl, app, "9876543213");
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
    const shipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "ACME Manufacturing",
      weightKg: 200,
      pickupAddress: "Sector 44, Gurugram",
      dropAddress: "Sitapura, Jaipur",
    });

    const forgedPodAtUtcMs = 1;
    const res = await postJson(
      baseUrl,
      `/shipments/${shipment.id}/pod`,
      { podAtUtcMs: forgedPodAtUtcMs },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(res.status, 200);
    const body = (await res.json()) as { shipment: { podAtUtcMs: number }; ledgerLine: { podAtUtcMs: number } };
    assert.notEqual(body.shipment.podAtUtcMs, forgedPodAtUtcMs);
    assert.notEqual(body.ledgerLine.podAtUtcMs, forgedPodAtUtcMs);
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
