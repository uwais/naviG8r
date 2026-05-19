import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import {
  bookShipment,
  createCarrier,
  grantOpsAdmin,
  markPodDelivered,
  publishAnchorTrip,
  registerCustomerOrgAdmin,
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

function bearerForPhone(app: AppBundle, phone: string): string {
  const start = pilotOtpStart(app.store, { phone });
  const verified = pilotOtpVerify(app.store, {
    phone,
    challengeId: start.challengeId,
    code: start.debugCode ?? "123456",
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

test("admin HTML does not embed store data and snapshot requires ops admin", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const admin = registerCustomerOrgAdmin(app.store, {
      fullName: "Ops User",
      phone: "9000000001",
      orgDisplayName: "Ops Org",
    });
    grantOpsAdmin(app.store, { phone: admin.user.phone });
    const carrier = createCarrier(app.store, "Sensitive Carrier");
    const trip = publishAnchorTrip(app.store, {
      carrierId: carrier.id,
      originCity: "SecretOrigin",
      destCity: "SecretDest",
      windowStart: "2026-04-24T00:00:00+05:30",
      windowEnd: "2026-04-25T23:59:59+05:30",
      vehicleClass: "MEDIUM",
      capacityKg: 1000,
    });
    const shipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "Sensitive Customer",
      weightKg: 200,
      pickupAddress: "Hidden pickup",
      dropAddress: "Hidden drop",
    });

    const page = await fetch(`${baseUrl}/admin`);
    assert.equal(page.status, 200);
    const html = await page.text();
    assert.equal(html.includes(admin.user.phone), false);
    assert.equal(html.includes(shipment.id), false);
    assert.equal(html.includes("Sensitive Customer"), false);

    const unauth = await fetch(`${baseUrl}/v1/admin/snapshot`);
    assert.equal(unauth.status, 401);

    const token = bearerForPhone(app, admin.user.phone);
    const authed = await fetch(`${baseUrl}/v1/admin/snapshot`, {
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(authed.status, 200);
    const body = (await authed.json()) as { users?: Array<{ phone: string }>; shipments?: Array<{ id: string }> };
    assert.equal(body.users?.some((u) => u.phone === admin.user.phone), true);
    assert.equal(body.shipments?.some((s) => s.id === shipment.id), true);
  });
});

test("legacy demo flag does not allow unauthenticated shipment mutations", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";

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
    const shipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "ACME Manufacturing",
      weightKg: 200,
      pickupAddress: "Sector 44, Gurugram",
      dropAddress: "Sitapura, Jaipur",
    });

    const pod = await postJson(baseUrl, `/shipments/${shipment.id}/pod`, {});
    assert.equal(pod.status, 401);
    assert.equal(app.store.shipments.get(shipment.id)?.status, "BOOKED");
    assert.equal(app.store.ledgerLines.size, 0);

    const refund = await postJson(baseUrl, `/shipments/${shipment.id}/fail-refund`, {});
    assert.equal(refund.status, 401);
    assert.equal(app.store.shipments.get(shipment.id)?.status, "BOOKED");
    assert.equal(app.store.payments.get(shipment.paymentId)?.status, "CAPTURED");
  });
});

test("ledger and payout routes require ops admin bearer", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const admin = registerCustomerOrgAdmin(app.store, {
      fullName: "Ops User",
      phone: "9000000002",
      orgDisplayName: "Ops Org",
    });
    grantOpsAdmin(app.store, { phone: admin.user.phone });

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
    const pod = markPodDelivered(app.store, { shipmentId: shipment.id });

    const unauthLedger = await fetch(`${baseUrl}/carriers/${carrier.id}/ledger`);
    assert.equal(unauthLedger.status, 401);

    const unauthRun = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: pod.ledgerLine.payoutBatchCutoffUtcMs });
    assert.equal(unauthRun.status, 401);
    assert.equal(app.store.ledgerLines.get(pod.ledgerLine.id)?.status, "ACCRUED");

    const token = bearerForPhone(app, admin.user.phone);
    const authLedger = await fetch(`${baseUrl}/carriers/${carrier.id}/ledger`, {
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(authLedger.status, 200);
    const ledgerBody = (await authLedger.json()) as { lines?: Array<{ id: string }> };
    assert.equal(ledgerBody.lines?.some((line) => line.id === pod.ledgerLine.id), true);

    const authRun = await fetch(`${baseUrl}/payout-batches/run`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ nowUtcMs: pod.ledgerLine.payoutBatchCutoffUtcMs }),
    });
    assert.equal(authRun.status, 200);
    assert.equal(app.store.ledgerLines.get(pod.ledgerLine.id)?.status, "PAID");
  });
});
