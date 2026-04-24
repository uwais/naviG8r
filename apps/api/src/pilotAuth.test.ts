import assert from "node:assert/strict";
import test from "node:test";
import { pilotOtpStart, pilotOtpVerify, verifyBearer } from "./auth.ts";
import { createStore } from "./store.ts";
import { publishAnchorTripAsPilotDriver, registerSoloOwnerOperatorDriver } from "./services.ts";

test("OTP + bearer auth: verify issues token usable for protected pilot routes", (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });

  process.env.AUTH_SECRET = process.env.AUTH_SECRET ?? "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543210",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB1234",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });

  const start = pilotOtpStart(store, { phone: onboard.user.phone });
  assert.ok(start.challengeId);
  assert.equal(start.debugCode, "123456");

  const verified = pilotOtpVerify(store, {
    phone: onboard.user.phone,
    challengeId: start.challengeId,
    code: "123456",
  });
  assert.ok(verified.accessToken);

  const authed = verifyBearer(store, verified.accessToken);
  assert.equal(authed.userId, onboard.user.id);

  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: authed.userId,
    orgId: onboard.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  assert.equal(trip.carrierId, onboard.org.id);
});
