import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import {
  bookShipment,
  createCarrier,
  markPodDelivered,
  publishAnchorTrip,
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

function seedBookedShipment(store: AppBundle["store"]) {
  const carrier = createCarrier(store, "Carrier One");
  const trip = publishAnchorTrip(store, {
    carrierId: carrier.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });
  return { carrier, trip, shipment };
}

function createOpsBearerToken(store: AppBundle["store"], phone = "9876543210"): string {
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ops Admin",
    phone,
    orgDisplayName: "Ops Carrier",
    vehicleRegistrationNumber: "HR55AB1234",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 1000,
  });
  const start = pilotOtpStart(store, { phone: onboard.user.phone });
  const verified = pilotOtpVerify(store, {
    phone: onboard.user.phone,
    challengeId: start.challengeId,
    code: String(process.env.OTP_FIXED_CODE ?? "123456"),
  });
  return verified.accessToken;
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

test("production ignores ALLOW_X_USER_ID header impersonation", async (t) => {
  const prev = {
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
  };
  t.after(() => {
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
  });

  process.env.ALLOW_X_USER_ID = "1";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";

  await withApp(t, async (baseUrl, app) => {
    const onboard = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Header Spoof Target",
      phone: "9876500001",
      orgDisplayName: "Spoof Carrier",
      vehicleRegistrationNumber: "HR55AA0001",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 1000,
    });

    const res = await fetch(`${baseUrl}/v1/pilot/me`, { headers: { "x-user-id": onboard.user.id } });
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "unauthorized" });
  });
});

test("production demo flag does not allow anonymous POD or refund mutation", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    PAYMENT_PROVIDER: process.env.PAYMENT_PROVIDER,
    RAZORPAY_KEY_ID: process.env.RAZORPAY_KEY_ID,
    RAZORPAY_KEY_SECRET: process.env.RAZORPAY_KEY_SECRET,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.PAYMENT_PROVIDER = prev.PAYMENT_PROVIDER;
    process.env.RAZORPAY_KEY_ID = prev.RAZORPAY_KEY_ID;
    process.env.RAZORPAY_KEY_SECRET = prev.RAZORPAY_KEY_SECRET;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  delete process.env.PAYMENT_PROVIDER;
  delete process.env.RAZORPAY_KEY_ID;
  delete process.env.RAZORPAY_KEY_SECRET;

  await withApp(t, async (baseUrl, app) => {
    const { shipment } = seedBookedShipment(app.store);

    const pod = await postJson(baseUrl, `/shipments/${shipment.id}/pod`, { podAtUtcMs: 0 });
    assert.equal(pod.status, 401);
    assert.deepEqual(await pod.json(), { error: "unauthorized" });
    assert.equal(app.store.shipments.get(shipment.id)?.status, "BOOKED");
    assert.equal(app.store.ledgerLines.size, 0);

    const refund = await postJson(baseUrl, `/shipments/${shipment.id}/fail-refund`, {});
    assert.equal(refund.status, 401);
    assert.deepEqual(await refund.json(), { error: "unauthorized" });
    assert.equal(app.store.shipments.get(shipment.id)?.status, "BOOKED");
    assert.equal(app.store.payments.get(shipment.paymentId)?.status, "CAPTURED");
  });
});

test("production legacy payout routes require ops auth and ignore client clock", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    OPS_ADMIN_PHONES: process.env.OPS_ADMIN_PHONES,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
    PAYMENT_PROVIDER: process.env.PAYMENT_PROVIDER,
    RAZORPAY_KEY_ID: process.env.RAZORPAY_KEY_ID,
    RAZORPAY_KEY_SECRET: process.env.RAZORPAY_KEY_SECRET,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OPS_ADMIN_PHONES = prev.OPS_ADMIN_PHONES;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
    process.env.PAYMENT_PROVIDER = prev.PAYMENT_PROVIDER;
    process.env.RAZORPAY_KEY_ID = prev.RAZORPAY_KEY_ID;
    process.env.RAZORPAY_KEY_SECRET = prev.RAZORPAY_KEY_SECRET;
  });

  process.env.AUTH_SECRET = "test_auth_secret_for_http_server";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  process.env.OPS_ADMIN_PHONES = "9876543210";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  delete process.env.PAYMENT_PROVIDER;
  delete process.env.RAZORPAY_KEY_ID;
  delete process.env.RAZORPAY_KEY_SECRET;

  await withApp(t, async (baseUrl, app) => {
    const token = createOpsBearerToken(app.store);
    const { carrier, shipment } = seedBookedShipment(app.store);
    const delivered = markPodDelivered(app.store, { shipmentId: shipment.id, podAtUtcMs: Date.now() });
    const lineId = delivered.ledgerLine.id;

    const unauthLedger = await fetch(`${baseUrl}/carriers/${carrier.id}/ledger`);
    assert.equal(unauthLedger.status, 401);
    assert.deepEqual(await unauthLedger.json(), { error: "unauthorized" });

    const premature = await postJsonWithHeaders(
      baseUrl,
      "/payout-batches/run",
      { nowUtcMs: delivered.ledgerLine.payoutBatchCutoffUtcMs },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(premature.status, 200);
    const body = (await premature.json()) as { batch: { totalNetToCarrierPaise: number; lineIds: string[] } };
    assert.equal(body.batch.totalNetToCarrierPaise, 0);
    assert.deepEqual(body.batch.lineIds, []);
    assert.equal(app.store.ledgerLines.get(lineId)?.status, "ACCRUED");
  });
});

test("production admin page does not embed store data and snapshot requires ops auth", async (t) => {
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

  process.env.AUTH_SECRET = "test_auth_secret_for_admin_page";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  process.env.OPS_ADMIN_PHONES = "9876543210";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    registerCustomerOrgAdmin(app.store, {
      fullName: "Secret Customer",
      phone: "9876500002",
      orgDisplayName: "Sensitive Factory",
    });

    const html = await fetch(`${baseUrl}/admin`);
    assert.equal(html.status, 200);
    const text = await html.text();
    assert.match(text, /Admin Login/);
    assert.doesNotMatch(text, /Secret Customer/);
    assert.doesNotMatch(text, /Sensitive Factory/);

    const unauthSnapshot = await fetch(`${baseUrl}/v1/admin/snapshot`);
    assert.equal(unauthSnapshot.status, 401);
    assert.deepEqual(await unauthSnapshot.json(), { error: "unauthorized" });

    const token = createOpsBearerToken(app.store);
    const authedSnapshot = await fetch(`${baseUrl}/v1/admin/snapshot`, {
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(authedSnapshot.status, 200);
    const snapshotText = await authedSnapshot.text();
    assert.match(snapshotText, /Secret Customer/);
    assert.match(snapshotText, /Sensitive Factory/);
  });
});
