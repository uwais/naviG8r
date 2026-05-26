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

async function otpLogin(baseUrl: string, phone: string): Promise<string> {
  const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone });
  assert.equal(start.status, 200);
  const startBody = (await start.json()) as { challengeId: string };
  const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
    phone,
    challengeId: startBody.challengeId,
    code: "123456",
  });
  assert.equal(verify.status, 200);
  const verifyBody = (await verify.json()) as { accessToken: string };
  return verifyBody.accessToken;
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

    const run = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: 9_999_999_999_999 });
    assert.equal(run.status, 401);
    assert.deepEqual(await run.json(), { error: "unauthorized" });

    const batches = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(batches.status, 401);
    assert.deepEqual(await batches.json(), { error: "unauthorized" });
  });
});

test("production ignores x-user-id impersonation header", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ALLOW_X_USER_ID = "1";

  await withApp(t, async (baseUrl, app) => {
    const registered = registerCustomerOrgAdmin(app.store, {
      fullName: "Buyer",
      phone: "9123456780",
      orgDisplayName: "Buyer Co",
    });

    const me = await fetch(`${baseUrl}/v1/pilot/me`, { headers: { "x-user-id": registered.user.id } });
    assert.equal(me.status, 401);
    assert.deepEqual(await me.json(), { error: "unauthorized" });
  });
});

test("production payout batch run requires ops auth and ignores caller clock", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    OPS_ADMIN_PHONES: process.env.OPS_ADMIN_PHONES,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OPS_ADMIN_PHONES = prev.OPS_ADMIN_PHONES;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = "test-secret-for-http-server";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.OPS_ADMIN_PHONES = "9123456781";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const admin = registerCustomerOrgAdmin(app.store, {
      fullName: "Ops",
      phone: "9123456781",
      orgDisplayName: "Ops Co",
    });
    const futureCutoff = Date.now() + 24 * 60 * 60 * 1000;
    app.store.ledgerLines.set("led_future", {
      id: "led_future",
      shipmentId: "shp_future",
      carrierId: "org_future",
      grossPaise: 1000,
      commissionPaise: 100,
      netToCarrierPaise: 900,
      podAtUtcMs: Date.now(),
      firstPayoutEligibleAtUtcMs: futureCutoff,
      payoutBatchCutoffUtcMs: futureCutoff,
      status: "ACCRUED",
      createdAtUtcMs: Date.now(),
      paidAtUtcMs: null,
    });

    const unauth = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: 9_999_999_999_999 });
    assert.equal(unauth.status, 401);
    assert.equal(app.store.ledgerLines.get("led_future")?.status, "ACCRUED");

    const token = await otpLogin(baseUrl, admin.user.phone);
    const authed = await postJson(
      baseUrl,
      "/payout-batches/run",
      { nowUtcMs: 9_999_999_999_999 },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(authed.status, 200);
    const body = (await authed.json()) as { batch: { totalNetToCarrierPaise: number; lineIds: string[] } };
    assert.equal(body.batch.totalNetToCarrierPaise, 0);
    assert.deepEqual(body.batch.lineIds, []);
    assert.equal(app.store.ledgerLines.get("led_future")?.status, "ACCRUED");
  });
});

test("production POD uses server time for payout schedule", async (t) => {
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

  process.env.AUTH_SECRET = "test-secret-for-http-server";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const customer = registerCustomerOrgAdmin(app.store, {
      fullName: "Buyer",
      phone: "9123456782",
      orgDisplayName: "Buyer Co",
    });
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
      customerOrgName: "Buyer Co",
      customerOrg: { id: customer.org.id, displayName: customer.org.displayName },
      weightKg: 200,
      pickupAddress: "Sector 44, Gurugram",
      dropAddress: "Sitapura, Jaipur",
    });

    const token = await otpLogin(baseUrl, customer.user.phone);
    const before = Date.now() - 1;
    const pod = await postJson(
      baseUrl,
      `/shipments/${shipment.id}/pod`,
      { podAtUtcMs: 0 },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(pod.status, 200);
    const delivered = app.store.shipments.get(shipment.id);
    assert.ok(delivered?.podAtUtcMs != null);
    assert.ok(delivered.podAtUtcMs >= before);
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
