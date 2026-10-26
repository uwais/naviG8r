import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import { once } from "node:events";
import { createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "./httpServer.ts";
import { createOtpDependencies, pilotOtpStart, pilotOtpVerify, setFirebaseTokenVerifierForTests } from "./auth.ts";
import { FIREBASE_JS_SDK_VERSION, firebaseSignInScript, staffSignInFromEnv } from "./staffSignIn.ts";

const STAFF_PAGES = ["/ops", "/admin", "/workflow", "/admin/v2", "/ops/v2", "/admin/v1", "/ops/v1", "/ops/beta"];
// Built by concatenation so the repo holds no string shaped like a real key.
const syntheticWebApiKey = "AIza" + "T".repeat(35);
const syntheticWebAppId = "1:123456789012:web:0123456789abcdef";
const webSettings = { FIREBASE_PROJECT_ID: "test-project", FIREBASE_WEB_API_KEY: syntheticWebApiKey, FIREBASE_WEB_APP_ID: syntheticWebAppId };
const CONTROLLED_ENV = ["NODE_ENV", "OTP_DEBUG", "OTP_TRUST_PROXY", "FIREBASE_PROJECT_ID", "FIREBASE_WEB_API_KEY", "FIREBASE_WEB_APP_ID",
  "ENABLE_LEGACY_DEMO_SURFACE", "FIREBASE_EXCHANGE_IP_LIMIT", "AUTH_SECRET", "PERSISTENCE", "PAYMENT_PROVIDER", "PAYOUTS_MODE"];

async function startApp(t: TestContext, env: Record<string, string>) {
  const previous = Object.fromEntries(CONTROLLED_ENV.map((name) => [name, process.env[name]]));
  for (const name of CONTROLLED_ENV) delete process.env[name];
  Object.assign(process.env, { PERSISTENCE: "FILE", PAYMENT_PROVIDER: "MOCK", PAYOUTS_MODE: "BOOKKEEPING", AUTH_SECRET: "synthetic-test-signing-value-only" }, env);
  const dir = await mkdtemp(join(tmpdir(), "staff-sign-in-"));
  const app = await createApp({ dataFilePath: join(dir, "store.json") });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const address = app.server.address();
  assert.ok(address && typeof address === "object");
  t.after(async () => {
    setFirebaseTokenVerifierForTests();
    app.server.closeAllConnections();
    await new Promise<void>((done) => app.server.close(() => done()));
    await rm(dir, { recursive: true, force: true });
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[name]; else process.env[name] = value;
    }
  });
  app.store.users.set("usr_staff", { id: "usr_staff", phone: "9876543210", fullName: "Synthetic Staff", createdAtUtcMs: Date.now() });
  const base = `http://127.0.0.1:${address.port}`;
  async function post(path: string, body: unknown, headers: Record<string, string> = {}) {
    const response = await fetch(base + path, { method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  }
  return { ...app, base, post };
}

const phoneClaims = (uid: string, phone: string) => ({
  uid,
  phone_number: phone,
  aud: "test-project",
  iss: "https://securetoken.google.com/test-project",
  exp: Math.floor(Date.now() / 1000) + 60,
  firebase: { sign_in_provider: "phone" },
});

test("in production the old code sign-in gives no code and asks the person to reload or update", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", OTP_DEBUG: "1" });
  const start = await app.post("/v1/auth/otp/start", { phone: "9876543210" });
  assert.equal(start.status, 410);
  assert.equal(start.body.error, "otp_sign_in_retired");
  assert.equal(start.body.message, "This sign-in is no longer used. Reload the page or update the app. If it still fails, try again later.");
  assert.equal(start.body.debugCode, undefined);
  assert.equal(start.body.challengeId, undefined);
  assert.equal(app.store.otpChallenges.size, 0);
});

test("in production a code issued before the change signs no one in", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", OTP_DEBUG: "1" });
  const now = Date.now();
  app.store.otpChallenges.set("otp_earlier", { id: "otp_earlier", phone: "9876543210", code: "123456", status: "PENDING", expiresAtUtcMs: now + 60_000, createdAtUtcMs: now });
  const verify = await app.post("/v1/auth/otp/verify", { phone: "9876543210", challengeId: "otp_earlier", code: "123456" });
  assert.equal(verify.status, 410);
  assert.equal(verify.body.error, "otp_sign_in_retired");
  assert.equal(verify.body.accessToken, undefined);
  assert.equal(app.store.authSessions.size, 0);
});

test("outside production the old code sign-in still works", async (t) => {
  const app = await startApp(t, { NODE_ENV: "alpha", OTP_DEBUG: "1" });
  const start = await app.post("/v1/auth/otp/start", { phone: "9876543210" });
  assert.equal(start.status, 200);
  assert.match(start.body.debugCode, /^\d{6}$/);
  const verify = await app.post("/v1/auth/otp/verify", { phone: "9876543210", challengeId: start.body.challengeId, code: start.body.debugCode });
  assert.equal(verify.status, 200);
  assert.equal(typeof verify.body.accessToken, "string");
  const me = await fetch(app.base + "/v1/auth/me", { headers: { authorization: `Bearer ${verify.body.accessToken}` } });
  assert.equal(me.status, 200);
});

test("in production a session from the old code sign-in no longer works, and a Firebase session does", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", ...webSettings });
  const earlierServer = createOtpDependencies({ env: { NODE_ENV: "beta", OTP_DEBUG: "1" } });
  const started = pilotOtpStart(app.store, { phone: "9876543210" }, earlierServer);
  const earlier = pilotOtpVerify(app.store, { phone: "9876543210", challengeId: started.challengeId, code: started.debugCode! }, earlierServer);
  const me = (token: string) => fetch(app.base + "/v1/auth/me", { headers: { authorization: `Bearer ${token}` } });
  assert.equal((await me(earlier.accessToken)).status, 401);

  setFirebaseTokenVerifierForTests(async () => phoneClaims("firebase-staff", "+919876543210"));
  const exchanged = await app.post("/v1/auth/firebase/exchange", { idToken: "known-phone" });
  assert.equal(exchanged.status, 200);
  assert.equal((await me(exchanged.body.accessToken)).status, 200);
});

test("only the named test and pre-release settings allow the old code sign-in", async (t) => {
  for (const nodeEnv of ["Production", "prod", "production ", "staging"]) {
    await t.test(JSON.stringify(nodeEnv), async (t) => {
      const app = await startApp(t, { NODE_ENV: nodeEnv, OTP_DEBUG: "1" });
      const start = await app.post("/v1/auth/otp/start", { phone: "9876543210" });
      assert.equal(start.status, 410);
      assert.equal(start.body.debugCode, undefined);
      assert.equal(staffSignInFromEnv({ NODE_ENV: nodeEnv }).kind, "not-set-up");
    });
  }
  for (const nodeEnv of ["test", "development", "alpha", "beta"]) {
    assert.equal(staffSignInFromEnv({ NODE_ENV: nodeEnv }).kind, "server-code", nodeEnv);
  }
});

test("after a send that fails, the next send on a staff page still works", async () => {
  const elements = new Map<string, any>();
  const element = (id: string) => ({
    id, value: "", textContent: "", disabled: false, handlers: {} as Record<string, (event: unknown) => Promise<void>>,
    addEventListener(type: string, handler: (event: unknown) => Promise<void>) { this.handlers[type] = handler; },
    focus() {},
    replaceWith(next: { id: string }) { elements.set(next.id, next); },
  });
  for (const id of ["phone", "send", "code", "verify", "staff-recaptcha", "staff-sign-in-message"]) elements.set(id, element(id));
  const document = { getElementById: (id: string) => elements.get(id) ?? null, createElement: () => element(""), dispatchEvent() {} };
  // Stands in for reCAPTCHA as the SDK behaves: clear() leaves the widget drawn, so a second one in that element fails.
  class RecaptchaVerifier {
    constructor(_auth: unknown, container: string) {
      const spot = document.getElementById(container);
      if (spot.widget) throw new Error("reCAPTCHA has already been rendered in this element");
      spot.widget = true;
    }
    clear() {}
  }
  let sends = 0;
  const signInWithPhoneNumber = async () => {
    sends += 1;
    if (sends === 1) throw { code: "auth/network-request-failed" };
    return { confirm: async () => ({}) };
  };
  const script = firebaseSignInScript(
    { projectId: "test-project", apiKey: syntheticWebApiKey, appId: syntheticWebAppId },
    { phone: "phone", send: "send", code: "code", verify: "verify" },
  ).replace(/^import .* from "https:\/\/www\.gstatic\.com\/firebasejs\/[^"]+";$/gm, "");
  const AsyncFunction = (async () => {}).constructor as new (...args: string[]) => (...values: unknown[]) => Promise<void>;
  await new AsyncFunction("initializeApp", "initializeAuth", "inMemoryPersistence", "RecaptchaVerifier", "signInWithPhoneNumber", "document", script)(
    () => ({}), () => ({}), {}, RecaptchaVerifier, signInWithPhoneNumber, document,
  );
  const click = () => elements.get("send").handlers.click({ preventDefault() {} });
  elements.get("phone").value = "9876543210";
  await click();
  assert.equal(elements.get("staff-sign-in-message").textContent, "No connection. Check your internet and try again.");
  await click();
  assert.equal(elements.get("staff-sign-in-message").textContent, "Code sent. Enter it to sign in.");
});

test("in production with the legacy demo switch on, user and organization lists still need a signed-in admin", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", ENABLE_LEGACY_DEMO_SURFACE: "1" });
  for (const path of ["/v1/users", "/v1/orgs"]) {
    const response = await fetch(app.base + path);
    assert.equal(response.status, 401, path);
    const body = await response.json();
    assert.equal(body.users, undefined, path);
    assert.equal(body.orgs, undefined, path);
  }
  assert.equal((await fetch(app.base + "/carriers")).status, 410);
});

test("in production with web settings, every staff page signs in with Firebase and carries no old code sign-in", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", ...webSettings });
  for (const path of STAFF_PAGES) {
    const response = await fetch(app.base + path);
    assert.equal(response.status, 200, path);
    const html = await response.text();
    assert.ok(html.includes(`https://www.gstatic.com/firebasejs/${FIREBASE_JS_SDK_VERSION}/firebase-auth.js`), path);
    assert.ok(html.includes("signInWithPhoneNumber") && html.includes("RecaptchaVerifier"), path);
    assert.ok(html.includes("/v1/auth/firebase/exchange"), path);
    assert.ok(html.includes('"authDomain":"test-project.firebaseapp.com"'), path);
    assert.ok(html.includes("navig8r-staff-signed-in"), path);
    assert.ok(!html.includes("/v1/auth/otp/"), `${path} must not offer the old code sign-in`);
    assert.ok(!html.includes("Staff sign-in is not set up on this server."), path);
  }
});

test("in production without web settings, staff pages say sign-in is not set up and offer no way in", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", FIREBASE_PROJECT_ID: "test-project" });
  for (const path of STAFF_PAGES) {
    const html = await (await fetch(app.base + path)).text();
    assert.ok(html.includes("Staff sign-in is not set up on this server."), path);
    assert.ok(!html.includes("/v1/auth/otp/"), path);
    assert.ok(!html.includes("/v1/auth/firebase/exchange"), path);
    assert.ok(!html.includes("gstatic.com/firebasejs"), path);
    assert.ok(!html.includes('id="phone"'), path);
  }
});

test("web settings outside the strict pattern are never put in a page", async (t) => {
  const unsafe = 'AIza"</script>';
  const app = await startApp(t, { NODE_ENV: "production", ...webSettings, FIREBASE_WEB_API_KEY: unsafe });
  for (const path of STAFF_PAGES) {
    const html = await (await fetch(app.base + path)).text();
    assert.ok(!html.includes(unsafe), path);
    assert.ok(html.includes("Staff sign-in is not set up on this server."), path);
  }
});

test("the web settings must each match their strict pattern", () => {
  const good = { NODE_ENV: "production", ...webSettings };
  assert.equal(staffSignInFromEnv(good).kind, "firebase");
  for (const [name, value] of [
    ["FIREBASE_WEB_API_KEY", syntheticWebApiKey + "x"],
    ["FIREBASE_WEB_API_KEY", "AIza" + "T".repeat(34) + "<"],
    ["FIREBASE_WEB_APP_ID", "1:123:web:XYZ"],
    ["FIREBASE_WEB_APP_ID", syntheticWebAppId + '"'],
    ["FIREBASE_PROJECT_ID", "Test-Project"],
    ["FIREBASE_PROJECT_ID", "test-project.evil"],
    ["FIREBASE_WEB_API_KEY", ""],
  ] as const) {
    assert.equal(staffSignInFromEnv({ ...good, [name]: value }).kind, "not-set-up", `${name}=${value}`);
  }
  assert.equal(staffSignInFromEnv({ NODE_ENV: "beta" }).kind, "server-code");
  assert.equal(staffSignInFromEnv({}).kind, "server-code");
});

test("outside production without web settings, staff pages keep the old code sign-in", async (t) => {
  const app = await startApp(t, { NODE_ENV: "beta" });
  for (const path of STAFF_PAGES) {
    const html = await (await fetch(app.base + path)).text();
    assert.ok(html.includes("/v1/auth/otp/start") && html.includes("/v1/auth/otp/verify"), path);
    assert.ok(!html.includes("gstatic.com/firebasejs"), path);
  }
});

test("/ops/beta's policy allows what Firebase phone sign-in needs and nothing broader", async (t) => {
  const app = await startApp(t, { NODE_ENV: "production", ...webSettings });
  const response = await fetch(app.base + "/ops/beta");
  const html = await response.text();
  const policy = Object.fromEntries((response.headers.get("content-security-policy") ?? "").split(";").map((part) => {
    const [name, ...sources] = part.trim().split(/\s+/);
    return [name, sources];
  }));
  const sha256 = (text: string) => `'sha256-${createHash("sha256").update(text).digest("base64")}'`;
  const pageScript = html.split("<script>")[1]?.split("</script>")[0] ?? "";
  const signInScript = html.split('<script type="module">')[1]?.split("</script>")[0] ?? "";
  assert.ok(signInScript.length > 0);
  assert.deepEqual(policy["script-src"], [
    sha256(pageScript), sha256(signInScript),
    `https://www.gstatic.com/firebasejs/${FIREBASE_JS_SDK_VERSION}/`, "https://www.google.com/recaptcha/", "https://www.gstatic.com/recaptcha/",
  ]);
  assert.deepEqual(policy["connect-src"], ["'self'", "https://identitytoolkit.googleapis.com", "https://securetoken.googleapis.com"]);
  assert.deepEqual(policy["frame-src"], ["https://www.google.com/recaptcha/", "https://recaptcha.google.com/recaptcha/"]);
  assert.deepEqual(policy["frame-ancestors"], ["'none'"]);
  assert.deepEqual(policy["object-src"], ["'none'"]);
  for (const sources of Object.values(policy)) {
    for (const source of sources as string[]) assert.ok(!source.includes("*") && !source.includes("unsafe"), source);
  }
});

test("without a trusted proxy address, the exchange is limited per identity only, like the other sign-in routes", async (t) => {
  const app = await startApp(t, { ...webSettings, FIREBASE_EXCHANGE_IP_LIMIT: "2" });
  setFirebaseTokenVerifierForTests(async (token) => {
    if (token !== "valid-token") throw new Error("rejected");
    return phoneClaims("firebase-staff", "+919876543210");
  });
  for (let attempt = 0; attempt < 3; attempt++) {
    assert.equal((await app.post("/v1/auth/firebase/exchange", { idToken: `other-${attempt}` })).status, 400);
  }
  const signedIn = await app.post("/v1/auth/firebase/exchange", { idToken: "valid-token" });
  assert.equal(signedIn.status, 200);
  assert.equal(signedIn.body.user.id, "usr_staff");
});

test("with a trusted proxy address, the per-address exchange limit still applies", async (t) => {
  const app = await startApp(t, { ...webSettings, FIREBASE_EXCHANGE_IP_LIMIT: "2", OTP_TRUST_PROXY: "1" });
  setFirebaseTokenVerifierForTests(async () => { throw new Error("rejected"); });
  const from = { "x-forwarded-for": "203.0.113.9" };
  assert.equal((await app.post("/v1/auth/firebase/exchange", { idToken: "a" }, from)).status, 400);
  assert.equal((await app.post("/v1/auth/firebase/exchange", { idToken: "b" }, from)).status, 400);
  const limited = await app.post("/v1/auth/firebase/exchange", { idToken: "c" }, from);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "firebase_exchange_rate_limited");
});

test("the exchange signs in only an existing account and grants no role", async (t) => {
  const app = await startApp(t, webSettings);
  const before = { users: app.store.users.size, memberships: app.store.memberships.size, roles: app.store.membershipRoles.size };
  setFirebaseTokenVerifierForTests(async () => phoneClaims("firebase-unknown", "+919000000001"));
  const unknown = await app.post("/v1/auth/firebase/exchange", { idToken: "unknown-phone" });
  assert.equal(unknown.status, 400);
  assert.equal(unknown.body.error, "user_not_found");
  assert.equal(app.store.firebaseIdentities.size, 0);
  assert.equal(app.store.authSessions.size, 0);

  setFirebaseTokenVerifierForTests(async () => phoneClaims("firebase-staff", "+919876543210"));
  const known = await app.post("/v1/auth/firebase/exchange", { idToken: "known-phone" });
  assert.equal(known.status, 200);
  assert.equal(known.body.isOpsAdmin, false);
  assert.deepEqual({ users: app.store.users.size, memberships: app.store.memberships.size, roles: app.store.membershipRoles.size }, before);
});

test("every inline script on every staff page parses, in each sign-in mode", async (t) => {
  for (const env of [{ NODE_ENV: "beta" }, { NODE_ENV: "production" }, { NODE_ENV: "production", ...webSettings }]) {
    await t.test(JSON.stringify(env), async (t) => {
      const app = await startApp(t, env);
      for (const path of STAFF_PAGES) {
        const html = await (await fetch(app.base + path)).text();
        const scripts = [...html.matchAll(/<script( type="module")?>([\s\S]*?)<\/script>/g)];
        assert.ok(scripts.length > 0, path);
        for (const [, module, text] of scripts) {
          // Parse only: Function compiles the body without running it; a module's import lines are not valid there.
          const body = module ? text!.replace(/^import .* from "https:\/\/www\.gstatic\.com\/firebasejs\/[^"]+";$/gm, "") : text!;
          assert.doesNotThrow(() => new Function(module ? `return (async () => {${body}\n})` : body), `${path} ${module ? "module" : "page"} script`);
        }
      }
    });
  }
});
