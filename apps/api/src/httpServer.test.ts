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
  publishAnchorTripAsPilotDriver,
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

function bearerForPhone(app: AppBundle, phone: string): string {
  const start = pilotOtpStart(app.store, { phone });
  return pilotOtpVerify(app.store, {
    phone,
    challengeId: start.challengeId,
    code: start.debugCode ?? "123456",
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

test("production ignores x-user-id bypass and does not embed admin data", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.ALLOW_X_USER_ID = "1";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const onboard = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Sensitive Driver",
      phone: "9876543210",
      orgDisplayName: "Sensitive Transport",
      vehicleRegistrationNumber: "HR26AB1234",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });

    const me = await fetch(`${baseUrl}/v1/pilot/me`, {
      headers: { "x-user-id": onboard.user.id },
    });
    assert.equal(me.status, 401);

    const admin = await fetch(`${baseUrl}/admin`);
    assert.equal(admin.status, 200);
    const html = await admin.text();
    assert.equal(html.includes("Sensitive Driver"), false);
    assert.equal(html.includes("9876543210"), false);
  });
});

test("production legacy payout endpoints require ops auth and ignore client payout clock", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

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
      customerOrgName: "ACME",
      weightKg: 100,
      pickupAddress: "Gurugram",
      dropAddress: "Jaipur",
    });
    const pod = markPodDelivered(app.store, { shipmentId: shipment.id });

    const ledgerNoAuth = await fetch(`${baseUrl}/carriers/${carrier.id}/ledger`);
    assert.equal(ledgerNoAuth.status, 401);

    const runNoAuth = await postJson(baseUrl, "/payout-batches/run", {});
    assert.equal(runNoAuth.status, 401);

    const batchesNoAuth = await fetch(`${baseUrl}/payout-batches`);
    assert.equal(batchesNoAuth.status, 401);

    const ops = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Ops Admin",
      phone: "9876543211",
      orgDisplayName: "Ops Carrier",
      vehicleRegistrationNumber: "HR26AB1235",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    grantOpsAdmin(app.store, { phone: ops.user.phone });
    const token = bearerForPhone(app, ops.user.phone);
    const auth = { authorization: `Bearer ${token}` };

    const ledger = await fetch(`${baseUrl}/carriers/${carrier.id}/ledger`, { headers: auth });
    assert.equal(ledger.status, 200);
    assert.equal(((await ledger.json()) as { lines: unknown[] }).lines.length, 1);

    const farFuture = Date.now() + 60 * 24 * 60 * 60 * 1000;
    const run = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: farFuture }, auth);
    assert.equal(run.status, 200);
    const body = (await run.json()) as { batch: { lineIds: string[] } };
    assert.deepEqual(body.batch.lineIds, []);
    assert.equal(app.store.ledgerLines.get(pod.ledgerLine.id)?.status, "ACCRUED");
  });
});

test("production demo flag does not allow anonymous shipment mutation or client POD clock", async (t) => {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  await withApp(t, async (baseUrl, app) => {
    const onboard = registerSoloOwnerOperatorDriver(app.store, {
      fullName: "Ravi Kumar",
      phone: "9876543212",
      orgDisplayName: "Ravi Transport",
      vehicleRegistrationNumber: "HR26AB1236",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    const trip = publishAnchorTripAsPilotDriver(app.store, {
      userId: onboard.user.id,
      orgId: onboard.org.id,
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
    const refundShipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "ACME",
      weightKg: 100,
      pickupAddress: "Gurugram",
      dropAddress: "Jaipur",
    });

    const podNoAuth = await postJson(baseUrl, `/shipments/${shipment.id}/pod`, {});
    assert.equal(podNoAuth.status, 401);
    assert.equal(app.store.shipments.get(shipment.id)?.status, "BOOKED");

    const refundNoAuth = await postJson(baseUrl, `/shipments/${refundShipment.id}/fail-refund`, {});
    assert.equal(refundNoAuth.status, 401);
    assert.equal(app.store.shipments.get(refundShipment.id)?.status, "BOOKED");

    const token = bearerForPhone(app, onboard.user.phone);
    const pod = await postJson(
      baseUrl,
      `/shipments/${shipment.id}/pod`,
      { podAtUtcMs: 0 },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(pod.status, 200);
    assert.notEqual(app.store.shipments.get(shipment.id)?.podAtUtcMs, 0);
  });
});
