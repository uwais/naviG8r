import { once } from "node:events";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/httpServer.ts";
import { registerCustomerOrgAdmin, registerSoloOwnerOperatorDriver, publishAnchorTrip } from "../src/services.ts";
import { internalUser } from "./fixtures.ts";

export async function httpFixture(t: TestContext) {
  const dir = await mkdtemp(join(tmpdir(), "rbac-http-"));
  process.env.DATA_FILE = join(dir, "synthetic.json");
  process.env.PERSISTENCE = "FILE";
  process.env.PAYMENT_PROVIDER = "MOCK";
  process.env.PAYOUTS_MODE = "BOOKKEEPING";
  process.env.AUTH_SECRET = "synthetic-test-signing-value-only";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  const app = await createApp();
  app.server.listen(0, "127.0.0.1"); await once(app.server, "listening");
  const address = app.server.address(); assert.ok(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;
  t.after(async () => { app.server.closeAllConnections(); await new Promise<void>(r => app.server.close(() => r())); await rm(dir, { recursive: true, force: true }); });
  const shipperA = registerCustomerOrgAdmin(app.store, { fullName: "Synthetic Shipper A", phone: "8000000001", orgDisplayName: "Synthetic Shipper A" });
  const shipperB = registerCustomerOrgAdmin(app.store, { fullName: "Synthetic Shipper B", phone: "8000000002", orgDisplayName: "Synthetic Shipper B" });
  const carrierA = registerSoloOwnerOperatorDriver(app.store, { fullName: "Synthetic Carrier A", phone: "8000000003", orgDisplayName: "Synthetic Carrier A", vehicleRegistrationNumber: "TEST-A", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const carrierB = registerSoloOwnerOperatorDriver(app.store, { fullName: "Synthetic Carrier B", phone: "8000000004", orgDisplayName: "Synthetic Carrier B", vehicleRegistrationNumber: "TEST-B", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  for (const c of [carrierA, carrierB]) app.store.organizations.set(c.org.id, { ...c.org, kycStatus: "APPROVED" });
  const ops = internalUser(app.store, "OPS"), finance = internalUser(app.store, "FINANCE"), admin = internalUser(app.store, "ADMIN");
  const trip = publishAnchorTrip(app.store, { carrierId: carrierA.org.id, originCity: "A", destCity: "B", windowStart: "2026-09-16", windowEnd: "2026-09-17", vehicleClass: "MEDIUM", capacityKg: 1000 });
  async function request(path: string, method = "GET", body?: unknown, token?: string, headers: Record<string, string> = {}) {
    const response = await fetch(base + path, { method, headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    const out = await response.json(); return { status: response.status, body: out };
  }
  async function login(phone: string) {
    const start = await request("/v1/auth/otp/start", "POST", { phone }); assert.equal(start.status, 200);
    const verified = await request("/v1/auth/otp/verify", "POST", { phone, challengeId: start.body.challengeId, code: start.body.debugCode }); assert.equal(verified.status, 200);
    return verified.body.accessToken as string;
  }
  const tokens = { shipperA: await login(shipperA.user.phone), shipperB: await login(shipperB.user.phone), carrierA: await login(carrierA.user.phone), carrierB: await login(carrierB.user.phone), ops: await login(ops.user.phone), finance: await login(finance.user.phone), admin: await login(admin.user.phone) };
  async function book(token = tokens.shipperA, extra = {}) { return request("/shipments/book", "POST", { anchorTripId: trip.id, customerOrgName: "ignored", weightKg: 10, pickupAddress: "Synthetic A", dropAddress: "Synthetic B", ...extra }, token); }
  return { ...app, dir, base, request, login, tokens, shipperA, shipperB, carrierA, carrierB, ops, finance, admin, trip, book };
}
