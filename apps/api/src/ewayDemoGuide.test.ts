import assert from "node:assert/strict";
import { createServer, request as httpRequest } from "node:http";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";
import { handleEwayDemoPortal } from "./ewayDemoPortal.ts";

type Reply = { status: number; headers: Headers; text: string };

let server: Server;
let baseUrl = "";
const originalSwitch = process.env.EWAY_DEMO_PORTAL;

before(async () => {
  process.env.EWAY_DEMO_PORTAL = "1";
  server = createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    handleEwayDemoPortal(req, res, url).then((handled) => {
      if (!handled) {
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("fall-through");
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(async () => {
  if (originalSwitch === undefined) delete process.env.EWAY_DEMO_PORTAL;
  else process.env.EWAY_DEMO_PORTAL = originalSwitch;
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

async function get(path: string): Promise<Reply> {
  const response = await fetch(baseUrl + path);
  return { status: response.status, headers: response.headers, text: await response.text() };
}

test("guide has the new steps, the rules box with sources, and only local links", async () => {
  const guide = await get("/demo/eway-guide");
  assert.equal(guide.status, 200);
  for (const phrase of ["Before you start", "Step 1", "Step 2", "Step 3", "Step 4", "Step 5", "8000000001", "8000000003", "8000000009", "8000000005",
    "Choose who you are: Supplier", "Switch user to Transporter", "reason First Time", "Verify an e-way bill", "Rules I modelled", "Notification 94/2020",
    "Notification 31/2019", "Rule 138(5) and 138(5A)", "Assumed, my reading", "What is real", "What is pretend", "no password, no captcha", "from the PIN codes",
    "This public look-up is a practice-site convenience. Who may look a bill up on the real portal is an open question.", "Tap Open the practice portal"]) {
    assert.ok(guide.text.includes(phrase), phrase);
  }
  const links = [...guide.text.matchAll(/href="([^"]*)"/g)].map((match) => match[1]);
  for (const link of links) assert.ok(link.startsWith("/") || link.startsWith("http://127.0.0.1"), link);
});

test("guide addresses follow the Host the visitor used, escaped", async () => {
  const guideFor = (host: string) => new Promise<string>((resolve, reject) => {
    const request = httpRequest(baseUrl + "/demo/eway-guide", { headers: { host } }, (response) => {
      let text = "";
      response.setEncoding("utf8");
      response.on("data", (chunk: string) => { text += chunk; });
      response.on("end", () => resolve(text));
    });
    request.on("error", reject);
    request.end();
  });
  const fromLaptop = await guideFor("192.168.1.20:3139");
  assert.ok(fromLaptop.includes("Open http://192.168.1.20:3139/demo/eway-guide to come back to this page."));
  assert.ok(fromLaptop.includes('href="http://192.168.1.20:8087/#/customer/login"'));
  assert.ok(!fromLaptop.includes("127.0.0.1"));
  const hostile = await guideFor("a\"><b>x");
  assert.ok(!hostile.includes('"><b>'), "a hostile Host is never printed raw");
});
