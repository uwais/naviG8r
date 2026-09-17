import { httpFixture } from "../test/httpFixtures.ts";
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
    assert.equal(users.status, 401);
    assert.deepEqual(await users.json(), { error: "unauthorized" });

    const carriers = await fetch(`${baseUrl}/carriers`);
    assert.equal(carriers.status, 410);

    const detail = await fetch(`${baseUrl}/shipments/shp_123`);
    assert.equal(detail.status, 401);
    assert.deepEqual(await detail.json(), { error: "unauthorized" });

    const shipments = await fetch(`${baseUrl}/shipments`);
    assert.equal(shipments.status, 401);
    assert.deepEqual(await shipments.json(), { error: "unauthorized" });

    const pod = await postJson(baseUrl, "/shipments/shp_123/pod", {});
    assert.equal(pod.status, 410);
    assert.deepEqual(await pod.json(), { error: "legacy_route_retired" });

    const refund = await postJson(baseUrl, "/shipments/shp_123/fail-refund", {});
    assert.equal(refund.status, 401);
    assert.deepEqual(await refund.json(), { error: "unauthorized" });

    const login = await postJson(baseUrl, "/v1/pilot/driver/login", { phone: "9876543210" });
    assert.equal(login.status, 410);
    assert.deepEqual(await login.json(), { error: "legacy_route_retired" });
  });
});

test("legacy demo mutations are retired in every environment", async (t) => {
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
    assert.equal(res.status, 410);
    assert.deepEqual(await res.json(), { error: "legacy_route_retired" });
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

test("POST /v1/pilot/carrier/shipments/:id/accept accepts pending booking with OTP bearer", async t => {
  const f = await httpFixture(t);
  const book = await f.book(); assert.equal(book.status, 201);
  const accepted = await f.request(`/v1/pilot/carrier/shipments/${book.body.shipment.id}/accept`, "POST", {}, f.tokens.carrierA);
  assert.equal(accepted.status, 200); assert.equal(accepted.body.shipment.status, "BOOKED");
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
    assert.ok(html.includes("NaviG8r operations"));
    assert.ok(html.includes("pending-release"));
  });
});

test("GET /workflow returns the shipment/POD workspace shell", async (t) => {
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;

  await withApp(t, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/workflow`);
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.ok(html.includes("<title>NaviG8r shipments</title>"));
    assert.ok(html.includes("const workflowOnly = true"));
    assert.ok(html.includes("Accept POD"));
    assert.ok(html.includes("Admin workspace"));
  });
});

test("CORS preflight allows localhost web clients", async (t) => {
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;

  await withApp(t, async (baseUrl) => {
    const origin = "http://localhost:56901";
    const preflight = await fetch(`${baseUrl}/v1/pilot/customer/register`, {
      method: "OPTIONS",
      headers: {
        origin,
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type,authorization",
      },
    });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get("access-control-allow-origin"), origin);
    assert.ok(preflight.headers.get("access-control-allow-methods")?.includes("POST"));

    const post = await fetch(`${baseUrl}/v1/pilot/customer/register`, {
      method: "POST",
      headers: { origin, "content-type": "application/json" },
      body: JSON.stringify({
        fullName: "Web Test",
        phone: "9812345678",
        orgDisplayName: "CORS Co",
      }),
    });
    assert.equal(post.headers.get("access-control-allow-origin"), origin);
    assert.ok(post.status === 200 || post.status === 201);
  });
});
