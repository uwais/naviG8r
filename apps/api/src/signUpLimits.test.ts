import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";

const DRIVER_SIGN_UP = "/v1/pilot/driver/register",
  SHIPPER_SIGN_UP = "/v1/pilot/customer/register",
  TEAM_MEMBER_SIGN_UP = "/v1/pilot/customer/users/register";

const driverSignUp = (phone: string, extra: Record<string, unknown> = {}) => ({
  fullName: "Synthetic Driver", phone, orgDisplayName: "Synthetic Driver Co",
  vehicleRegistrationNumber: "KA05MN0002", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000, ...extra,
});
const shipperSignUp = (phone: string, extra: Record<string, unknown> = {}) => ({
  fullName: "Synthetic Shipper", phone, orgDisplayName: "Synthetic Shipper Co", ...extra,
});
const teamMemberSignUp = (phone: string, extra: Record<string, unknown> = {}) => ({
  fullName: "Synthetic Member", phone, ...extra,
});

function setTrustProxy(t: TestContext, value: string | undefined) {
  const old = process.env.OTP_TRUST_PROXY;
  if (value === undefined) delete process.env.OTP_TRUST_PROXY;
  else process.env.OTP_TRUST_PROXY = value;
  t.after(() => old === undefined ? delete process.env.OTP_TRUST_PROXY : process.env.OTP_TRUST_PROXY = old);
}

test("sign-up routes have no per-IP limit when the proxy is not trusted", async (t) => {
  setTrustProxy(t, undefined);
  const f = await httpFixture(t);
  for (let attempt = 0; attempt < 31; attempt++) {
    const phone = String(9100000000 + attempt);
    const signedUp = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp(phone));
    assert.equal(signedUp.status, 201, `attempt ${attempt + 1}`);
  }
});

test("sign-up routes share a per-IP limit of 30 in 10 minutes when the proxy is trusted", async (t) => {
  setTrustProxy(t, "1");
  const f = await httpFixture(t);
  for (let attempt = 0; attempt < 30; attempt++) {
    const phone = String(9100000000 + attempt);
    const signedUp = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp(phone));
    assert.equal(signedUp.status, 201, `attempt ${attempt + 1}`);
  }
  for (const [path, body] of [
    [TEAM_MEMBER_SIGN_UP, teamMemberSignUp("9100000100")],
    [SHIPPER_SIGN_UP, shipperSignUp("9100000101")],
    [DRIVER_SIGN_UP, driverSignUp("9100000102")],
  ] as const) {
    const limited = await f.request(path, "POST", body);
    assert.deepEqual([limited.status, limited.body.error], [429, "rate_limited"], path);
  }
  assert.equal([...f.store.users.values()].some((user) => user.phone === "9100000100"), false);
});

test("a sign-up refused for its IP does not use one of the phone's tries", async (t) => {
  setTrustProxy(t, "1");
  const f = await httpFixture(t);
  const fromFirstAddress = { "x-forwarded-for": "198.51.100.1" }, fromSecondAddress = { "x-forwarded-for": "198.51.100.2" };
  for (let attempt = 0; attempt < 30; attempt++) {
    const signedUp = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp(String(9100000400 + attempt)), undefined, fromFirstAddress);
    assert.equal(signedUp.status, 201, `attempt ${attempt + 1}`);
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    const limited = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp("9100000450"), undefined, fromFirstAddress);
    assert.equal(limited.status, 429, `attempt ${attempt + 1}`);
  }
  const signedUp = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp("9100000450"), undefined, fromSecondAddress);
  assert.equal(signedUp.status, 201);
});

test("sign-up routes share a per-phone limit of 5 in an hour", async (t) => {
  const f = await httpFixture(t);
  const phone = "9100000200";
  assert.equal((await f.request(SHIPPER_SIGN_UP, "POST", shipperSignUp(phone))).status, 201);
  for (let attempt = 2; attempt <= 5; attempt++) {
    const repeated = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp(`+91 ${phone}`));
    assert.equal(repeated.status, 409, `attempt ${attempt}`);
  }
  const limited = await f.request(DRIVER_SIGN_UP, "POST", driverSignUp(phone));
  assert.deepEqual([limited.status, limited.body.error], [429, "rate_limited"]);
  const otherPhone = await f.request(TEAM_MEMBER_SIGN_UP, "POST", teamMemberSignUp("9100000201"));
  assert.equal(otherPhone.status, 201);
});

test("sign-up text fields over their length cap are refused with 400 and nothing is saved", async (t) => {
  const f = await httpFixture(t);
  const longName = "N".repeat(101), longPhone = "9 - 1 - 0 - 0 - 0 - 0 - 0 - 3 - 0 - 8";
  const cases = [
    [DRIVER_SIGN_UP, driverSignUp("9100000300", { fullName: longName }), "invalid_fullName"],
    [DRIVER_SIGN_UP, driverSignUp("9100000301", { orgDisplayName: longName }), "invalid_orgDisplayName"],
    [DRIVER_SIGN_UP, driverSignUp(longPhone), "invalid_phone"],
    [SHIPPER_SIGN_UP, shipperSignUp("9100000302", { fullName: longName }), "invalid_fullName"],
    [SHIPPER_SIGN_UP, shipperSignUp("9100000303", { orgDisplayName: longName }), "invalid_orgDisplayName"],
    [SHIPPER_SIGN_UP, shipperSignUp(longPhone), "invalid_phone"],
    [TEAM_MEMBER_SIGN_UP, teamMemberSignUp("9100000304", { fullName: longName }), "invalid_fullName"],
    [TEAM_MEMBER_SIGN_UP, teamMemberSignUp(longPhone), "invalid_phone"],
  ] as const;
  const usersBefore = f.store.users.size;
  for (const [path, body, error] of cases) {
    const refused = await f.request(path, "POST", body);
    assert.deepEqual([refused.status, refused.body.error], [400, error], `${path} ${error}`);
  }
  assert.equal(f.store.users.size, usersBefore);

  const atCap = "N".repeat(100);
  assert.equal((await f.request(SHIPPER_SIGN_UP, "POST", shipperSignUp("9100000305", { fullName: atCap, orgDisplayName: atCap }))).status, 201);
  assert.equal((await f.request(DRIVER_SIGN_UP, "POST", driverSignUp("+91 91000 00306", { fullName: atCap, orgDisplayName: atCap }))).status, 201);
});
