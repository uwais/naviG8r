import { httpFixture } from "../test/httpFixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { createHash } from "node:crypto";
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

test("production FCM rejects FILE persistence unless explicitly enabled", async (t) => {
  const previous = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    PERSISTENCE: process.env.PERSISTENCE,
    PUSH_ALLOW_FILE_PRODUCTION: process.env.PUSH_ALLOW_FILE_PRODUCTION,
    PUSH_DEVICE_REGISTRATION_ENABLED: process.env.PUSH_DEVICE_REGISTRATION_ENABLED,
    PUSH_SENDER_ENABLED: process.env.PUSH_SENDER_ENABLED,
    FCM_SERVICE_ACCOUNT_JSON: process.env.FCM_SERVICE_ACCOUNT_JSON,
  };
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  process.env.NODE_ENV = "production";
  process.env.PERSISTENCE = "FILE";
  process.env.PUSH_SENDER_ENABLED = "1";
  process.env.FCM_SERVICE_ACCOUNT_JSON = "{}";
  delete process.env.PUSH_ALLOW_FILE_PRODUCTION;
  delete process.env.PUSH_DEVICE_REGISTRATION_ENABLED;

  await assert.rejects(
    createApp({ dataFilePath: `/tmp/navig8r-fcm-production-${Date.now()}.json` }),
    /production_fcm_requires_db_persistence/,
  );
});

test("production FCM allows FILE persistence with explicit opt-in", async (t) => {
  const previous = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    PERSISTENCE: process.env.PERSISTENCE,
    PUSH_ALLOW_FILE_PRODUCTION: process.env.PUSH_ALLOW_FILE_PRODUCTION,
    PUSH_DEVICE_REGISTRATION_ENABLED: process.env.PUSH_DEVICE_REGISTRATION_ENABLED,
    PUSH_SENDER_ENABLED: process.env.PUSH_SENDER_ENABLED,
    FCM_SERVICE_ACCOUNT_JSON: process.env.FCM_SERVICE_ACCOUNT_JSON,
  };
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  process.env.NODE_ENV = "production";
  process.env.PERSISTENCE = "FILE";
  process.env.PUSH_ALLOW_FILE_PRODUCTION = "1";
  process.env.PUSH_SENDER_ENABLED = "1";
  process.env.FCM_SERVICE_ACCOUNT_JSON = "{}";
  delete process.env.PUSH_DEVICE_REGISTRATION_ENABLED;

  const app = await createApp({ dataFilePath: `/tmp/navig8r-fcm-production-opt-in-${Date.now()}.json` });
  assert.ok(app.store);
  assert.equal(app.dataFilePath?.endsWith(".json"), true);
});

test("read-only requests do not snapshot the entire Store", async (t) => {
  const f = await httpFixture(t);
  Object.assign(f.store as unknown as Record<string, unknown>, {
    nonCloneableTestMarker: () => undefined,
  });

  const health = await f.request("/health");
  assert.equal(health.status, 200);
  assert.equal(health.body.ok, true);
});

test("conversation message reads retain Store snapshot protection", async (t) => {
  const f = await httpFixture(t);
  const booked = await f.book();
  assert.equal(booked.status, 201);
  const shipmentId = booked.body.shipment.id as string;
  Object.assign(f.store as unknown as Record<string, unknown>, {
    nonCloneableTestMarker: () => undefined,
  });

  const result = await f.request(`/v1/shipments/${shipmentId}/conversation/messages`, "GET", undefined, f.tokens.shipperA);
  assert.equal(result.status, 500);
});

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

test("POST /v1/pilot/carrier/payout-setup replies 400 with the IFSC sentence the app shows", async t => {
  const f = await httpFixture(t);
  const refusal = await f.request("/v1/pilot/carrier/payout-setup", "POST", { orgId: f.carrierA.org.id, accountHolderName: "Ravi Kumar", ifsc: "HDFC1001234", accountNumber: "1234567890" }, f.tokens.carrierA);
  assert.equal(refusal.status, 400);
  assert.equal(refusal.body.error, "invalid_payout_profile");
  assert.equal(refusal.body.detail, "IFSC must be 11 characters: four letters for the bank, then 0, then six letters or digits for the branch. Example: HDFC0000123.");
});

// httpFixture runs in BOOKKEEPING mode, as alpha and beta do; production gives this same sentence in RAZORPAYX mode.
test("POST /v1/pilot/carrier/payout-setup refuses a blank account number on a test server with the sentence production gives", async t => {
  const f = await httpFixture(t);
  for (const accountNumber of [undefined, "", "   "]) {
    const refusal = await f.request("/v1/pilot/carrier/payout-setup", "POST", { orgId: f.carrierA.org.id, accountHolderName: "Ravi Kumar", ifsc: "HDFC0001234", accountNumber }, f.tokens.carrierA);
    assert.equal(refusal.status, 400, `expected ${JSON.stringify(accountNumber)} to be refused`);
    assert.equal(refusal.body.error, "invalid_payout_profile");
    assert.equal(refusal.body.detail, "Bank account number is required.");
    assert.equal(refusal.body.field, "accountNumber");
  }
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
    assert.ok(html.includes("<h1>Operations workspace</h1>"));
    assert.ok(html.includes("pending-release"));
    assert.ok(html.includes("/ops/compliance/pending"));
  });
});

test("GET /ops/beta serves the redesigned ops page beside the unchanged current one", async (t) => {
  const prev = { DATA_FILE: process.env.DATA_FILE };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
  });

  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;

  await withApp(t, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/ops/beta`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("x-frame-options"), "DENY");
    const policy = res.headers.get("content-security-policy") ?? "";
    assert.match(policy, /frame-ancestors 'none'/);
    const html = await res.text();
    // The policy must carry the fingerprints of the exact script and stylesheet served, or the page stops working.
    const sha256 = (text: string) => `'sha256-${createHash("sha256").update(text).digest("base64")}'`;
    const inline = (tag: string) => html.split(`<${tag}>`)[1]?.split(`</${tag}>`)[0] ?? "";
    assert.ok(policy.includes(`script-src ${sha256(inline("script"))}`), "the policy allows the page's own script");
    assert.ok(policy.includes(`style-src ${sha256(inline("style"))}`), "the policy allows the page's own stylesheet");
    assert.ok(html.includes("<title>NaviG8r operations (beta)</title>"));
    assert.ok(html.includes("/ops/compliance/pending") && html.includes("/ops/shipments/pending-release"));
    assert.ok(!html.includes("prefers-color-scheme"), "light mode only, never switched by the system setting");
    for (const address of html.match(/https?:\/\/[^"' )]+/g) ?? []) {
      // The one link out is the government e-way bill portal, matched whole so no other address passes.
      assert.match(address, /^https:\/\/fonts\.(googleapis|gstatic)\.com(\/|$)|^http:\/\/www\.w3\.org\/2000\/svg$|^https:\/\/ewaybillgst\.gov\.in$/, `unexpected outside address ${address}`);
    }

    const current = await (await fetch(`${baseUrl}/ops`)).text();
    assert.ok(current.includes("<h1>Operations workspace</h1>"));
    assert.ok(!current.includes("/ops/beta"), "the current page does not link to or depend on the beta");
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

test("POST /v1/payments/razorpay/webhook refuses a body over 256 KB with 413", async (t) => {
  process.env.DATA_FILE = `/tmp/navig8r-http-test-${Date.now()}-${Math.random()}.json`;
  const previousSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  process.env.RAZORPAY_WEBHOOK_SECRET = "webhook_test_secret";
  t.after(() => {
    if (previousSecret === undefined) delete process.env.RAZORPAY_WEBHOOK_SECRET;
    else process.env.RAZORPAY_WEBHOOK_SECRET = previousSecret;
  });

  await withApp(t, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/v1/payments/razorpay/webhook`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-razorpay-signature": "0".repeat(64) },
      body: JSON.stringify({ event: "payment.authorized", padding: "a".repeat(300 * 1024) }),
    });
    assert.equal(res.status, 413);
    assert.deepEqual(await res.json(), { error: "payload_too_large" });
  });
});
