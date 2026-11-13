import assert from "node:assert/strict";
import test from "node:test";
import { firebasePhoneExchange, setFirebaseTokenVerifierForTests } from "./auth.ts";
import { createStore } from "./store.ts";
import { guardRequest } from "./rbacRoutes.ts";
import { dumpStore, loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
import { createApp } from "./httpServer.ts";
import { once } from "node:events";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

test("Firebase phone exchange isolates sessions and retries by verified token", async () => {
  const previousSecret = process.env.AUTH_SECRET;
  process.env.AUTH_SECRET = "test-secret-long-enough";
  const store = createStore();
  store.users.set("u1", { id: "u1", phone: "9876543210", fullName: "Test", createdAtUtcMs: Date.now() });
  store.authSessions.set("legacy-session", {
    id: "legacy-session",
    userId: "u1",
    createdAtUtcMs: Date.now() - 1000,
    expiresAtUtcMs: Date.now() + 60_000,
    revokedAtUtcMs: null,
  });
  setFirebaseTokenVerifierForTests(async () => ({
    uid: "firebase-u1",
    phone_number: "+91 98765 43210",
    aud: "test-project",
    iss: "https://securetoken.google.com/test-project",
    exp: Math.floor(Date.now() / 1000) + 60,
    firebase: { sign_in_provider: "phone" },
  }));
  process.env.FIREBASE_PROJECT_ID = "test-project";
  try {
    const out = await firebasePhoneExchange(store, "opaque-test-token");
    assert.equal(out.user.id, "u1");
    assert.ok(out.accessToken);
    assert.notEqual(out.session.id, "legacy-session");
    assert.equal(out.session.authProvider, "firebase");
    assert.equal(store.authSessions.size, 2);
    assert.equal(store.firebaseIdentities.get("firebase-u1")?.userId, "u1");
    const sessionCount = store.authSessions.size;
    const retry = await firebasePhoneExchange(store, "opaque-test-token");
    assert.equal(retry.session.id, out.session.id);
    assert.equal(retry.accessToken, out.accessToken);
    assert.equal(store.authSessions.size, sessionCount);
    const secondLogin = await firebasePhoneExchange(store, "a-different-token");
    assert.notEqual(secondLogin.session.id, out.session.id);
    assert.equal(store.authSessions.size, sessionCount + 1);
    for (let i = 0; i < 6; i++) {
      await firebasePhoneExchange(store, `rotated-token-${i}`);
    }
    const activeFirebaseSessions = [...store.authSessions.values()].filter(
      (session) => session.userId === "u1" &&
        session.authProvider === "firebase" &&
        session.revokedAtUtcMs == null &&
        session.expiresAtUtcMs > Date.now(),
    );
    assert.equal(activeFirebaseSessions.length, 5);
    assert.ok(store.authSessions.has("legacy-session"));
  } finally {
    setFirebaseTokenVerifierForTests();
    if (previousSecret === undefined) delete process.env.AUTH_SECRET; else process.env.AUTH_SECRET = previousSecret;
  }
});

test("Firebase HTTP exchange limits repeated identity requests", async (t) => {
  const previous = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID,
    FIREBASE_EXCHANGE_IP_LIMIT: process.env.FIREBASE_EXCHANGE_IP_LIMIT,
    FIREBASE_EXCHANGE_IDENTITY_LIMIT: process.env.FIREBASE_EXCHANGE_IDENTITY_LIMIT,
  };
  process.env.AUTH_SECRET = "test-secret-long-enough";
  process.env.FIREBASE_PROJECT_ID = "test-project";
  process.env.FIREBASE_EXCHANGE_IP_LIMIT = "10";
  process.env.FIREBASE_EXCHANGE_IDENTITY_LIMIT = "2";
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
    setFirebaseTokenVerifierForTests();
  });
  setFirebaseTokenVerifierForTests(async () => ({
    uid: "firebase-u1",
    phone_number: "+91 98765 43210",
    aud: "test-project",
    iss: "https://securetoken.google.com/test-project",
    exp: Math.floor(Date.now() / 1000) + 60,
    firebase: { sign_in_provider: "phone" },
  }));
  const app = await createApp({ dataFilePath: `/tmp/navig8r-firebase-http-${Date.now()}.json` });
  app.store.users.set("u1", { id: "u1", phone: "9876543210", fullName: "Test", createdAtUtcMs: Date.now() });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  t.after(() => app.server.close());
  const address = app.server.address();
  assert.ok(address && typeof address === "object");
  const request = () => fetch(`http://127.0.0.1:${address.port}/v1/auth/firebase/exchange`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ idToken: "opaque-test-token" }),
  });
  assert.equal((await request()).status, 200);
  assert.equal((await request()).status, 200);
  const limited = await request();
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, "firebase_exchange_rate_limited");
  assert.equal(app.store.authSessions.size, 1);
});

test("Firebase exchange rejects non-phone provider and inactive users", async () => {
  const store = createStore();
  store.users.set("u1", { id: "u1", phone: "9876543210", fullName: "Test", createdAtUtcMs: Date.now(), inactiveAtUtcMs: Date.now() });
  setFirebaseTokenVerifierForTests(async () => ({ uid: "firebase-u1", phone_number: "+919876543210", aud: "test-project", iss: "https://securetoken.google.com/test-project", firebase: { sign_in_provider: "google.com" } }));
  await assert.rejects(() => firebasePhoneExchange(store, "token"), { message: "firebase_phone_provider_required" });
  setFirebaseTokenVerifierForTests(async () => ({ uid: "firebase-u1", phone_number: "+919876543210", aud: "test-project", iss: "https://securetoken.google.com/test-project", firebase: { sign_in_provider: "phone" } }));
  await assert.rejects(() => firebasePhoneExchange(store, "token"), { message: "account_inactive" });
  setFirebaseTokenVerifierForTests();
});

test("Firebase exchange is the only public Firebase auth route", () => {
  const store = createStore();
  const req = { method: "POST", headers: {} } as never;
  assert.doesNotThrow(() => guardRequest(req, store, new URL("http://localhost/v1/auth/firebase/exchange")));
  assert.throws(() => guardRequest(req, store, new URL("http://localhost/v1/auth/firebase/phone")), { message: "not_found" });
});

test("Firebase identity mappings survive file persistence round-trip", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-firebase-"));
  const file = path.join(dir, "store.json");
  const store = createStore();
  store.firebaseIdentities.set("firebase-u1", { uid: "firebase-u1", userId: "u1", createdAtUtcMs: 123 });
  saveStoreToDisk(file, store);
  const loaded = loadStoreFromDisk(file);
  assert.deepEqual(loaded.firebaseIdentities.get("firebase-u1"), { uid: "firebase-u1", userId: "u1", createdAtUtcMs: 123 });
  assert.deepEqual(dumpStore(loaded).firebaseIdentities, [{ uid: "firebase-u1", userId: "u1", createdAtUtcMs: 123 }]);
  fs.rmSync(dir, { recursive: true, force: true });
});
