import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";
import { FixedWindowRateLimiter } from "./http/rateLimit.ts";

const DRIVER = "/v1/pilot/driver/register",
  CUSTOMER = "/v1/pilot/customer/register",
  CUSTOMER_USER = "/v1/pilot/customer/users/register";

function driverBody(phone: string, extra: Record<string, unknown> = {}) {
  return { fullName: "Sign-up Driver", phone, orgDisplayName: "Sign-up Carrier", vehicleRegistrationNumber: "TEST-S", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000, ...extra };
}

test("sign-up routes share one limit per connecting IP", async (t) => {
  const f = await httpFixture(t);
  for (let index = 0; index < 30; index++) {
    const phone = `70000${String(index).padStart(5, "0")}`;
    const path = [DRIVER, CUSTOMER, CUSTOMER_USER][index % 3]!;
    const body = path === DRIVER ? driverBody(phone) : { fullName: "Sign-up Person", phone, orgDisplayName: "Sign-up Company" };
    const created = await f.request(path, "POST", body);
    assert.equal(created.status, 201, `${path} ${phone}`);
  }
  const limited = await f.request(CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: "7100000000" });
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "sign_up_rate_limited");
  assert.equal([...f.store.users.values()].some((user) => user.phone === "7100000000"), false);
});

test("sign-up routes limit repeated tries for one phone number", async (t) => {
  const f = await httpFixture(t);
  const phone = f.shipperA.user.phone;
  for (let attempt = 1; attempt <= 5; attempt++) {
    const answer = await f.request(attempt % 2 ? CUSTOMER : CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: attempt === 3 ? `+91 ${phone}` : phone, orgDisplayName: "Sign-up Company" });
    assert.equal(answer.body.error, "phone_already_registered");
  }
  const limited = await f.request(DRIVER, "POST", driverBody(phone));
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "sign_up_rate_limited");
  const otherPhone = await f.request(CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: "7200000000" });
  assert.equal(otherPhone.status, 201);
});

test("sign-up text fields over their length cap are refused", async (t) => {
  const f = await httpFixture(t);
  const longName = "N".repeat(101), longPhone = `7300000000${" ".repeat(11)}x`;
  const refusals: Array<[string, Record<string, unknown>, string]> = [
    [DRIVER, driverBody("7300000001", { fullName: longName }), "invalid_fullName"],
    [DRIVER, driverBody("7300000002", { orgDisplayName: longName }), "invalid_orgDisplayName"],
    [DRIVER, driverBody(longPhone), "invalid_phone"],
    [CUSTOMER, { fullName: longName, phone: "7300000003", orgDisplayName: "Sign-up Company" }, "invalid_fullName"],
    [CUSTOMER, { fullName: "Sign-up Person", phone: "7300000004", orgDisplayName: longName }, "invalid_orgDisplayName"],
    [CUSTOMER, { fullName: "Sign-up Person", phone: longPhone, orgDisplayName: "Sign-up Company" }, "invalid_phone"],
    [CUSTOMER_USER, { fullName: longName, phone: "7300000005" }, "invalid_fullName"],
    [CUSTOMER_USER, { fullName: "Sign-up Person", phone: longPhone }, "invalid_phone"],
  ];
  const usersBefore = f.store.users.size;
  for (const [path, body, error] of refusals) {
    const refused = await f.request(path, "POST", body);
    assert.equal(refused.status, 400, `${path} ${error}`);
    assert.equal(refused.body.error, error, path);
    assert.equal(typeof refused.body.detail, "string", path);
  }
  assert.equal(f.store.users.size, usersBefore);
  const atCap = await f.request(CUSTOMER, "POST", { fullName: "N".repeat(100), phone: "7300000006", orgDisplayName: "C".repeat(100) });
  assert.equal(atCap.status, 201);
});

test("sign-up keeps a per-phone count only for a valid phone number", async (t) => {
  const f = await httpFixture(t);
  const keys: string[] = [];
  const original = FixedWindowRateLimiter.prototype.consume;
  t.mock.method(FixedWindowRateLimiter.prototype, "consume", function (this: FixedWindowRateLimiter, key: string, ...rest: [number, number, number?]) {
    keys.push(key);
    return original.call(this, key, ...rest);
  });
  const refused = await f.request(CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: "7".repeat(5000) });
  assert.equal(refused.status, 400);
  assert.equal(refused.body.error, "invalid_phone");
  assert.equal(keys.some((key) => key.startsWith("sign-up:phone:")), false);
  const accepted = await f.request(CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: "+91 74000 00000" });
  assert.equal(accepted.status, 201);
  assert.equal(keys.includes("sign-up:phone:7400000000"), true);
});

test("sign-up does not count the phone when the connecting IP is over its limit", async (t) => {
  const f = await httpFixture(t);
  for (let index = 0; index < 30; index++) {
    const created = await f.request(CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: `75000${String(index).padStart(5, "0")}` });
    assert.equal(created.status, 201);
  }
  const keys: string[] = [];
  const original = FixedWindowRateLimiter.prototype.consume;
  t.mock.method(FixedWindowRateLimiter.prototype, "consume", function (this: FixedWindowRateLimiter, key: string, ...rest: [number, number, number?]) {
    keys.push(key);
    return original.call(this, key, ...rest);
  });
  const limited = await f.request(CUSTOMER_USER, "POST", { fullName: "Sign-up Person", phone: "7600000000" });
  assert.equal(limited.status, 429);
  assert.equal(keys.some((key) => key.startsWith("sign-up:phone:")), false);
});
