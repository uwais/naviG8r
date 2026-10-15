import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";
import { handleEwayDemoPortal } from "./ewayDemoPortal.ts";

const BANNER = "naviG8r DEMO. This is a practice site, not the government e-way bill portal. Nothing here is real.";
const CONTENT_SECURITY_POLICY = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'";
const SAMPLE_GSTIN = "29ABCDE1234F1Z5";
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

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

async function get(path: string): Promise<{ status: number; headers: Headers; text: string }> {
  const response = await fetch(baseUrl + path);
  return { status: response.status, headers: response.headers, text: await response.text() };
}

async function post(path: string, fields: Record<string, string>): Promise<{ status: number; headers: Headers; text: string }> {
  const response = await fetch(baseUrl + path, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  return { status: response.status, headers: response.headers, text: await response.text() };
}

function todayInIndia(): { iso: string; words: string } {
  const iso = new Date(Date.now() + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const [year, month, day] = iso.split("-");
  return { iso, words: `${Number(day)} ${MONTH_NAMES[Number(month) - 1]} ${year}` };
}

async function generateBill(overrides: Record<string, string> = {}): Promise<{ billNumber: string; text: string }> {
  const result = await post("/demo/eway-portal/generate", {
    makerGstin: SAMPLE_GSTIN,
    invoiceNumber: "INV-2026-001",
    invoiceDate: "2026-10-14",
    transporterName: "Sample Carrier",
    ...overrides,
  });
  assert.equal(result.status, 200, result.text);
  const match = /<p class="number">(\d{4}) (\d{4}) (\d{4})<\/p>/.exec(result.text);
  assert.ok(match, "result page shows the number in groups of four");
  return { billNumber: match[1] + match[2] + match[3], text: result.text };
}

function lookupPath(number: string, billDate: string, gstin: string, invoiceNumber: string): string {
  return "/demo/eway-portal/check?" + new URLSearchParams({ number, billDate, gstin, invoiceNumber }).toString();
}

test("falls through when the switch is not 1", async () => {
  process.env.EWAY_DEMO_PORTAL = "0";
  try {
    for (const path of ["/demo/eway-portal", "/demo/eway-portal/generate", "/demo/eway-guide"]) {
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

test("every page carries the banner and the content-security-policy", async () => {
  const pages = ["/demo/eway-portal", "/demo/eway-portal/generate", "/demo/eway-portal/vehicle", "/demo/eway-portal/check", "/demo/eway-guide", "/demo/eway-portal/missing"];
  for (const path of pages) {
    const result = await get(path);
    assert.ok(result.text.includes(BANNER), `banner on ${path}`);
    assert.equal(result.headers.get("content-security-policy"), CONTENT_SECURITY_POLICY, path);
    assert.equal(result.headers.get("x-content-type-options"), "nosniff", path);
    assert.ok(!result.text.toLowerCase().includes("<script"), `no script on ${path}`);
  }
  const generated = await generateBill();
  assert.ok(generated.text.includes(BANNER));
  assert.ok(!generated.text.toLowerCase().includes("<script"));
});

test("home page has the three links", async () => {
  const home = await get("/demo/eway-portal");
  assert.equal(home.status, 200);
  assert.ok(home.text.includes("Generate a new e-way bill"));
  assert.ok(home.text.includes("Add a vehicle to a bill (Part B)"));
  assert.ok(home.text.includes("Look up a bill"));
});

test("guide has the steps and only local links", async () => {
  const guide = await get("/demo/eway-guide");
  assert.equal(guide.status, 200);
  for (const phrase of ["Before you start", "Step 1", "Step 2", "Step 3", "Step 4", "Step 5", "8000000001", "8000000003", "8000000009", "8000000005", "What is real", "What is pretend"]) {
    assert.ok(guide.text.includes(phrase), phrase);
  }
  const links = [...guide.text.matchAll(/href="([^"]*)"/g)].map((match) => match[1]);
  for (const link of links) {
    assert.ok(link.startsWith("/") || link.startsWith("http://127.0.0.1"), link);
  }
});

test("generate, add vehicle, then look up works end to end", async () => {
  const today = todayInIndia();
  const generated = await generateBill();
  const { billNumber } = generated;
  assert.match(billNumber, /^[1-9][0-9]{11}$/);
  assert.ok(generated.text.includes(`Generated on ${today.words}`));
  assert.ok(generated.text.includes(`<dd class="mono">${billNumber}</dd>`));
  assert.ok(generated.text.includes(SAMPLE_GSTIN));
  assert.ok(generated.text.includes("INV-2026-001"));
  assert.ok(generated.text.includes("Copy these four details into the naviG8r app: bill number, bill date, GSTIN, invoice number"));
  assert.ok(generated.text.includes("Part B is empty. Until a vehicle is added this bill is not valid for movement."));
  assert.ok(generated.text.includes("Go back to the naviG8r app tab and paste them there."));

  const beforeVehicle = await get(lookupPath(billNumber, today.iso, SAMPLE_GSTIN, "INV-2026-001"));
  assert.ok(beforeVehicle.text.includes("Found"));
  assert.ok(beforeVehicle.text.includes("No vehicle added yet"));

  const vehicle = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "ka 01-ab 1234", validUntil: "2099-12-31T23:59" });
  assert.equal(vehicle.status, 200, vehicle.text);
  assert.ok(vehicle.text.includes("Vehicle KA01AB1234 added. Valid until 31 Dec 2099, 23:59."));
  assert.ok(vehicle.text.includes("Copy the vehicle number and the valid-until time into the naviG8r app."));
  assert.ok(vehicle.text.includes("On the real portal only the person who made the bill, or the transporter named on it, can do this."));

  const spacedNumber = `${billNumber.slice(0, 4)} ${billNumber.slice(4, 8)} ${billNumber.slice(8)}`;
  const afterVehicle = await get(lookupPath(spacedNumber, today.iso, SAMPLE_GSTIN.toLowerCase(), "INV-2026-001"));
  assert.ok(afterVehicle.text.includes("Found"));
  assert.ok(afterVehicle.text.includes("KA01AB1234"));
  assert.ok(afterVehicle.text.includes("31 Dec 2099, 23:59"));
  assert.ok(!afterVehicle.text.includes("No vehicle added yet"));
});

test("a wrong detail on look-up names the detail that differs", async () => {
  const today = todayInIndia();
  const { billNumber } = await generateBill({ invoiceNumber: "INV-ABC" });

  const wrongInvoice = await get(lookupPath(billNumber, today.iso, SAMPLE_GSTIN, "INV-XYZ"));
  assert.ok(wrongInvoice.text.includes("No e-way bill matches these four details."));
  assert.ok(wrongInvoice.text.includes("the invoice number differs"));
  assert.ok(!wrongInvoice.text.includes("Found"));

  const wrongGstin = await get(lookupPath(billNumber, today.iso, "27ABCDE1234F1Z5", "INV-ABC"));
  assert.ok(wrongGstin.text.includes("the GSTIN differs"));

  const wrongDate = await get(lookupPath(billNumber, "2020-01-01", SAMPLE_GSTIN, "INV-ABC"));
  assert.ok(wrongDate.text.includes("the bill date differs"));

  const unknown = await get(lookupPath("999999999999", today.iso, SAMPLE_GSTIN, "INV-ABC"));
  assert.ok(unknown.text.includes("No e-way bill matches these four details."));
  assert.ok(!unknown.text.includes("The number exists"));
});

test("bad inputs get plain sentences and keep what was typed", async () => {
  const badGstin = await post("/demo/eway-portal/generate", { makerGstin: "SHORT1", invoiceNumber: "INV-KEEP", invoiceDate: "2026-10-14", transporterName: "" });
  assert.equal(badGstin.status, 400);
  assert.ok(badGstin.text.includes("The GSTIN is 15 letters and digits, for example 29ABCDE1234F1Z5."));
  assert.ok(badGstin.text.includes('value="SHORT1"'));
  assert.ok(badGstin.text.includes('value="INV-KEEP"'));

  const noInvoice = await post("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: "", invoiceDate: "2026-10-14" });
  assert.ok(noInvoice.text.includes("Type the invoice number, up to 32 characters."));

  const longInvoice = await post("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: "X".repeat(33), invoiceDate: "2026-10-14" });
  assert.ok(longInvoice.text.includes("Type the invoice number, up to 32 characters."));

  const noDate = await post("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: "INV-1", invoiceDate: "not a date" });
  assert.ok(noDate.text.includes("Choose the invoice date."));

  const { billNumber } = await generateBill();
  const unknownBill = await post("/demo/eway-portal/vehicle", { billNumber: "111111111111", vehicleNumber: "KA01AB1234", validUntil: "2099-01-01T10:00" });
  assert.ok(unknownBill.text.includes("No e-way bill with this number."));

  const badVehicle = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "AB12", validUntil: "2099-01-01T10:00" });
  assert.ok(badVehicle.text.includes("The vehicle number is 6 to 12 letters and digits"));
  assert.ok(badVehicle.text.includes('value="AB12"'));

  const pastTime = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", validUntil: "2020-01-01T10:00" });
  assert.ok(pastTime.text.includes("The valid-until time is in the past."));

  const missingTime = await post("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", validUntil: "" });
  assert.ok(missingTime.text.includes("Choose the date and time the bill is valid until."));

  const stillEmpty = await get(lookupPath(billNumber, todayInIndia().iso, SAMPLE_GSTIN, "INV-2026-001"));
  assert.ok(stillEmpty.text.includes("No vehicle added yet"), "failed vehicle attempts left Part B empty");
});

test("typed values are escaped everywhere they are printed", async () => {
  const attack = "<script>x</script>";
  const badGstin = await post("/demo/eway-portal/generate", { makerGstin: attack, invoiceNumber: "INV-1", invoiceDate: "2026-10-14" });
  assert.ok(!badGstin.text.includes(attack));
  assert.ok(!badGstin.text.toLowerCase().includes("<script"));
  assert.ok(badGstin.text.includes("&lt;SCRIPT&gt;X&lt;/SCRIPT&gt;"));

  const generated = await generateBill({ invoiceNumber: attack, transporterName: attack });
  assert.ok(!generated.text.includes(attack));
  assert.ok(!generated.text.toLowerCase().includes("<script"));
  assert.ok(generated.text.includes("&lt;script&gt;x&lt;/script&gt;"));

  const lookup = await get(lookupPath("<script>x</script>", "2026-10-14", attack, attack));
  assert.ok(!lookup.text.toLowerCase().includes("<script"));
  assert.ok(lookup.text.includes("&lt;script&gt;"));

  const vehicle = await post("/demo/eway-portal/vehicle", { billNumber: attack, vehicleNumber: attack, validUntil: attack });
  assert.ok(!vehicle.text.toLowerCase().includes("<script"));

  const quoteBreak = await get(lookupPath('"><b>', "", "", ""));
  assert.ok(!quoteBreak.text.includes('"><b>'));
});

test("a form body over 8 KB is refused, one under it is accepted", async () => {
  const tooBig = await post("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: "INV-1", invoiceDate: "2026-10-14", transporterName: "a".repeat(9000) });
  assert.equal(tooBig.status, 413);
  assert.ok(tooBig.text.includes(BANNER));
  assert.equal(tooBig.headers.get("content-security-policy"), CONTENT_SECURITY_POLICY);

  const justUnder = await post("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: "INV-1", invoiceDate: "2026-10-14", transporterName: "a".repeat(7000) });
  assert.equal(justUnder.status, 400);
  assert.ok(justUnder.text.includes("The transporter name is up to 60 characters."));
});

test("the store stops at 500 bills with a plain sentence", async () => {
  let refusedStatus = 0;
  let refusedText = "";
  for (let attempt = 0; attempt < 600 && refusedStatus === 0; attempt += 1) {
    const result = await post("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: `INV-${attempt}`, invoiceDate: "2026-10-14" });
    if (result.status === 503) {
      refusedStatus = result.status;
      refusedText = result.text;
    }
  }
  assert.equal(refusedStatus, 503);
  assert.ok(refusedText.includes("holds 500 bills and is full"));
});
