import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  createOtpDependencies,
  pilotOtpStart,
  pilotOtpVerify,
} from "./auth.ts";
import { loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
import { createStore } from "./store.ts";
import { registerCustomerOrgAdmin } from "./services.ts";

const SYNTHETIC_AUTH_SECRET = "otp-persistence-test-secret";
const NOW = 1_800_000_000_000;

const previousAuthSecret = process.env.AUTH_SECRET;
test.before(() => {
  process.env.AUTH_SECRET = SYNTHETIC_AUTH_SECRET;
});
test.after(() => {
  if (previousAuthSecret === undefined) delete process.env.AUTH_SECRET;
  else process.env.AUTH_SECRET = previousAuthSecret;
});

function seed() {
  const store = createStore();
  const account = registerCustomerOrgAdmin(store, {
    fullName: "OTP Persistence User",
    phone: "9876543210",
    orgDisplayName: "OTP Persistence Org",
  });
  return { store, user: account.user };
}

function deps(now = NOW, code = "123456") {
  return createOtpDependencies({
    env: { OTP_TTL_MS: "600000", OTP_DEBUG: "1" },
    now: () => now,
    generateCode: () => code,
  });
}

async function assertReloadedChallengeRejects(
  load: () => Promise<ReturnType<typeof createStore>>,
  status: "CONSUMED" | "EXPIRED" | "SUPERSEDED",
  challengeId: string,
) {
  const first = seed();
  const reloaded = await load();
  assert.ok(
    [...reloaded.users.values()].some(
      (user) => user.phone === first.user.phone,
    ),
  );
  assert.equal(reloaded.otpChallenges.get(challengeId)?.status, status);
  assert.throws(
    () =>
      pilotOtpVerify(
        reloaded,
        { phone: first.user.phone, challengeId, code: "123456" },
        deps(),
      ),
    /otp_challenge_invalid|otp_expired/,
  );
  assert.equal(reloaded.otpChallenges.get(challengeId)?.status, status);
  assert.equal(reloaded.authSessions.size, status === "CONSUMED" ? 1 : 0);
}

test("FILE persistence reloads pending OTP and preserves user/session", async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "otp-persistence-"));
  const file = path.join(dir, "store.json");
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const first = seed();
  const started = pilotOtpStart(
    first.store,
    { phone: first.user.phone },
    deps(),
  );
  saveStoreToDisk(file, first.store);
  const reloaded = loadStoreFromDisk(file);
  assert.equal(
    reloaded.users.get(first.user.id)?.fullName,
    first.user.fullName,
  );
  const verified = pilotOtpVerify(
    reloaded,
    {
      phone: first.user.phone,
      challengeId: started.challengeId,
      code: "123456",
    },
    deps(),
  );
  saveStoreToDisk(file, reloaded);
  const finalStore = loadStoreFromDisk(file);
  assert.equal(
    finalStore.otpChallenges.get(started.challengeId)?.status,
    "CONSUMED",
  );
  assert.ok(finalStore.authSessions.has(verified.session.id));
  assert.equal(finalStore.users.get(first.user.id)?.phone, first.user.phone);
});

test("FILE persistence rejects consumed, expired, and superseded OTP after reload", async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "otp-lifecycle-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const status of ["CONSUMED", "EXPIRED", "SUPERSEDED"] as const) {
    const file = path.join(dir, `${status}.json`);
    const original = seed();
    const started = pilotOtpStart(
      original.store,
      { phone: original.user.phone },
      deps(),
    );
    if (status === "CONSUMED")
      pilotOtpVerify(
        original.store,
        {
          phone: original.user.phone,
          challengeId: started.challengeId,
          code: "123456",
        },
        deps(),
      );
    if (status === "EXPIRED")
      assert.throws(
        () =>
          pilotOtpVerify(
            original.store,
            {
              phone: original.user.phone,
              challengeId: started.challengeId,
              code: "123456",
            },
            deps(NOW + 600000),
          ),
        /otp_expired/,
      );
    if (status === "SUPERSEDED")
      pilotOtpStart(original.store, { phone: original.user.phone }, deps(NOW + 30_000));
    saveStoreToDisk(file, original.store);
    await assertReloadedChallengeRejects(
      async () => loadStoreFromDisk(file),
      status,
      started.challengeId,
    );
  }
});

const databaseUrl = process.env.OTP_TEST_DATABASE_URL;
const disposableDatabaseUrl =
  databaseUrl &&
  /^postgres(?:ql)?:\/\/[^/]*127\.0\.0\.1(?::\d+)?\/navig8r_otp_test(?:\?.*)?$/.test(
    databaseUrl,
  )
    ? databaseUrl
    : undefined;
test(
  "PostgreSQL persistence reloads OTP lifecycle state",
  { skip: !databaseUrl },
  async (t) => {
    assert.ok(
      disposableDatabaseUrl,
      "OTP_TEST_DATABASE_URL must target 127.0.0.1/navig8r_otp_test",
    );
    const previousDatabaseUrl = process.env.DATABASE_URL;
    t.after(() => {
      if (previousDatabaseUrl === undefined) delete process.env.DATABASE_URL;
      else process.env.DATABASE_URL = previousDatabaseUrl;
    });
    process.env.DATABASE_URL = disposableDatabaseUrl;
    const { loadStoreFromDatabase, saveStoreToDatabase, closeDatabase } =
      await import("./persistenceDb.ts");
    t.after(async () => {
      await saveStoreToDatabase(createStore());
      await closeDatabase();
    });
    const pending = seed();
    const start = pilotOtpStart(
      pending.store,
      { phone: pending.user.phone },
      deps(NOW, "000042"),
    );
    await saveStoreToDatabase(pending.store);
    const pendingReload = await loadStoreFromDatabase();
    const verified = pilotOtpVerify(
      pendingReload,
      {
        phone: pending.user.phone,
        challengeId: start.challengeId,
        code: "000042",
      },
      deps(),
    );
    await saveStoreToDatabase(pendingReload);
    const consumedReload = await loadStoreFromDatabase();
    assert.equal(
      consumedReload.users.get(pending.user.id)?.phone,
      pending.user.phone,
    );
    assert.equal(
      consumedReload.otpChallenges.get(start.challengeId)?.status,
      "CONSUMED",
    );
    assert.ok(consumedReload.authSessions.has(verified.session.id));
    for (const status of ["CONSUMED", "EXPIRED", "SUPERSEDED"] as const) {
      const first = seed();
      const started = pilotOtpStart(
        first.store,
        { phone: first.user.phone },
        deps(),
      );
      if (status === "CONSUMED")
        pilotOtpVerify(
          first.store,
          {
            phone: first.user.phone,
            challengeId: started.challengeId,
            code: "123456",
          },
          deps(),
        );
      if (status === "EXPIRED")
        assert.throws(
          () =>
            pilotOtpVerify(
              first.store,
              {
                phone: first.user.phone,
                challengeId: started.challengeId,
                code: "123456",
              },
              deps(NOW + 600000),
            ),
          /otp_expired/,
        );
      if (status === "SUPERSEDED")
        pilotOtpStart(first.store, { phone: first.user.phone }, deps(NOW + 30_000));
      await saveStoreToDatabase(first.store);
      const reloaded = await loadStoreFromDatabase();
      assert.equal(
        reloaded.otpChallenges.get(started.challengeId)?.status,
        status,
      );
      assert.throws(
        () =>
          pilotOtpVerify(
            reloaded,
            {
              phone: first.user.phone,
              challengeId: started.challengeId,
              code: "123456",
            },
            deps(),
          ),
        /otp_challenge_invalid|otp_expired/,
      );
    }
  },
);
