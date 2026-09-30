import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { mkdir, rename, rm } from "node:fs/promises";
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

test("HTTP resends and concurrent verification persist one successful session", async (t) => {
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  const before = f.store.authSessions.size;
  const [a, b] = await Promise.all([
    f.request(START, "POST", { phone }),
    f.request(START, "POST", { phone }),
  ]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);
  const old =
    f.store.otpChallenges.get(a.body.challengeId)?.status === "SUPERSEDED"
      ? a
      : b;
  const current = old === a ? b : a;
  assert.equal(
    (
      await f.request(VERIFY, "POST", {
        phone,
        challengeId: old.body.challengeId,
        code: old.body.debugCode,
      })
    ).body.error,
    "otp_challenge_invalid",
  );
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
    reloaded.otpChallenges.get(old.body.challengeId)?.status,
    "SUPERSEDED",
  );
  assert.equal(
    reloaded.otpChallenges.get(current.body.challengeId)?.status,
    "CONSUMED",
  );
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

test("failed persistence returns no code/session and restores previous OTP state", async (t) => {
  const f = await httpFixture(t),
    phone = f.shipperA.user.phone;
  const started = await f.request(START, "POST", { phone });
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
