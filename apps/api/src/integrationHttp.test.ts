import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { createApp } from "./httpServer.ts";

type AppBundle = Awaited<ReturnType<typeof createApp>>;

const GURGAON = { lat: 28.4595, lng: 77.0266, label: "Gurugram" };
const JAIPUR = { lat: 26.9124, lng: 75.7873, label: "Jaipur" };

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

function testEnv(t: { after(fn: () => void): void }): void {
  const prev = {
    DATA_FILE: process.env.DATA_FILE,
    NODE_ENV: process.env.NODE_ENV,
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
  };
  t.after(() => {
    process.env.DATA_FILE = prev.DATA_FILE;
    process.env.NODE_ENV = prev.NODE_ENV;
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
    process.env.ALLOW_X_USER_ID = prev.ALLOW_X_USER_ID;
  });

  process.env.DATA_FILE = `/tmp/navig8r-integration-http-${Date.now()}-${Math.random()}.json`;
  process.env.NODE_ENV = "test";
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  process.env.ALLOW_X_USER_ID = "1";
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

async function patchJson(
  baseUrl: string,
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return fetch(`${baseUrl}${path}`, {
    method: "PATCH",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

async function customerBearer(baseUrl: string): Promise<{ token: string; orgId: string }> {
  const phone = "9111008800";
  const reg = await postJson(baseUrl, "/v1/pilot/customer/register", {
    fullName: "ERP HTTP Admin",
    phone,
    orgDisplayName: "ERP HTTP Shipper",
  });
  assert.equal(reg.status, 201);
  const regBody = (await reg.json()) as { org: { id: string } };

  const start = await postJson(baseUrl, "/v1/auth/otp/start", { phone });
  assert.equal(start.status, 200);
  const startBody = (await start.json()) as { challengeId: string; debugCode: string };

  const verify = await postJson(baseUrl, "/v1/auth/otp/verify", {
    phone,
    challengeId: startBody.challengeId,
    code: startBody.debugCode,
  });
  assert.equal(verify.status, 200);
  const verifyBody = (await verify.json()) as { accessToken: string };
  return { token: verifyBody.accessToken, orgId: regBody.org.id };
}

async function seedCarrierTrip(baseUrl: string): Promise<{ tripId: string }> {
  const reg = await postJson(baseUrl, "/v1/pilot/driver/register", {
    fullName: "ERP HTTP Carrier",
    phone: "9876548800",
    orgDisplayName: "ERP HTTP Carrier",
    vehicleRegistrationNumber: "HR26AB8800",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  assert.equal(reg.status, 201);
  const onboard = (await reg.json()) as { user: { id: string }; org: { id: string } };

  const tripRes = await postJson(baseUrl, "/v1/pilot/anchor-trips", {
    orgId: onboard.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    origin: GURGAON,
    destination: JAIPUR,
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  }, { "x-user-id": onboard.user.id });
  assert.equal(tripRes.status, 201);
  const tripBody = (await tripRes.json()) as { trip: { id: string } };
  return { tripId: tripBody.trip.id };
}

test("POST /v1/integrations/loads creates and idempotently returns shipment", async (t) => {
  testEnv(t);
  await withApp(t, async (baseUrl) => {
    await seedCarrierTrip(baseUrl);
    const { token, orgId } = await customerBearer(baseUrl);

    const keyRes = await postJson(
      baseUrl,
      `/v1/pilot/customer/integrations/keys?orgId=${orgId}`,
      { scopes: ["loads:read", "loads:write"] },
      { authorization: `Bearer ${token}` },
    );
    assert.equal(keyRes.status, 201);
    const keyBody = (await keyRes.json()) as { token: string };

    await patchJson(
      baseUrl,
      `/v1/pilot/customer/integrations/connection?orgId=${orgId}`,
      { paymentPolicy: "erp_preauthorized" },
      { authorization: `Bearer ${token}` },
    );

    const loadBody = {
      externalLoadId: "ERP-HTTP-001",
      weightKg: 100,
      pickupAddress: "Gurugram warehouse",
      dropAddress: "Jaipur plant",
      pickup: GURGAON,
      drop: JAIPUR,
      metadata: { poNumber: "PO-HTTP-1" },
    };

    const create = await postJson(baseUrl, "/v1/integrations/loads", loadBody, {
      authorization: `Bearer ${keyBody.token}`,
    });
    assert.equal(create.status, 201);
    const created = (await create.json()) as { created: boolean; shipmentId: string; externalLoadId: string };
    assert.equal(created.created, true);
    assert.equal(created.externalLoadId, "ERP-HTTP-001");

    const dup = await postJson(baseUrl, "/v1/integrations/loads", loadBody, {
      authorization: `Bearer ${keyBody.token}`,
    });
    assert.equal(dup.status, 200);
    const dupBody = (await dup.json()) as { created: boolean; shipmentId: string };
    assert.equal(dupBody.created, false);
    assert.equal(dupBody.shipmentId, created.shipmentId);

    const lookup = await fetch(
      `${baseUrl}/v1/integrations/loads?externalLoadId=ERP-HTTP-001`,
      { headers: { authorization: `Bearer ${keyBody.token}` } },
    );
    assert.equal(lookup.status, 200);
    const loads = (await lookup.json()) as { loads: unknown[] };
    assert.equal(loads.loads.length, 1);
  });
});

test("GET /v1/pilot/customer/integrations requires CUSTOMER_ADMIN bearer", async (t) => {
  testEnv(t);
  await withApp(t, async (baseUrl) => {
    const { token, orgId } = await customerBearer(baseUrl);

    const summary = await fetch(`${baseUrl}/v1/pilot/customer/integrations?orgId=${orgId}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(summary.status, 200);
    const body = (await summary.json()) as { connection: { id: string }; apiKeys: unknown[] };
    assert.ok(body.connection.id);
    assert.ok(Array.isArray(body.apiKeys));

    const noAuth = await fetch(`${baseUrl}/v1/pilot/customer/integrations?orgId=${orgId}`);
    assert.equal(noAuth.status, 401);
  });
});

test("POST /v1/integrations/loads without token returns 401", async (t) => {
  testEnv(t);
  await withApp(t, async (baseUrl) => {
    const res = await postJson(baseUrl, "/v1/integrations/loads", {
      externalLoadId: "X",
      weightKg: 1,
      pickupAddress: "A",
      dropAddress: "B",
    });
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "integration_unauthorized" });
  });
});
