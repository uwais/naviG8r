import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
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

test("production admin shell does not leak store data before ops auth", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
    PAYMENT_PROVIDER: process.env.PAYMENT_PROVIDER,
    PERSISTENCE: process.env.PERSISTENCE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
    process.env.PAYMENT_PROVIDER = prev.PAYMENT_PROVIDER;
    process.env.PERSISTENCE = prev.PERSISTENCE;
  });

  process.env.AUTH_SECRET = "test-auth-secret-at-least-16";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  process.env.PAYMENT_PROVIDER = "MOCK";
  delete process.env.PERSISTENCE;

  await withApp(t, async (baseUrl, app) => {
    const ops = registerCustomerOrgAdmin(app.store, {
      fullName: "Sensitive Ops User",
      phone: "9999990000",
      orgDisplayName: "Sensitive Customer Org",
    });
    grantOpsAdmin(app.store, { phone: ops.user.phone });

    const admin = await fetch(`${baseUrl}/admin`);
    assert.equal(admin.status, 200);
    const adminHtml = await admin.text();
    assert.ok(!adminHtml.includes("Sensitive Ops User"));
    assert.ok(!adminHtml.includes("9999990000"));
    assert.ok(!adminHtml.includes("Sensitive Customer Org"));

    const unauthSnapshot = await fetch(`${baseUrl}/v1/admin/snapshot`);
    assert.equal(unauthSnapshot.status, 401);
    assert.deepEqual(await unauthSnapshot.json(), { error: "unauthorized" });

    const usersDump = await fetch(`${baseUrl}/v1/users`);
    assert.equal(usersDump.status, 401);
    assert.deepEqual(await usersDump.json(), { error: "unauthorized" });

    const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone: ops.user.phone });
    assert.equal(start.status, 200);
    const started = (await start.json()) as { challengeId: string; debugCode?: string };
    assert.equal(started.debugCode, "123456");

    const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
      phone: ops.user.phone,
      challengeId: started.challengeId,
      code: "123456",
    });
    assert.equal(verify.status, 200);
    const verified = (await verify.json()) as { accessToken: string; isOpsAdmin: boolean };
    assert.equal(verified.isOpsAdmin, true);

    const authedSnapshot = await fetch(`${baseUrl}/v1/admin/snapshot`, {
      headers: { authorization: `Bearer ${verified.accessToken}` },
    });
    assert.equal(authedSnapshot.status, 200);
    const snapshot = (await authedSnapshot.json()) as { users: Array<{ phone: string }> };
    assert.ok(snapshot.users.some((u) => u.phone === ops.user.phone));
  });
});

test("production legacy admin flag does not allow unauthenticated money mutations", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    PAYMENT_PROVIDER: process.env.PAYMENT_PROVIDER,
    PERSISTENCE: process.env.PERSISTENCE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.PAYMENT_PROVIDER = prev.PAYMENT_PROVIDER;
    process.env.PERSISTENCE = prev.PERSISTENCE;
  });

  process.env.AUTH_SECRET = "test-auth-secret-at-least-16";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  process.env.NODE_ENV = "production";
  process.env.PAYMENT_PROVIDER = "MOCK";
  delete process.env.PERSISTENCE;

  await withApp(t, async (baseUrl, app) => {
    const carrier = createCarrier(app.store, "Carrier Ledger");
    const trip = publishAnchorTrip(app.store, {
      carrierId: carrier.id,
      originCity: "Delhi",
      destCity: "Mumbai",
      windowStart: "2026-05-20T12:00:00+05:30",
      windowEnd: "2026-05-20T18:00:00+05:30",
      vehicleClass: "MEDIUM",
      capacityKg: 1000,
    });
    const podShipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "Customer A",
      weightKg: 100,
      pickupAddress: "A",
      dropAddress: "B",
    });
    const refundShipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "Customer B",
      weightKg: 100,
      pickupAddress: "A",
      dropAddress: "B",
    });
    const payoutShipment = bookShipment(app.store, {
      anchorTripId: trip.id,
      customerOrgName: "Customer C",
      weightKg: 100,
      pickupAddress: "A",
      dropAddress: "B",
    });
    const payoutLine = markPodDelivered(app.store, {
      shipmentId: payoutShipment.id,
      podAtUtcMs: 0,
    }).ledgerLine;

    const pod = await postJson(baseUrl, `/shipments/${podShipment.id}/pod`, {});
    assert.equal(pod.status, 401);
    assert.deepEqual(await pod.json(), { error: "unauthorized" });
    assert.equal(app.store.shipments.get(podShipment.id)?.status, "BOOKED");

    const refund = await postJson(baseUrl, `/shipments/${refundShipment.id}/fail-refund`, {});
    assert.equal(refund.status, 401);
    assert.deepEqual(await refund.json(), { error: "unauthorized" });
    assert.equal(app.store.shipments.get(refundShipment.id)?.status, "BOOKED");
    assert.equal(app.store.payments.get(refundShipment.paymentId)?.status, "CAPTURED");

    const ledger = await fetch(`${baseUrl}/carriers/${carrier.id}/ledger`);
    assert.equal(ledger.status, 401);
    assert.deepEqual(await ledger.json(), { error: "unauthorized" });

    const payout = await postJson(baseUrl, "/payout-batches/run", { nowUtcMs: Number.MAX_SAFE_INTEGER });
    assert.equal(payout.status, 401);
    assert.deepEqual(await payout.json(), { error: "unauthorized" });
    assert.equal(app.store.ledgerLines.get(payoutLine.id)?.status, "ACCRUED");
    assert.equal(app.store.payoutBatches.size, 0);
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
