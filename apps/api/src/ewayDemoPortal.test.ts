import assert from "node:assert/strict";
import { createServer, request as httpRequest } from "node:http";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";
import { SEEDED_TRUCK_VALID_UNTIL_UTC_MS, handleEwayDemoPortal } from "./ewayDemoPortal.ts";
import { formatIndiaDateTime } from "./ewayDemoPortalPages.ts";
import { validUpToUtcMs } from "./ewayDemoPortalRules.ts";
import { findBill } from "./ewayDemoPortalStore.ts";

const BANNER = "naviG8r DEMO. This is a practice site, not the government e-way bill portal. Nothing here is real.";
const CONTENT_SECURITY_POLICY = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'";
const SUPPLIER_GSTIN = "29ABCDE1234F1Z5";
const TRANSPORTER_ID = "29TRNSP1234A1Z7";
const HOUR_MS = 60 * 60 * 1000;

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

async function get(path: string, cookie = ""): Promise<Reply> {
  const response = await fetch(baseUrl + path, { headers: cookie ? { cookie } : {} });
  return { status: response.status, headers: response.headers, text: await response.text() };
}

async function post(path: string, fields: Record<string, string>, cookie = ""): Promise<Reply> {
  const response = await fetch(baseUrl + path, {
    method: "POST",
    redirect: "manual",
    headers: { "content-type": "application/x-www-form-urlencoded", ...(cookie ? { cookie } : {}) },
    body: new URLSearchParams(fields).toString(),
  });
  return { status: response.status, headers: response.headers, text: await response.text() };
}

async function signIn(persona: "supplier" | "transporter" | "other"): Promise<string> {
  const reply = await post("/demo/eway-portal/sign-in", { persona });
  assert.equal(reply.status, 303);
  const setCookie = reply.headers.get("set-cookie") ?? "";
  return setCookie.split(";")[0];
}

function billFields(overrides: Record<string, string> = {}): Record<string, string> {
  return {
    supplierGstin: SUPPLIER_GSTIN, recipientGstin: "33AAACT5678L1Z2", dispatchPin: "560099", deliveryPin: "600032",
    documentNumber: "SYN/2026/101", documentDate: "2026-10-01", goodsValueRupees: "75000", hsnCode: "8471",
    transportReason: "Supply", distanceKm: "350", vehicleNumber: "", transporterId: TRANSPORTER_ID, ...overrides,
  };
}

async function generateBill(cookie: string, overrides: Record<string, string> = {}): Promise<{ billNumber: string; text: string }> {
  const reply = await post("/demo/eway-portal/generate", billFields(overrides), cookie);
  assert.equal(reply.status, 200, reply.text);
  const match = /<p class="number">(\d{4}) (\d{4}) (\d{4})<\/p>/.exec(reply.text);
  assert.ok(match, "result page shows the number in groups of four");
  return { billNumber: match[1] + match[2] + match[3], text: reply.text };
}

function todayInIndia(): string {
  return new Date(Date.now() + 5.5 * HOUR_MS).toISOString().slice(0, 10);
}

function verifyPath(number: string, billDate: string, gstin: string, invoiceNumber: string): string {
  return "/demo/eway-portal/check?" + new URLSearchParams({ number, billDate, gstin, invoiceNumber }).toString();
}

test("falls through when the switch is not 1, read at call time", async () => {
  process.env.EWAY_DEMO_PORTAL = "0";
  try {
    for (const path of ["/demo/eway-portal", "/demo/eway-portal/sign-in", "/demo/eway-guide"]) {
      const result = await get(path);
      assert.equal(result.status, 404);
      assert.equal(result.text, "fall-through");
    }
  } finally {
    process.env.EWAY_DEMO_PORTAL = "1";
  }
});

test("falls through for paths outside the practice site", async () => {
  for (const path of ["/", "/health", "/demo", "/demo/other", "/demo/eway-guides", "/ops/beta"]) {
    const result = await get(path);
    assert.equal(result.status, 404, path);
    assert.equal(result.text, "fall-through", path);
    assert.equal(result.headers.get("content-security-policy"), null, path);
  }
});

test("every page carries the banner, the signed-in line, the content-security-policy and no script", async () => {
  const supplier = await signIn("supplier");
  const pages = ["/demo/eway-portal", "/demo/eway-portal/sign-in", "/demo/eway-portal/generate", "/demo/eway-portal/vehicle",
    "/demo/eway-portal/extend", "/demo/eway-portal/cancel", "/demo/eway-portal/check", "/demo/eway-portal/bill?number=123456789012",
    "/demo/eway-guide", "/demo/eway-portal/missing"];
  for (const path of pages) {
    for (const cookie of ["", supplier]) {
      const result = await get(path, cookie);
      assert.ok(result.text.includes(BANNER), `banner on ${path}`);
      assert.equal(result.headers.get("content-security-policy"), CONTENT_SECURITY_POLICY, path);
      assert.equal(result.headers.get("x-content-type-options"), "nosniff", path);
      assert.ok(!result.text.toLowerCase().includes("<script"), `no script on ${path}`);
      assert.ok(result.text.includes(cookie ? "Signed in as Supplier: Synthetic Shipper A" : "Not signed in."), `who is signed in on ${path}`);
      assert.ok(result.text.includes(cookie ? "Switch user" : "Choose who you are"), path);
    }
  }
});

test("sign-in sets an HttpOnly, SameSite=Lax cookie scoped to /demo, and says there is no password", async () => {
  const page = await get("/demo/eway-portal/sign-in");
  assert.ok(page.text.includes("no password and no captcha"));
  for (const words of ["Supplier: Synthetic Shipper A", "Transporter: Synthetic Carrier A", "Someone else: Synthetic Other Business", TRANSPORTER_ID, "07OTHER1234B1Z2"]) {
    assert.ok(page.text.includes(words), words);
  }
  const reply = await post("/demo/eway-portal/sign-in", { persona: "transporter" });
  assert.equal(reply.status, 303);
  assert.equal(reply.headers.get("location"), "/demo/eway-portal");
  assert.equal(reply.headers.get("set-cookie"), "eway_demo_persona=transporter; Path=/demo; HttpOnly; SameSite=Lax");
  assert.equal(reply.headers.get("content-security-policy"), CONTENT_SECURITY_POLICY);
  const home = await get("/demo/eway-portal", "eway_demo_persona=transporter");
  assert.ok(home.text.includes(`Signed in as Transporter: Synthetic Carrier A (Transporter ID <span class="mono">${TRANSPORTER_ID}</span>)`));

  const unknown = await post("/demo/eway-portal/sign-in", { persona: "admin" });
  assert.equal(unknown.status, 400);
  assert.equal(unknown.headers.get("set-cookie"), null);

  const forged = await get("/demo/eway-portal", "eway_demo_persona=<b>admin</b>");
  assert.ok(forged.text.includes("Not signed in."), "an unknown cookie value is signed out");
  assert.ok(!forged.text.includes("<b>admin"), "the cookie value is never printed");
});

test("generating needs a sign-in, and Someone else is refused", async () => {
  const noCookie = await post("/demo/eway-portal/generate", billFields());
  assert.equal(noCookie.status, 401);
  assert.ok(noCookie.text.includes("Choose who you are first"));
  const other = await signIn("other");
  const refused = await post("/demo/eway-portal/generate", billFields({ supplierGstin: "07OTHER1234B1Z2" }), other);
  assert.equal(refused.status, 403);
  assert.ok(refused.text.includes("Practice rule: Only the supplier or a transporter can generate an e-way bill here."), "rules stated as fact carry the practice prefix");
  assert.equal((await get("/demo/eway-portal/generate", other)).status, 403);
});

test("a bill with a named transporter and no vehicle is not valid for movement; with a vehicle, validity starts now", async () => {
  const supplier = await signIn("supplier");
  const form = await get("/demo/eway-portal/generate", supplier);
  assert.ok(form.text.includes(`value="${SUPPLIER_GSTIN}"`), "A.1 starts as the supplier's own GSTIN");
  for (const label of ["A.1 GSTIN of Supplier", "A.2 Place of Dispatch", "A.3 GSTIN of Recipient", "A.4 Place of Delivery", "A.5 Document Number",
    "A.6 Document Date", "A.7 Value of Goods", "A.8 HSN Code", "A.9 Reason for Transportation", "B.1 Vehicle Number for Road", "Approximate distance", "Transporter ID"]) {
    assert.ok(form.text.includes(label), label);
  }
  assert.ok(form.text.includes("The real portal works this out from the two PIN codes. Here you type it."));

  const noVehicle = await generateBill(supplier);
  assert.match(noVehicle.billNumber, /^[1-9][0-9]{11}$/);
  assert.ok(noVehicle.text.includes("Part B not entered: not valid for movement"));
  assert.ok(!noVehicle.text.includes("Valid up to"));
  assert.ok(noVehicle.text.includes("<h2>Practice bill, not a real e-way bill</h2>"));
  assert.ok(noVehicle.text.includes(`(${todayInIndia()})`), "the bill date is today in India");
  assert.ok(noVehicle.text.includes("Transporter named on the bill: Synthetic Carrier A"));
  assert.ok(noVehicle.text.includes("Copy these four details into the naviG8r app: bill number, bill date, supplier GSTIN, document number"));

  const startedAt = Date.now();
  const withVehicle = await generateBill(supplier, { vehicleNumber: "ka 01-ab 1234", transporterId: "", distanceKm: "201" });
  assert.ok(withVehicle.text.includes(`Valid up to ${formatIndiaDateTime(validUpToUtcMs(startedAt, 201))} (India time)`));
  assert.ok(withVehicle.text.includes("No transporter is named on this bill."));

  const neither = await post("/demo/eway-portal/generate", billFields({ transporterId: "" }), supplier);
  assert.equal(neither.status, 400);
  assert.ok(neither.text.includes("Enter B.1 Vehicle Number, or name a Transporter ID"));
  const notOwnGstin = await post("/demo/eway-portal/generate", billFields({ supplierGstin: "27ABCDE1234F1Z5", documentNumber: "KEEP-ME" }), supplier);
  assert.ok(notOwnGstin.text.includes(`A.1 must be your own GSTIN, ${SUPPLIER_GSTIN}.`));
  assert.ok(notOwnGstin.text.includes('value="KEEP-ME"'), "what was typed is kept");
});

test("a transporter can generate for a supplier and is named on the bill", async () => {
  const transporter = await signIn("transporter");
  const generated = await generateBill(transporter, { transporterId: "" });
  assert.ok(generated.text.includes(`Transporter named on the bill: Synthetic Carrier A (<span class="mono">${TRANSPORTER_ID}</span>)`));
});

test("vehicle update: the named transporter sets validity, the supplier is then refused, a change keeps validity", async () => {
  const supplier = await signIn("supplier");
  const transporter = await signIn("transporter");
  const other = await signIn("other");
  const { billNumber } = await generateBill(supplier, { distanceKm: "450" });

  const refusedOther = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", reasonCode: "4" }, other);
  assert.equal(refusedOther.status, 403);
  assert.ok(refusedOther.text.includes("Only whoever generated this bill, or the transporter it names, can update its vehicle."));
  const wrongReason = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", reasonCode: "1" }, transporter);
  assert.ok(wrongReason.text.includes("This bill has no vehicle yet. Practice rule: Choose First Time as the reason."));

  const startedAt = Date.now();
  const first = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", reasonCode: "4" }, transporter);
  assert.equal(first.status, 200, first.text);
  const validUpTo = formatIndiaDateTime(validUpToUtcMs(startedAt, 450));
  assert.ok(first.text.includes(`Vehicle KA01AB1234. Valid up to ${validUpTo} (India time).`));

  const supplierAfter = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA02CD5678", reasonCode: "1" }, supplier);
  assert.equal(supplierAfter.status, 403);
  assert.ok(supplierAfter.text.includes("The transporter has already updated the vehicle on this bill. Practice rule: After that, the supplier can no longer change it."));

  const othersNoRemark = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA02CD5678", reasonCode: "3", remark: "" }, transporter);
  assert.ok(othersNoRemark.text.includes("With Others as the reason, write a remark"));
  const breakDown = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA02CD5678", reasonCode: "1" }, transporter);
  assert.equal(breakDown.status, 200);
  assert.ok(breakDown.text.includes(`Vehicle KA02CD5678. Valid up to ${validUpTo} (India time).`), "a change keeps the validity");

  const detail = await get(`/demo/eway-portal/bill?number=${billNumber}`, supplier);
  assert.equal(detail.status, 200);
  assert.ok(detail.text.includes("KA01AB1234</span>, First Time, by the transporter"));
  assert.ok(detail.text.includes("KA02CD5678</span>, Break Down, by the transporter"));
});

test("extension: refused before expiry, allowed in the eight hours after, refused later", async () => {
  const supplier = await signIn("supplier");
  const transporter = await signIn("transporter");
  const { billNumber } = await generateBill(supplier);
  await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", reasonCode: "4" }, transporter);
  const extendFields = { billNumber, reasonCode: "ACCIDENT", remark: "", remainingDistanceKm: "120" };

  const early = await post("/demo/eway-portal/extend", extendFields, transporter);
  assert.equal(early.status, 403);
  assert.ok(early.text.includes("This bill has not expired yet. Practice rule: A bill can be extended only in the eight hours after it expires."));

  const bill = findBill(billNumber);
  assert.ok(bill);
  bill.validUpToUtcMs = Date.now() - HOUR_MS;
  const bySupplier = await post("/demo/eway-portal/extend", extendFields, supplier);
  assert.ok(bySupplier.text.includes("Only the transporter named on this bill, after it has updated the vehicle, can extend it."));
  const startedAt = Date.now();
  const extended = await post("/demo/eway-portal/extend", extendFields, transporter);
  assert.equal(extended.status, 200, extended.text);
  assert.ok(extended.text.includes(`Valid up to ${formatIndiaDateTime(validUpToUtcMs(startedAt, 120))} (India time).`));

  bill.validUpToUtcMs = Date.now() - 9 * HOUR_MS;
  const late = await post("/demo/eway-portal/extend", extendFields, transporter);
  assert.equal(late.status, 403);
  assert.ok(late.text.includes("The eight hours after this bill expired have passed. Practice rule: After that, it can no longer be extended."));
});

test("cancel: the generator within 24 hours; a cancelled bill shows Cancelled everywhere", async () => {
  const supplier = await signIn("supplier");
  const transporter = await signIn("transporter");
  const { billNumber } = await generateBill(supplier, { documentNumber: "CANCEL-ME" });
  const byTransporter = await post("/demo/eway-portal/cancel", { billNumber }, transporter);
  assert.equal(byTransporter.status, 403);
  assert.ok(byTransporter.text.includes("Only whoever generated this bill can cancel it."));
  const cancelled = await post("/demo/eway-portal/cancel", { billNumber }, supplier);
  assert.equal(cancelled.status, 200);
  assert.ok(cancelled.text.includes("is now Cancelled"));

  const verified = await get(verifyPath(billNumber, todayInIndia(), SUPPLIER_GSTIN, "CANCEL-ME"));
  assert.ok(verified.text.includes("<h2>Cancelled (practice site)</h2>"));
  assert.ok(!verified.text.includes("Found (practice site)"));
  assert.ok((await get(`/demo/eway-portal/bill?number=${billNumber}`, supplier)).text.includes("<strong>Cancelled</strong>"));
  const vehicle = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", reasonCode: "4" }, transporter);
  assert.ok(vehicle.text.includes("This bill was cancelled."));

  const seededTooOld = await post("/demo/eway-portal/cancel", { billNumber: "123456789012" }, supplier);
  assert.ok(seededTooOld.text.includes("more than 24 hours ago"));
});

test("bill details go to its parties only", async () => {
  const other = await signIn("other");
  const refused = await get("/demo/eway-portal/bill?number=123456789012", other);
  assert.equal(refused.status, 403);
  assert.ok(refused.text.includes("Only the supplier on this bill and the transporter it names can see its details. You are neither."));
  assert.ok(!refused.text.includes("SYN/2026/001"));
  assert.equal((await get("/demo/eway-portal/bill?number=123456789012")).status, 401);
  const transporterView = await get("/demo/eway-portal/bill?number=1234 5678 9012", await signIn("transporter"));
  assert.equal(transporterView.status, 200);
  assert.ok(transporterView.text.includes("Part B not entered: not valid for movement"));
  assert.ok(transporterView.text.includes("No vehicle entered yet."));
});

test("verify: Found with vehicle and valid up to, the one differing detail named, and the seeded bills", async () => {
  const page = await get("/demo/eway-portal/check");
  assert.ok(page.text.includes("This public look-up is a practice-site convenience. Who may look a bill up on the real portal is an open question."));

  const seededTruck = await get(verifyPath("2345 6789 0123", "2026-10-02", SUPPLIER_GSTIN.toLowerCase(), "SYN/2026/002"));
  assert.ok(seededTruck.text.includes("<h2>Found (practice site)</h2>"));
  assert.ok(seededTruck.text.includes("KA01AB1234"));
  assert.ok(seededTruck.text.includes(`Valid up to ${formatIndiaDateTime(SEEDED_TRUCK_VALID_UNTIL_UTC_MS)} (India time)`), "matches the seed script's export");

  const seeded = await get(verifyPath("123456789012", "2026-10-01", SUPPLIER_GSTIN, "SYN/2026/001"));
  assert.ok(seeded.text.includes("<h2>Found (practice site)</h2>"));
  assert.ok(seeded.text.includes("No vehicle added yet"));
  assert.ok(seeded.text.includes("Part B not entered: not valid for movement"));

  const oneDiffers = await get(verifyPath("123456789012", "2026-10-01", SUPPLIER_GSTIN, "SYN/2026/999"));
  assert.ok(oneDiffers.text.includes("No match. No e-way bill matches these four details. The number exists, but the document number differs."));
  const dateDiffers = await get(verifyPath("123456789012", "2020-01-01", SUPPLIER_GSTIN, "SYN/2026/001"));
  assert.ok(dateDiffers.text.includes("the bill date differs"));
  const twoDiffer = await get(verifyPath("123456789012", "2020-01-01", SUPPLIER_GSTIN, "SYN/2026/999"));
  assert.ok(twoDiffer.text.includes("No match."));
  assert.ok(!twoDiffer.text.includes("The number exists"));
  const unknown = await get(verifyPath("999999999999", "2026-10-01", SUPPLIER_GSTIN, "SYN/2026/001"));
  assert.ok(unknown.text.includes("No match."));
  assert.ok(!unknown.text.includes("The number exists"));
});

test("typed values are escaped everywhere they are printed", async () => {
  const attack = "<script>x</script>";
  const supplier = await signIn("supplier");
  const transporter = await signIn("transporter");
  const badGstin = await post("/demo/eway-portal/generate", billFields({ supplierGstin: attack }), supplier);
  assert.ok(!badGstin.text.toLowerCase().includes("<script"));
  assert.ok(badGstin.text.includes("&lt;SCRIPT&gt;X&lt;/SCRIPT&gt;"));

  const generated = await generateBill(supplier, { documentNumber: attack });
  assert.ok(!generated.text.toLowerCase().includes("<script"));
  assert.ok(generated.text.includes("&lt;script&gt;x&lt;/script&gt;"));

  const remark = await post("/demo/eway-portal/vehicle", { billNumber: generated.billNumber, vehicleNumber: "KA01AB1234", reasonCode: "4", remark: "<b>x</b>" }, transporter);
  assert.equal(remark.status, 200);
  const detail = await get(`/demo/eway-portal/bill?number=${generated.billNumber}`, supplier);
  assert.ok(!detail.text.toLowerCase().includes("<script"));
  assert.ok(detail.text.includes("(&lt;b&gt;x&lt;/b&gt;)"));

  const lookup = await get(verifyPath(attack, "2026-10-14", attack, attack));
  assert.ok(!lookup.text.toLowerCase().includes("<script"));
  for (const path of ["/demo/eway-portal/vehicle", "/demo/eway-portal/extend", "/demo/eway-portal/cancel"]) {
    const reply = await post(path, { billNumber: attack, vehicleNumber: attack, reasonCode: attack, remark: attack, remainingDistanceKm: attack }, transporter);
    assert.ok(!reply.text.toLowerCase().includes("<script"), path);
  }
  const quoteBreak = await get(verifyPath('"><b>', "", "", ""));
  assert.ok(!quoteBreak.text.includes('"><b>'));
});

test("a form body over 8 KB is refused, one under it is read", async () => {
  const supplier = await signIn("supplier");
  const tooBig = await post("/demo/eway-portal/generate", billFields({ documentNumber: "a".repeat(9000) }), supplier);
  assert.equal(tooBig.status, 413);
  assert.ok(tooBig.text.includes(BANNER));
  assert.equal(tooBig.headers.get("content-security-policy"), CONTENT_SECURITY_POLICY);
  const tooBigSignedOut = await post("/demo/eway-portal/generate", billFields({ documentNumber: "a".repeat(9000) }));
  assert.equal(tooBigSignedOut.status, 413, "the size cap applies before the sign-in check");

  const justUnder = await post("/demo/eway-portal/generate", billFields({ documentNumber: "a".repeat(7000) }), supplier);
  assert.equal(justUnder.status, 400);
  assert.ok(justUnder.text.includes("A.5 Document Number is up to 32 characters."));
});

test("guide has the new steps, the rules box with sources, and only local links", async () => {
  const guide = await get("/demo/eway-guide");
  assert.equal(guide.status, 200);
  for (const phrase of ["Before you start", "Step 1", "Step 2", "Step 3", "Step 4", "Step 5", "8000000001", "8000000003", "8000000009", "8000000005",
    "Choose who you are: Supplier", "Switch user to Transporter", "reason First Time", "Verify an e-way bill", "Rules I modelled", "Notification 94/2020",
    "Notification 31/2019", "Rule 138(5) and 138(5A)", "Assumed, my reading", "What is real", "What is pretend", "no password, no captcha", "from the PIN codes"]) {
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

test("past 500 bills the oldest is dropped, never a seeded one, and generating keeps working", async () => {
  const supplier = await signIn("supplier");
  const today = todayInIndia();
  const oldest = await generateBill(supplier, { documentNumber: "INV-OLDEST" });
  let newest = "";
  for (let attempt = 0; attempt < 500; attempt += 1) {
    newest = (await generateBill(supplier, { documentNumber: `INV-${attempt}` })).billNumber;
  }
  const oldestLookup = await get(verifyPath(oldest.billNumber, today, SUPPLIER_GSTIN, "INV-OLDEST"));
  assert.ok(oldestLookup.text.includes("No match."), "the oldest bill was dropped");
  assert.ok((await get(verifyPath(newest, today, SUPPLIER_GSTIN, "INV-499"))).text.includes("<h2>Found (practice site)</h2>"), "the newest bill is kept");
  assert.ok((await get(verifyPath("123456789012", "2026-10-01", SUPPLIER_GSTIN, "SYN/2026/001"))).text.includes("<h2>Found (practice site)</h2>"));
  assert.ok((await get(verifyPath("234567890123", "2026-10-02", SUPPLIER_GSTIN, "SYN/2026/002"))).text.includes("<h2>Found (practice site)</h2>"));
});
