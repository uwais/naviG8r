import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import {
  createOtpDependencies,
  pilotOtpStart,
  pilotOtpVerify,
} from "./auth.ts";
import { createStore } from "./store.ts";
import { registerCustomerOrgAdmin } from "./services.ts";

function fixture(t: TestContext, debug = true) {
  const previous = process.env.AUTH_SECRET;
  process.env.AUTH_SECRET = "synthetic-otp-unit-signing-only";
  t.after(() => {
    if (previous === undefined) delete process.env.AUTH_SECRET;
    else process.env.AUTH_SECRET = previous;
  });
  const store = createStore();
  const { user } = registerCustomerOrgAdmin(store, {
    fullName: "OTP Test",
    phone: "8000000042",
    orgDisplayName: "OTP Test",
  });
  let now = Date.now(),
    draws = 0;
  const otp = createOtpDependencies({
    env: { OTP_DEBUG: debug ? "1" : "0" },
    now: () => now,
    generateCode: () => {
      draws++;
      return "000042";
    },
  });
  const start = (phone = user.phone) => pilotOtpStart(store, { phone }, otp);
  const verify = (challengeId: string, code = "000042", phone = user.phone) =>
    pilotOtpVerify(store, { phone, challengeId, code }, otp);
  return {
    store,
    user,
    otp,
    start,
    verify,
    setNow: (value: number) => {
      now = value;
    },
    draws: () => draws,
  };
}

test("OTP configuration defaults, explicit overrides, and invalid values", () => {
  const now = () => 1_800_000_000_000;
  assert.equal(createOtpDependencies({ env: {}, now }).ttlMs, 600_000);
  assert.equal(
    createOtpDependencies({ env: { OTP_TTL_MS: "5000" }, now }).ttlMs,
    5000,
  );
  for (const value of [
    "0",
    "-1",
    "1.5",
    "",
    " ",
    "NaN",
    "Infinity",
    "no",
    "1e100",
    "8640000000000000",
  ]) {
    assert.throws(
      () => createOtpDependencies({ env: { OTP_TTL_MS: value }, now }),
      /OTP_TTL_MS_invalid/,
      value,
    );
  }
  const env = { OTP_DEBUG: "1", OTP_TTL_MS: "5000" };
  const otp = createOtpDependencies({ env, now });
  env.OTP_DEBUG = "0";
  env.OTP_TTL_MS = "0";
  assert.equal(otp.debug, true);
  assert.equal(otp.ttlMs, 5000);
});

test("debug only controls exposure; generated leading zeroes are verified", (t) => {
  for (const debug of [false, true]) {
    const f = fixture(t, debug);
    const result = f.start();
    assert.equal(f.draws(), 1);
    assert.equal(Object.hasOwn(result, "debugCode"), debug);
    if (debug) assert.equal(result.debugCode, "000042");
    assert.equal(result.expiresAtUtcMs - f.otp.now(), 600_000);
    assert.throws(() => f.verify(result.challengeId, "42"), /otp_incorrect/);
    assert.equal(f.store.authSessions.size, 0);
    assert.equal(f.verify(result.challengeId).user.id, f.user.id);
    assert.throws(() => f.verify(result.challengeId), /otp_challenge_invalid/);
    assert.equal(f.store.authSessions.size, 1);
  }
});

test("real generator returns six digits and legacy fixed override has no effect", (t) => {
  const f = fixture(t);
  const otp = createOtpDependencies({
    env: { OTP_DEBUG: "1", OTP_FIXED_CODE: "not-a-code" },
  });
  const result = pilotOtpStart(f.store, { phone: f.user.phone }, otp);
  assert.match(result.debugCode!, /^\d{6}$/);
  assert.equal(
    pilotOtpVerify(
      f.store,
      {
        phone: f.user.phone,
        challengeId: result.challengeId,
        code: result.debugCode!,
      },
      otp,
    ).user.id,
    f.user.id,
  );
});

test("OTP accepts just before expiry and rejects at and after expiry", (t) => {
  for (const offset of [-1, 0, 1]) {
    const f = fixture(t),
      result = f.start();
    f.setNow(result.expiresAtUtcMs + offset);
    if (offset < 0) assert.ok(f.verify(result.challengeId).accessToken);
    else {
      assert.throws(() => f.verify(result.challengeId), /otp_expired/);
      assert.equal(
        f.store.otpChallenges.get(result.challengeId)?.status,
        "EXPIRED",
      );
      assert.equal(f.store.authSessions.size, 0);
    }
  }
});

test("resend supersedes only the normalized phone, even if random codes coincide", (t) => {
  const f = fixture(t);
  const other = registerCustomerOrgAdmin(f.store, {
    fullName: "Other",
    phone: "8000000043",
    orgDisplayName: "Other",
  });
  const first = f.start(),
    unrelated = f.start(other.user.phone);
  const second = f.start("+91 8000000042");
  assert.equal(
    f.store.otpChallenges.get(first.challengeId)?.status,
    "SUPERSEDED",
  );
  assert.equal(
    f.store.otpChallenges.get(unrelated.challengeId)?.status,
    "PENDING",
  );
  assert.throws(() => f.verify(first.challengeId), /otp_challenge_invalid/);
  assert.throws(
    () => f.verify(second.challengeId, "000042", other.user.phone),
    /otp_challenge_mismatch/,
  );
  assert.ok(f.verify(second.challengeId).accessToken);
});

test("invalid starts and signing failures preserve a usable challenge", (t) => {
  const f = fixture(t),
    first = f.start();
  assert.throws(() => f.start("bad"), /invalid_phone/);
  assert.throws(() => f.start("8000000099"), /user_not_found/);
  assert.throws(
    () =>
      pilotOtpStart(
        f.store,
        { phone: f.user.phone },
        { ...f.otp, generateCode: () => "bad" },
      ),
    /otp_generator_invalid/,
  );
  f.store.users.set(f.user.id, { ...f.user, inactiveAtUtcMs: f.otp.now() });
  assert.throws(() => f.start(), /account_inactive/);
  assert.throws(() => f.verify(first.challengeId), /account_inactive/);
  f.store.users.set(f.user.id, f.user);
  assert.throws(() => f.verify("missing"), /otp_challenge_not_found/);
  const secret = process.env.AUTH_SECRET;
  delete process.env.AUTH_SECRET;
  assert.throws(() => f.verify(first.challengeId), /AUTH_SECRET/);
  process.env.AUTH_SECRET = secret;
  assert.equal(f.store.otpChallenges.get(first.challengeId)?.status, "PENDING");
  assert.equal(f.store.authSessions.size, 0);
  assert.ok(f.verify(first.challengeId).accessToken);
});
