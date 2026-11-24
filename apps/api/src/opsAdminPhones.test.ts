import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import { once } from "node:events";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "./httpServer.ts";
import { setFirebaseTokenVerifierForTests } from "./auth.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { createStore, type Store } from "./store.ts";
import { grantOpsAdminFromList, isOpsAdmin, opsAdminPhonesFromEnv, registerCustomerOrgAdmin } from "./services.ts";

const PLATFORM_ORG = "org_platform_ops";
// Synthetic numbers: 555-01xx is reserved for fiction in the US, 80000001xx matches the repo's other fixtures.
const US_PHONE = "2025550143";
const US_PHONE_TWO = "2025550144";
const INDIA_PHONE = "8000000101";
const INDIA_PHONE_TWO = "8000000102";
const INDIA_PHONE_THREE = "8000000103";

const CONTROLLED_ENV = ["NODE_ENV", "OTP_DEBUG", "OTP_TRUST_PROXY", "AUTH_SECRET", "PERSISTENCE", "PAYMENT_PROVIDER", "PAYOUTS_MODE",
  "FIREBASE_PROJECT_ID", "OPS_ADMIN_PHONES", "DATA_FILE"];
const originalEnv = Object.fromEntries(CONTROLLED_ENV.map((name) => [name, process.env[name]]));

async function tempDataFile(t: TestContext): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "ops-admin-phones-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return join(dir, "store.json");
}

async function startApp(t: TestContext, opsAdminPhones: string | undefined, dataFilePath: string) {
  for (const name of CONTROLLED_ENV) delete process.env[name];
  Object.assign(process.env, {
    NODE_ENV: "test", OTP_DEBUG: "1", PERSISTENCE: "FILE", PAYMENT_PROVIDER: "MOCK", PAYOUTS_MODE: "BOOKKEEPING",
    AUTH_SECRET: "synthetic-test-signing-value-only", FIREBASE_PROJECT_ID: "test-project",
  }, opsAdminPhones === undefined ? {} : { OPS_ADMIN_PHONES: opsAdminPhones });
  const app = await createApp({ dataFilePath });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const address = app.server.address();
  assert.ok(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;
  async function close() {
    if (!app.server.listening) return;
    app.server.closeAllConnections();
    await new Promise<void>((done) => app.server.close(() => done()));
  }
  t.after(async () => {
    await close();
    setFirebaseTokenVerifierForTests();
    for (const [name, value] of Object.entries(originalEnv)) {
      if (value === undefined) delete process.env[name]; else process.env[name] = value;
    }
  });
  async function request(path: string, method: string, body?: unknown, token?: string, organizationId?: string) {
    const response = await fetch(base + path, {
      method,
      headers: {
        "content-type": "application/json",
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(organizationId ? { "x-organization-id": organizationId } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  }
  async function register(phone: string, countryCode: string) {
    const out = await request("/v1/pilot/customer/users/register", "POST", { fullName: "Synthetic person", phone, countryCode });
    assert.equal(out.status, 201);
    return out.body.user.id as string;
  }
  async function otpSignIn(phone: string, countryCode: string) {
    const start = await request("/v1/auth/otp/start", "POST", { phone, countryCode });
    assert.equal(start.status, 200);
    const verified = await request("/v1/auth/otp/verify", "POST", { phone, countryCode, challengeId: start.body.challengeId, code: start.body.debugCode });
    assert.equal(verified.status, 200);
    return verified.body as { accessToken: string; isOpsAdmin: boolean; user: { id: string } };
  }
  async function firebaseSignIn(e164: string, idToken: string) {
    setFirebaseTokenVerifierForTests(async () => ({
      uid: `firebase-${e164}`,
      phone_number: e164,
      aud: "test-project",
      iss: "https://securetoken.google.com/test-project",
      exp: Math.floor(Date.now() / 1000) + 60,
      firebase: { sign_in_provider: "phone" },
    }));
    const out = await request("/v1/auth/firebase/exchange", "POST", { idToken });
    assert.equal(out.status, 200);
    return out.body as { accessToken: string; isOpsAdmin: boolean; user: { id: string } };
  }
  const me = (token: string, organizationId?: string) => request("/v1/auth/me", "GET", undefined, token, organizationId);
  return { ...app, request, register, otpSignIn, firebaseSignIn, me, close };
}

function platformRecord(store: Store, userId: string) {
  const key = `${userId}:${PLATFORM_ORG}`;
  return {
    membership: store.memberships.get(key),
    roles: store.membershipRoles.get(key),
    audits: [...store.auditEvents.values()].filter((e) => e.resourceType === "membership" && e.resourceId === key),
    membershipCount: [...store.memberships.values()].filter((m) => m.userId === userId).length,
  };
}

async function assertSignedInAsPlatformAdmin(app: Awaited<ReturnType<typeof startApp>>, token: string, userId: string) {
  assert.equal(isOpsAdmin(app.store, userId), true);
  const out = await app.me(token);
  assert.equal(out.status, 200);
  assert.equal(out.body.isOpsAdmin, true);
  assert.equal(out.body.principal.internal, true);
  assert.equal(out.body.principal.organizationId, PLATFORM_ORG);
  assert.deepEqual([...out.body.principal.roles].sort(), ["ADMIN", "OPS"]);
  assert.ok(out.body.organizations.some((org: { id: string }) => org.id === PLATFORM_ORG));
}

test("OPS_ADMIN_PHONES keeps entries that carry a country code and ignores the rest without logging the number", (t) => {
  const warn = t.mock.method(console, "warn", () => {});
  const keys = opsAdminPhonesFromEnv({
    OPS_ADMIN_PHONES: ` +1 (202) 555-0143, +918000000101,918000000102, ${INDIA_PHONE_THREE}, , +44 20 7946 0000, 12025550144 `,
  });
  assert.deepEqual([...keys].sort(), ["+1:2025550143", "+91:8000000101", "+91:8000000102"]);
  const logged = warn.mock.calls.map((call) => call.arguments.join(" "));
  assert.equal(logged.length, 3);
  assert.match(logged[0]!, /entry 4\b/);
  assert.match(logged[1]!, /entry 6\b/);
  assert.match(logged[2]!, /entry 7\b/);
  for (const line of logged) assert.doesNotMatch(line, /8000000103|7946|2025550144|5550144/);
  assert.equal(opsAdminPhonesFromEnv({}).size, 0);
  assert.equal(warn.mock.callCount(), 3);
});

test("a listed US number becomes platform admin at OTP sign-in, and signing in again adds nothing", async (t) => {
  const dataFilePath = await tempDataFile(t);
  const app = await startApp(t, `+1${US_PHONE}`, dataFilePath);
  const userId = await app.register(US_PHONE, "+1");
  const first = await app.otpSignIn(US_PHONE, "+1");
  assert.equal(first.isOpsAdmin, true);
  await assertSignedInAsPlatformAdmin(app, first.accessToken, userId);
  const record = platformRecord(app.store, userId);
  assert.equal(record.membership?.role, "OPS_ADMIN");
  assert.deepEqual(record.roles, ["ADMIN", "OPS"]);
  assert.equal(record.audits.length, 1);
  assert.equal(record.audits[0]!.action, "ROLE_ASSIGNED");
  assert.equal(record.audits[0]!.reasonCode, "OPS_ADMIN_PHONES");
  assert.equal(record.audits[0]!.source, "SYSTEM");

  const saved = platformRecord(loadStoreFromDisk(dataFilePath), userId);
  assert.equal(saved.membership?.role, "OPS_ADMIN");
  assert.deepEqual(saved.roles, ["ADMIN", "OPS"]);
  assert.equal(saved.audits.length, 1);

  const second = await app.otpSignIn(US_PHONE, "+1");
  assert.equal(second.isOpsAdmin, true);
  const after = platformRecord(app.store, userId);
  assert.equal(after.membershipCount, 1);
  assert.equal(after.audits.length, 1);
});

test("a listed +91 number becomes admin; a bare 10-digit entry and an unlisted number get nothing", async (t) => {
  const app = await startApp(t, `+91${INDIA_PHONE}, ${INDIA_PHONE_TWO}`, await tempDataFile(t));
  const listed = await app.register(INDIA_PHONE, "+91");
  const bare = await app.register(INDIA_PHONE_TWO, "+91");
  const unlisted = await app.register(INDIA_PHONE_THREE, "+91");

  const listedSignIn = await app.otpSignIn(INDIA_PHONE, "+91");
  assert.equal(listedSignIn.isOpsAdmin, true);
  await assertSignedInAsPlatformAdmin(app, listedSignIn.accessToken, listed);

  for (const [phone, userId] of [[INDIA_PHONE_TWO, bare], [INDIA_PHONE_THREE, unlisted]] as const) {
    const out = await app.otpSignIn(phone, "+91");
    assert.equal(out.isOpsAdmin, false);
    const record = platformRecord(app.store, userId);
    assert.equal(record.membershipCount, 0);
    assert.equal(record.audits.length, 0);
    const meOut = await app.me(out.accessToken);
    assert.equal(meOut.body.isOpsAdmin, false);
    assert.deepEqual(meOut.body.organizations, []);
  }
});

test("a user who signed up before their number was listed becomes admin on the next sign-in", async (t) => {
  const dataFilePath = await tempDataFile(t);
  const before = await startApp(t, undefined, dataFilePath);
  const userId = await before.register(US_PHONE, "+1");
  const plain = await before.otpSignIn(US_PHONE, "+1");
  assert.equal(plain.isOpsAdmin, false);
  assert.equal(platformRecord(before.store, userId).membershipCount, 0);
  await before.close();

  const after = await startApp(t, `+1${US_PHONE}`, dataFilePath);
  const signedIn = await after.otpSignIn(US_PHONE, "+1");
  assert.equal(signedIn.isOpsAdmin, true);
  await assertSignedInAsPlatformAdmin(after, signedIn.accessToken, userId);
});

test("an admin revoked on the admin page stays revoked while the number is still listed, on both sign-in paths", async (t) => {
  const app = await startApp(t, `+1${US_PHONE},+1${US_PHONE_TWO}`, await tempDataFile(t));
  await app.register(US_PHONE, "+1");
  const revokedUserId = await app.register(US_PHONE_TWO, "+1");
  const keeper = await app.otpSignIn(US_PHONE, "+1");
  const revoked = await app.otpSignIn(US_PHONE_TWO, "+1");
  assert.equal(revoked.isOpsAdmin, true);

  const revoke = await app.request(`/v1/ops-admins/${US_PHONE_TWO}?countryCode=%2B1`, "DELETE", undefined, keeper.accessToken);
  assert.equal(revoke.status, 200);
  assert.equal(platformRecord(app.store, revokedUserId).membership, undefined);
  const auditsAfterRevoke = platformRecord(app.store, revokedUserId).audits.length;

  const otpAgain = await app.otpSignIn(US_PHONE_TWO, "+1");
  assert.equal(otpAgain.isOpsAdmin, false);
  const firebaseAgain = await app.firebaseSignIn(`+1${US_PHONE_TWO}`, "revoked-admin-token");
  assert.equal(firebaseAgain.isOpsAdmin, false);
  const record = platformRecord(app.store, revokedUserId);
  assert.equal(record.membershipCount, 0);
  assert.equal(record.audits.length, auditsAfterRevoke);
});

test("an existing platform row is never changed by the list, whether inactive, emptied or a support agent", () => {
  const listed = new Set(["+1:2025550143", "+1:2025550144", "+1:2025550145"]);
  const store = createStore();
  store.organizations.set(PLATFORM_ORG, { id: PLATFORM_ORG, kind: "PLATFORM", displayName: "Platform", kycStatus: "APPROVED", createdAtUtcMs: 1 });
  const rows = [
    { userId: "usr_inactive", phone: "2025550143", role: "OPS_ADMIN" as const, roles: ["ADMIN", "OPS"] as const, inactiveAtUtcMs: 5 },
    { userId: "usr_emptied", phone: "2025550144", role: "OPS_ADMIN" as const, roles: [] as const },
    { userId: "usr_agent", phone: "2025550145", role: "OPS_AGENT" as const, roles: ["OPS"] as const },
  ];
  for (const row of rows) {
    store.users.set(row.userId, { id: row.userId, phone: row.phone, countryCode: "+1", fullName: "Synthetic", createdAtUtcMs: 1 });
    store.memberships.set(`${row.userId}:${PLATFORM_ORG}`, {
      userId: row.userId, orgId: PLATFORM_ORG, role: row.role, createdAtUtcMs: 1,
      ...("inactiveAtUtcMs" in row ? { inactiveAtUtcMs: row.inactiveAtUtcMs } : {}),
    });
    store.membershipRoles.set(`${row.userId}:${PLATFORM_ORG}`, [...row.roles]);
  }
  const membershipsBefore = structuredClone([...store.memberships]);
  const rolesBefore = structuredClone([...store.membershipRoles]);
  for (const row of rows) assert.equal(grantOpsAdminFromList(store, row.userId, listed), false);
  assert.deepEqual([...store.memberships], membershipsBefore);
  assert.deepEqual([...store.membershipRoles], rolesBefore);
  assert.equal(store.auditEvents.size, 0);
});

test("a listed number with a customer membership keeps it and gains the platform one", async (t) => {
  const app = await startApp(t, `+91${INDIA_PHONE}`, await tempDataFile(t));
  const customer = registerCustomerOrgAdmin(app.store, { fullName: "Synthetic shipper", phone: INDIA_PHONE, countryCode: "+91", orgDisplayName: "Synthetic Shipper" });
  const signedIn = await app.otpSignIn(INDIA_PHONE, "+91");
  const record = platformRecord(app.store, customer.user.id);
  assert.equal(record.membershipCount, 2);
  assert.equal(record.membership?.role, "OPS_ADMIN");
  assert.equal(app.store.memberships.get(`${customer.user.id}:${customer.org.id}`)?.role, "CUSTOMER_ADMIN");

  const asPlatform = await app.me(signedIn.accessToken, PLATFORM_ORG);
  assert.equal(asPlatform.status, 200);
  assert.equal(asPlatform.body.principal.internal, true);
  assert.deepEqual([...asPlatform.body.principal.roles].sort(), ["ADMIN", "OPS"]);
  const ids = asPlatform.body.organizations.map((org: { id: string }) => org.id).sort();
  assert.deepEqual(ids, [customer.org.id, PLATFORM_ORG].sort());

  const asShipper = await app.me(signedIn.accessToken, customer.org.id);
  assert.equal(asShipper.status, 200);
  assert.deepEqual(asShipper.body.principal.roles, ["SHIPPER"]);
});

test("a listed number becomes admin through the Firebase sign-in, once, and an unlisted one gets nothing", async (t) => {
  const dataFilePath = await tempDataFile(t);
  const app = await startApp(t, `+1${US_PHONE}`, dataFilePath);
  const userId = await app.register(US_PHONE, "+1");
  const unlistedUserId = await app.register(US_PHONE_TWO, "+1");

  const first = await app.firebaseSignIn(`+1${US_PHONE}`, "listed-token-one");
  assert.equal(first.isOpsAdmin, true);
  await assertSignedInAsPlatformAdmin(app, first.accessToken, userId);
  await app.firebaseSignIn(`+1${US_PHONE}`, "listed-token-two");
  await app.firebaseSignIn(`+1${US_PHONE}`, "listed-token-two");
  const record = platformRecord(app.store, userId);
  assert.equal(record.membershipCount, 1);
  assert.equal(record.audits.length, 1);
  assert.equal(record.audits[0]!.reasonCode, "OPS_ADMIN_PHONES");
  assert.equal(platformRecord(loadStoreFromDisk(dataFilePath), userId).membership?.role, "OPS_ADMIN");

  const unlisted = await app.firebaseSignIn(`+1${US_PHONE_TWO}`, "unlisted-token");
  assert.equal(unlisted.isOpsAdmin, false);
  assert.equal(platformRecord(app.store, unlistedUserId).membershipCount, 0);
});

test("a Firebase user already signed in before being listed becomes admin, and the grant is saved", async (t) => {
  const dataFilePath = await tempDataFile(t);
  const before = await startApp(t, undefined, dataFilePath);
  const userId = await before.register(US_PHONE, "+1");
  const plain = await before.firebaseSignIn(`+1${US_PHONE}`, "same-token");
  assert.equal(plain.isOpsAdmin, false);
  await before.close();

  // The same token again finds the saved session and identity, so only the grant changes the store.
  const after = await startApp(t, `+1${US_PHONE}`, dataFilePath);
  const signedIn = await after.firebaseSignIn(`+1${US_PHONE}`, "same-token");
  assert.equal(signedIn.isOpsAdmin, true);
  await assertSignedInAsPlatformAdmin(after, signedIn.accessToken, userId);
  assert.equal(platformRecord(loadStoreFromDisk(dataFilePath), userId).membership?.role, "OPS_ADMIN");
});
