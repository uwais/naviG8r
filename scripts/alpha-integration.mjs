#!/usr/bin/env node

import { request } from "./common/request.mjs";

const apiUrl = (process.env.ALPHA_API_URL || "https://navig8r-api-alpha.onrender.com").replace(/\/$/, "");
const expectedRelease = process.env.EXPECTED_RELEASE;

if (!expectedRelease) {
  console.error("EXPECTED_RELEASE is required");
  process.exit(1);
}

const health = await request(apiUrl, "/health");

if (health.ok !== true) throw new Error("Alpha health.ok is not true");
if (health.paymentProvider !== "mock") {
  throw new Error(`Expected mock payment provider, got ${health.paymentProvider}`);
}
if (health.release !== expectedRelease) {
  throw new Error(`Expected API release ${expectedRelease}, got ${health.release}`);
}

const phone = process.env.ALPHA_TEST_PHONE || "9876543210";

const start = await request(apiUrl, "/v1/auth/otp/start", {
  method: "POST",
  body: JSON.stringify({ phone }),
});

if (!start.challengeId) throw new Error("OTP start did not return challengeId");
if (!start.debugCode) throw new Error("Alpha OTP_DEBUG did not return debugCode");

const verify = await request(apiUrl, "/v1/auth/otp/verify", {
  method: "POST",
  body: JSON.stringify({
    challengeId: start.challengeId,
    phone,
    code: start.debugCode,
  }),
});

if (!verify.accessToken) throw new Error("OTP verification did not return accessToken");

const me = await request(apiUrl, "/v1/pilot/me", {
  headers: {
    authorization: `Bearer ${verify.accessToken}`,
  },
});

if (!me || typeof me !== "object") throw new Error("pilot/me returned invalid response");

console.log("Alpha integration smoke test passed.");
