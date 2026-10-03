import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { mkdir, rename, rm, stat } from "node:fs/promises";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { createApp } from "./httpServer.ts";

const START = "/v1/auth/otp/start",
  VERIFY = "/v1/auth/otp/verify";

test("invalid OTP config fails application startup", async (t) => {
  const old = process.env.OTP_TTL_MS;
  t.after(() => {
    if (old === undefined) delete process.env.OTP_TTL_MS;
    else process.env.OTP_TTL_MS = old;
  });
  process.env.OTP_TTL_MS = "0";
  await assert.rejects(createApp(), /OTP_TTL_MS_invalid/);
});

test("HTTP concurrent OTP starts reuse one challenge and concurrent verification persists one session", async (t) => {
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  const before = f.store.authSessions.size;
  const [a, b] = await Promise.all([
    f.request(START, "POST", { phone }),
    f.request(START, "POST", { phone }),
  ]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);
  assert.equal(a.body.challengeId, b.body.challengeId);
  assert.equal(a.body.debugCode, b.body.debugCode);
  assert.equal(typeof a.body.retryAfterMs, "number");
  const current = b;
  const payload = {
    phone,
    challengeId: current.body.challengeId,
    code: current.body.debugCode,
  };
  const results = await Promise.all([
    f.request(VERIFY, "POST", payload),
    f.request(VERIFY, "POST", payload),
  ]);
  assert.equal(results.filter((r) => r.status === 200).length, 1);
  assert.equal(
    results.filter((r) => r.body.error === "otp_challenge_invalid").length,
    1,
  );
  assert.equal(f.store.authSessions.size, before + 1);
  const reloaded = loadStoreFromDisk(f.dataFilePath!);
  assert.equal(
    reloaded.otpChallenges.get(current.body.challengeId)?.status,
    "CONSUMED",
  );
});

test("cooldown retries reuse the current challenge without rewriting the store", async (t) => {
  const f = await httpFixture(t), phone = f.shipperA.user.phone;
  const first = await f.request(START, "POST", { phone });
  const before = await stat(f.dataFilePath!, { bigint: true });
  const retry = await f.request(START, "POST", { phone });
  const after = await stat(f.dataFilePath!, { bigint: true });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.challengeId, first.body.challengeId);
  assert.equal(retry.body.debugCode, first.body.debugCode);
  assert.ok(retry.body.retryAfterMs > 0);
  assert.equal(after.mtimeNs, before.mtimeNs);
});

test("phone resend limit returns 429 and preserves the usable current challenge", async (t) => {
  const oldLimit = process.env.OTP_PHONE_START_LIMIT;
  const oldCooldown = process.env.OTP_RESEND_COOLDOWN_MS;
  process.env.OTP_PHONE_START_LIMIT = "2";
  process.env.OTP_RESEND_COOLDOWN_MS = "1";
  t.after(() => {
    if (oldLimit === undefined) delete process.env.OTP_PHONE_START_LIMIT;
    else process.env.OTP_PHONE_START_LIMIT = oldLimit;
    if (oldCooldown === undefined) delete process.env.OTP_RESEND_COOLDOWN_MS;
    else process.env.OTP_RESEND_COOLDOWN_MS = oldCooldown;
  });
  const f = await httpFixture(t), phone = f.shipperA.user.phone;
  // The fixture's initial login used one issuance; this second code uses the last slot.
  const started = await f.request(START, "POST", { phone });
  assert.equal(started.status, 200);
  await new Promise((resolve) => setTimeout(resolve, 5));
  const limited = await f.request(START, "POST", { phone });
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "otp_rate_limited");
  assert.ok(limited.body.retryAfterMs > 0);
  assert.ok(Number(limited.body.retryAfterMs) <= 3_600_000);
  const challenge = [...f.store.otpChallenges.values()].find((item) => item.phone === phone && item.status === "PENDING");
  assert.ok(challenge);
  const verified = await f.request(VERIFY, "POST", { phone, challengeId: challenge.id, code: challenge.code });
  assert.equal(verified.status, 200);
});

test("HTTP OTP starts are rate limited by the connecting IP", async (t) => {
  const oldLimit = process.env.OTP_IP_START_LIMIT;
  process.env.OTP_IP_START_LIMIT = "7";
  t.after(() => oldLimit === undefined ? delete process.env.OTP_IP_START_LIMIT : process.env.OTP_IP_START_LIMIT = oldLimit);
  const f = await httpFixture(t);
  const limited = await f.request(START, "POST", { phone: f.shipperA.user.phone });
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "otp_rate_limited");
  assert.ok(limited.body.retryAfterMs > 0);
  assert.ok(limited.body.retryAfterMs <= 600_000);
});

test("HTTP expiration is persisted even though verification returns an error", async (t) => {
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  const result = await f.request(START, "POST", { phone });
  const ch = f.store.otpChallenges.get(result.body.challengeId)!;
  f.store.otpChallenges.set(ch.id, { ...ch, expiresAtUtcMs: Date.now() - 1 });
  const verified = await f.request(VERIFY, "POST", {
    phone,
    challengeId: ch.id,
    code: result.body.debugCode,
  });
  assert.equal(verified.body.error, "otp_expired");
  assert.equal(
    loadStoreFromDisk(f.dataFilePath!).otpChallenges.get(ch.id)?.status,
    "EXPIRED",
  );
});

test("HTTP lockout after too many wrong codes is persisted, and the right code then fails", async (t) => {
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  const result = await f.request(START, "POST", { phone });
  const challengeId = result.body.challengeId;
  const wrong = result.body.debugCode === "000000" ? "111111" : "000000";
  for (let attempt = 1; attempt <= 4; attempt++) {
    const refused = await f.request(VERIFY, "POST", { phone, challengeId, code: wrong });
    assert.equal(refused.body.error, "otp_incorrect");
  }
  const locked = await f.request(VERIFY, "POST", { phone, challengeId, code: wrong });
  assert.equal(locked.body.error, "otp_attempts_exceeded");
  assert.equal(
    loadStoreFromDisk(f.dataFilePath!).otpChallenges.get(challengeId)?.status,
    "EXPIRED",
  );
  const right = await f.request(VERIFY, "POST", { phone, challengeId, code: result.body.debugCode });
  assert.equal(right.body.error, "otp_challenge_invalid");
});

test("failed persistence returns no code/session and restores previous OTP state", async (t) => {
  const oldCooldown = process.env.OTP_RESEND_COOLDOWN_MS;
  process.env.OTP_RESEND_COOLDOWN_MS = "1";
  t.after(() => oldCooldown === undefined ? delete process.env.OTP_RESEND_COOLDOWN_MS : process.env.OTP_RESEND_COOLDOWN_MS = oldCooldown);
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  const started = await f.request(START, "POST", { phone });
  await new Promise((resolve) => setTimeout(resolve, 5));
  const original = f.store.otpChallenges.get(started.body.challengeId)!;
  const sessionCount = f.store.authSessions.size,
    challengeCount = f.store.otpChallenges.size;
  // A directory at the synthetic file target reliably fails the atomic file rename.
  const file = f.dataFilePath!;
  await rename(file, file + ".saved");
  await mkdir(file);
  try {
    const start = await f.request(START, "POST", { phone });
    assert.notEqual(start.status, 200);
    assert.equal(start.body.debugCode, undefined);
    assert.equal(f.store.otpChallenges.size, challengeCount);
    assert.equal(f.store.otpChallenges.get(original.id)?.status, "PENDING");
    const verify = await f.request(VERIFY, "POST", {
      phone,
      challengeId: original.id,
      code: started.body.debugCode,
    });
    assert.notEqual(verify.status, 200);
    assert.equal(verify.body.accessToken, undefined);
    assert.equal(f.store.authSessions.size, sessionCount);
    assert.equal(f.store.otpChallenges.get(original.id)?.status, "PENDING");
  } finally {
    await rm(file, { recursive: true });
    await rename(file + ".saved", file);
  }
  assert.equal(
    (
      await f.request(VERIFY, "POST", {
        phone,
        challengeId: original.id,
        code: started.body.debugCode,
      })
    ).status,
    200,
  );
});

test("debug configuration is captured at startup; client parameters cannot enable it", async (t) => {
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  process.env.OTP_DEBUG = "0";
  // The existing app retains its startup configuration.
  assert.match(
    (await f.request(START, "POST", { phone })).body.debugCode,
    /^\d{6}$/,
  );
  await f.persist();
  const app = await createApp();
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  t.after(async () => {
    app.server.closeAllConnections();
    await new Promise<void>((r) => app.server.close(() => r()));
  });
  const address = app.server.address();
  assert.ok(address && typeof address === "object");
  const response = await fetch(
    `http://127.0.0.1:${address.port}${START}?OTP_DEBUG=1`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone, debug: true, OTP_DEBUG: "1" }),
    },
  );
  assert.equal(response.status, 200);
  assert.equal(Object.hasOwn(await response.json(), "debugCode"), false);
});
