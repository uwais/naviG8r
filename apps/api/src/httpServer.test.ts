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

test("POST /v1/pilot/carrier/shipments/:id/accept accepts pending booking", async (t) => {
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
  process.env.NODE_ENV = "test";
  process.env.ALLOW_X_USER_ID = "1";

  async function authedPost(baseUrl: string, path: string, userId: string, body: unknown): Promise<Response> {
    return fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-user-id": userId },
      body: JSON.stringify(body),
    });
  }

  await withApp(t, async (baseUrl) => {
    const reg = await postJson(baseUrl, "/v1/pilot/driver/register", {
      fullName: "Ravi Kumar",
      phone: "9876543210",
      orgDisplayName: "Ravi Transport",
      vehicleRegistrationNumber: "HR26AB1234",
      vehicleClass: "MEDIUM",
      vehicleCapacityKg: 5000,
    });
    assert.equal(reg.status, 201);
    const onboard = (await reg.json()) as { user: { id: string }; org: { id: string } };
    const userId = onboard.user.id;

    const tripRes = await authedPost(baseUrl, "/v1/pilot/anchor-trips", userId, {
      orgId: onboard.org.id,
      originCity: "Gurugram",
      destCity: "Jaipur",
      windowStart: "2026-04-24T00:00:00+05:30",
      windowEnd: "2026-04-25T23:59:59+05:30",
      vehicleClass: "MEDIUM",
      capacityKg: 1000,
    });
    assert.equal(tripRes.status, 201);
    const tripBody = (await tripRes.json()) as { trip: { id: string } };

    const book = await postJson(baseUrl, "/shipments/book", {
      anchorTripId: tripBody.trip.id,
      customerOrgName: "ACME Manufacturing",
      weightKg: 200,
      pickupAddress: "Sector 44, Gurugram",
      dropAddress: "Sitapura, Jaipur",
    });
    assert.equal(book.status, 201);
    const shipment = (await book.json()) as { shipment: { id: string; status: string } };
    assert.equal(shipment.shipment.status, "PENDING_CARRIER_ACCEPT");

    const accept = await authedPost(
      baseUrl,
      `/v1/pilot/carrier/shipments/${shipment.shipment.id}/accept`,
      userId,
      {},
    );
    const acceptText = await accept.text();
    assert.equal(accept.status, 200, acceptText);
    const accepted = JSON.parse(acceptText) as { shipment: { status: string } };
    assert.equal(accepted.shipment.status, "BOOKED");
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
  });
});
