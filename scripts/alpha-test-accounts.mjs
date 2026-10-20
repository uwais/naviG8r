#!/usr/bin/env node
// Signs up the shared test phones in alpha-test-accounts.json through alpha's own sign-up routes,
// the same ones the app uses, so nothing already on alpha is replaced. Safe to run repeatedly:
// an account that already exists is left as it is.
//
// Needs OTP_DEBUG on the target server, which returns the login code instead of texting it.

import { appendFileSync, readFileSync } from "node:fs";
import { request } from "./common/request.mjs";

const apiUrl = (process.env.ALPHA_API_URL || "https://navig8r-api-alpha.onrender.com").replace(/\/$/, "");
const accounts = JSON.parse(readFileSync(new URL("./alpha-test-accounts.json", import.meta.url), "utf8"));
const { shipper, ownerDriver, driver } = accounts;

async function post(path, body, token) {
  return request(apiUrl, path, {
    method: "POST",
    body: JSON.stringify(body),
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
}

// Returns "created" or "already there"; any other failure stops the script.
async function createUnlessAlreadyExists(path, body, token, alreadyExistsError) {
  try {
    await post(path, body, token);
    return "created";
  } catch (error) {
    if (error.message.includes(alreadyExistsError)) return "already there";
    throw error;
  }
}

async function logIn(phone) {
  const start = await post("/v1/auth/otp/start", { phone });
  if (!start.debugCode) throw new Error("No login code returned; is OTP_DEBUG on for this server?");
  const verify = await post("/v1/auth/otp/verify", { challengeId: start.challengeId, phone, code: start.debugCode });
  return verify.accessToken;
}

// Guards against ALPHA_API_URL pointing at beta or production: these phones look like real numbers.
const health = await request(apiUrl, "/health");
if (health.paymentProvider !== "mock") throw new Error(`Refusing to sign up test phones on ${apiUrl}: payments are not mock`);

const shipperResult = await createUnlessAlreadyExists("/v1/pilot/customer/register", shipper, null, "phone_already_registered");
const ownerDriverResult = await createUnlessAlreadyExists("/v1/pilot/driver/register", ownerDriver, null, "phone_already_registered");
const driverSignUpResult = await createUnlessAlreadyExists(
  "/v1/pilot/customer/users/register",
  { fullName: driver.fullName, phone: driver.phone },
  null,
  "phone_already_registered",
);

const ownerToken = await logIn(ownerDriver.phone);
const ownerProfile = await request(apiUrl, "/v1/pilot/me", { headers: { authorization: `Bearer ${ownerToken}` } });
const carrierOrg = ownerProfile.organizations.find((org) => ["CARRIER_SOLO", "CARRIER_FLEET", "CARRIER_LEGACY"].includes(org.kind));
if (!carrierOrg) throw new Error(`Owner ${ownerDriver.phone} has no carrier organisation`);

const driverInviteResult = await createUnlessAlreadyExists(
  "/v1/pilot/carrier/drivers/invite",
  {
    orgId: carrierOrg.id,
    phone: driver.phone,
    role: "DRIVER",
    vehicleRegistrationNumber: driver.vehicleRegistrationNumber,
    vehicleClass: driver.vehicleClass,
    vehicleCapacityKg: driver.vehicleCapacityKg,
  },
  ownerToken,
  "membership_already_exists",
);

const summary = [
  "## Alpha test accounts",
  "",
  "Log in with any of these phones; alpha shows the login code on screen.",
  "",
  "| Phone | Meant to be | This run |",
  "|---|---|---|",
  `| ${shipper.phone} | Shipper admin, ${shipper.orgDisplayName} | ${shipperResult} |`,
  `| ${ownerDriver.phone} | Owner-driver, ${ownerDriver.orgDisplayName} | ${ownerDriverResult} |`,
  `| ${driver.phone} | Driver in ${ownerDriver.orgDisplayName} | sign-up ${driverSignUpResult}, invite ${driverInviteResult} |`,
  "",
].join("\n");

console.log(summary);
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
