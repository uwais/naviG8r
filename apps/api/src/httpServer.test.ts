import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import type http from "node:http";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import {
  bookShipment,
  createCarrier,
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

test("POST /shipments/:id/driver-pod requires authenticated user", async (t) => {
  const prev = { DATA_FILE: process.env.DATA_FILE, NODE_ENV: process.env.NODE_ENV };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "test";

  await withApp(t, async (baseUrl) => {
    const res = await postJson(baseUrl, "/shipments/shp_fake/driver-pod", { notes: "ok" });
    assert.equal(res.status, 401);
  });
});

test("GET /ops returns ops portal HTML", async (t) => {
  const prev = { DATA_FILE: process.env.DATA_FILE };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;

  await withApp(t, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/ops`);
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.ok(html.includes("naviG8r Ops"));
    assert.ok(html.includes("pending-release"));
    assert.ok(html.includes("function escHtml"));
    assert.ok(html.includes("escHtml(s.customerOrgName)"));
    assert.equal(html.includes("(s.customerOrgName||\"\")"), false);
  });
});

test("POST /shipments/:id/pod rejects visible non-ops bearer users in production", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    DATA_FILE: process.env.DATA_FILE,
    ENABLE_LEGACY_DEMO_SURFACE: process.env.ENABLE_LEGACY_DEMO_SURFACE,
    NODE_ENV: process.env.NODE_ENV,
    PAYMENT_PROVIDER: process.env.PAYMENT_PROVIDER,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.ENABLE_LEGACY_DEMO_SURFACE = prev.ENABLE_LEGACY_DEMO_SURFACE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.PAYMENT_PROVIDER = prev.PAYMENT_PROVIDER;
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "production";
  delete process.env.ENABLE_LEGACY_DEMO_SURFACE;
  delete process.env.PAYMENT_PROVIDER;

  await withApp(t, async (baseUrl, app) => {
    const customer = registerCustomerOrgAdmin(app.store, {
      fullName: "Buyer",
      phone: "9100000033",
      orgDisplayName: "ACME Buyer",
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
      customerOrgName: customer.org.displayName,
      customerOrg: { id: customer.org.id, displayName: customer.org.displayName },
      weightKg: 100,
      pickupAddress: "A",
      dropAddress: "B",
    });
    const otp = pilotOtpStart(app.store, { phone: customer.user.phone });
    const { accessToken } = pilotOtpVerify(app.store, {
      phone: customer.user.phone,
      challengeId: otp.challengeId,
      code: otp.debugCode ?? app.store.otpChallenges.get(otp.challengeId)!.code,
    });

    const res = await fetch(`${baseUrl}/shipments/${shipment.id}/pod`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${accessToken}` },
      body: "{}",
    });

    assert.equal(res.status, 403);
    assert.equal((await res.json() as { error?: string }).error, "legacy_pod_requires_ops");
    assert.equal(app.store.shipments.get(shipment.id)?.status, "BOOKED");
    assert.equal([...app.store.ledgerLines.values()].filter((line) => line.shipmentId === shipment.id).length, 0);
  });
});
