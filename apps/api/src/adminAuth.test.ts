import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createApp } from "./httpServer.ts";
import { bookShipment, publishAnchorTripAsPilotDriver, registerSoloOwnerOperatorDriver } from "./services.ts";

async function request(baseUrl: string, path: string, method: "GET" | "POST", token?: string): Promise<Response> {
  return fetch(`${baseUrl}${path}`, {
    method,
    headers: token ? { authorization: `Bearer ${token}` } : undefined,
  });
}

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}

test("sensitive read/admin endpoints require bearer auth", async (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
    DATA_FILE: process.env.DATA_FILE,
    ALLOW_X_USER_ID: process.env.ALLOW_X_USER_ID,
  };
  t.after(() => {
    restoreEnv("AUTH_SECRET", prev.AUTH_SECRET);
    restoreEnv("OTP_DEBUG", prev.OTP_DEBUG);
    restoreEnv("OTP_FIXED_CODE", prev.OTP_FIXED_CODE);
    restoreEnv("DATA_FILE", prev.DATA_FILE);
    restoreEnv("ALLOW_X_USER_ID", prev.ALLOW_X_USER_ID);
  });

  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  delete process.env.ALLOW_X_USER_ID;

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-admin-auth-"));
  process.env.DATA_FILE = path.join(tmpDir, "store.json");
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));

  const { server, store } = createApp();
  t.after(() => server.close());

  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543210",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB1234",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: onboard.user.id,
    orgId: onboard.org.id,
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
  const start = pilotOtpStart(store, { phone: onboard.user.phone });
  const verified = pilotOtpVerify(store, {
    phone: onboard.user.phone,
    challengeId: start.challengeId,
    code: "123456",
  });

  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address === "object");
  const baseUrl = `http://127.0.0.1:${address.port}`;

  const protectedRoutes: Array<{ method: "GET" | "POST"; path: string }> = [
    { method: "GET", path: "/v1/users" },
    { method: "GET", path: "/v1/orgs" },
    { method: "GET", path: "/admin" },
    { method: "GET", path: "/shipments" },
    { method: "GET", path: `/shipments/${shipment.id}` },
    { method: "POST", path: `/shipments/${shipment.id}/pod` },
    { method: "POST", path: `/shipments/${shipment.id}/fail-refund` },
    { method: "GET", path: `/carriers/${onboard.org.id}/ledger` },
    { method: "GET", path: "/payout-batches" },
    { method: "POST", path: "/payout-batches/run" },
  ];

  for (const route of protectedRoutes) {
    const unauthenticated = await request(baseUrl, route.path, route.method);
    assert.equal(unauthenticated.status, 400, `${route.method} ${route.path} should reject missing bearer token`);
    assert.deepEqual(await unauthenticated.json(), { error: "unauthorized" });

    const authenticated = await request(baseUrl, route.path, route.method, verified.accessToken);
    assert.equal(authenticated.status, 200, `${route.method} ${route.path} should allow bearer token`);
  }
});
