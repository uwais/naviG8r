#!/usr/bin/env node

const apiUrl = (process.env.BETA_API_URL || "https://navig8r-api-beta.onrender.com").replace(/\/$/, "");
const expectedRelease = process.env.EXPECTED_RELEASE;

if (!expectedRelease) {
  console.error("EXPECTED_RELEASE is required");
  process.exit(1);
}

const response = await fetch(`${apiUrl}/health`);
const body = await response.json();

if (!response.ok) {
  throw new Error(`Beta health returned ${response.status}`);
}
if (body.ok !== true) {
  throw new Error("Beta health.ok is not true");
}
if (body.paymentProvider !== "razorpay") {
  throw new Error(`Expected Razorpay in Beta, got ${body.paymentProvider}`);
}
if (body.release !== expectedRelease) {
  throw new Error(`Expected Beta release ${expectedRelease}, got ${body.release}`);
}

console.log("Beta smoke test passed.");
