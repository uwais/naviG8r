import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { after } from "node:test";
import { fileURLToPath } from "node:url";

const practiceServerScript = fileURLToPath(new URL("../../../scripts/rbac-manual.mjs", import.meta.url));

// A stand-in for apps/driver_pilot/build/web, with the same Maps script markers as web/index.html.
const scratchDirectory = mkdtempSync(join(tmpdir(), "navig8r-practice-hosting-"));
const webDirectory = join(scratchDirectory, "web");
mkdirSync(webDirectory);
writeFileSync(join(webDirectory, "index.html"), [
  "<html><head>",
  '<script src="runtime-config.js"></script>',
  "<!-- BEGIN MAPS_API_SCRIPT -->",
  '<script src="https://maps.googleapis.com/maps/api/js?key=__MAPS_API_KEY__"></script>',
  "<!-- END MAPS_API_SCRIPT -->",
  "</head><body>fake web app</body></html>",
].join("\n"));
writeFileSync(join(webDirectory, "main.dart.js"), "console.log('fake app code');");
writeFileSync(join(scratchDirectory, "outside-the-web-folder.txt"), "not for the browser");
after(() => rmSync(scratchDirectory, { recursive: true, force: true }));

// The child gets none of this shell's secrets or settings, so a developer's own environment cannot change the result.
function practiceServerEnvironment(extra: Record<string, string>): NodeJS.ProcessEnv {
  return { PATH: process.env.PATH, HOME: process.env.HOME, TMPDIR: process.env.TMPDIR, ...extra };
}

async function startPracticeServer(extra: Record<string, string>): Promise<{ baseUrl: string; stop: () => void }> {
  const child = spawn(process.execPath, ["--experimental-strip-types", practiceServerScript], {
    env: practiceServerEnvironment({ RBAC_MANUAL_PORT: "0", RBAC_MANUAL_WEB_DIR: webDirectory, ...extra }),
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  const baseUrl = await new Promise<string>((resolveAddress, reject) => {
    const timer = setTimeout(() => reject(new Error(`practice server did not start:\n${output}`)), 20_000);
    const onData = (chunk: Buffer) => {
      output += chunk.toString();
      const address = /Open (http:\/\/[^/\s]+)\//.exec(output);
      if (address) { clearTimeout(timer); resolveAddress(address[1]!); }
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.on("exit", code => { clearTimeout(timer); reject(new Error(`practice server exited with ${code}:\n${output}`)); });
  });
  return { baseUrl, stop: () => child.kill() };
}

async function exitOfPracticeServer(extra: Record<string, string>): Promise<{ code: number | null; stderr: string }> {
  const child = spawn(process.execPath, ["--experimental-strip-types", practiceServerScript], {
    env: practiceServerEnvironment({ RBAC_MANUAL_PORT: "0", ...extra }),
    stdio: ["ignore", "ignore", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", chunk => { stderr += chunk.toString(); });
  const code = await new Promise<number | null>(resolveExit => child.on("exit", resolveExit));
  return { code, stderr };
}

test("practice server serves the web app beside the API, with mock payments and the sign-in code in the reply", async () => {
  const server = await startPracticeServer({ EWAY_DEMO_PORTAL: "1" });
  try {
    const health = await fetch(`${server.baseUrl}/api/health`);
    assert.equal(health.status, 200);
    const healthBody = await health.json();
    assert.equal(healthBody.ok, true);
    assert.equal(healthBody.paymentProvider, "mock");

    const page = await fetch(`${server.baseUrl}/`);
    assert.equal(page.status, 200);
    assert.match(page.headers.get("content-type") ?? "", /^text\/html/);
    const pageHtml = await page.text();
    assert.match(pageHtml, /fake web app/);
    assert.doesNotMatch(pageHtml, /maps\.googleapis\.com/);
    assert.match(await (await fetch(`${server.baseUrl}/runtime-config.js`)).text(), /MAPS_API_KEY: ""/);

    const appCode = await fetch(`${server.baseUrl}/main.dart.js`);
    assert.equal(appCode.status, 200);
    assert.equal(appCode.headers.get("content-type"), "text/javascript");

    // An encoded slash keeps the URL parser from folding the dots away, so this reaches the folder check.
    const outside = await fetch(`${server.baseUrl}/%2e%2e%2foutside-the-web-folder.txt`);
    assert.equal(outside.status, 404);
    assert.doesNotMatch(await outside.text(), /not for the browser/);

    const otpStart = await fetch(`${server.baseUrl}/api/v1/auth/otp/start`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "8000000001" }),
    });
    assert.equal(otpStart.status, 200);
    assert.match((await otpStart.json()).debugCode, /^\d{6}$/);

    // The ops page and the practice portal keep their own paths, outside /api.
    assert.equal((await fetch(`${server.baseUrl}/ops`)).status, 200);
    assert.equal((await fetch(`${server.baseUrl}/demo/eway-portal`)).status, 200);
  } finally {
    server.stop();
  }
});

test("practice server writes the Maps key into the page when MAPS_API_KEY is set", async () => {
  const server = await startPracticeServer({ MAPS_API_KEY: "AIzaSyFakeKeyForThisTest_123-x" });
  try {
    const pageHtml = await (await fetch(`${server.baseUrl}/`)).text();
    assert.match(pageHtml, /maps\/api\/js\?key=AIzaSyFakeKeyForThisTest_123-x"/);
    assert.doesNotMatch(pageHtml, /__MAPS_API_KEY__/);
    assert.match(await (await fetch(`${server.baseUrl}/runtime-config.js`)).text(), /MAPS_API_KEY: "AIzaSyFakeKeyForThisTest_123-x"/);
  } finally {
    server.stop();
  }
});

for (const [unsafeSetting, environment] of [
  ["NODE_ENV is production", { NODE_ENV: "production" }],
  ["NODE_ENV is beta", { NODE_ENV: "beta" }],
  ["RAZORPAY_KEY_SECRET is set", { RAZORPAY_KEY_SECRET: "fake-secret" }],
  ["DATABASE_URL is set", { DATABASE_URL: "postgres://fake" }],
] as const) {
  test(`practice server refuses to start when ${unsafeSetting}`, async () => {
    const { code, stderr } = await exitOfPracticeServer(environment);
    assert.equal(code, 1);
    assert.match(stderr, new RegExp(`Refusing to start the practice server: ${unsafeSetting}`));
  });
}
