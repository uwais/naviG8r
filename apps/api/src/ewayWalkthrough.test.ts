import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { connect } from "node:net";
import type { Socket } from "node:net";
import { httpFixture } from "../test/httpFixtures.ts";
import { FORM_BODY_TIMEOUT_MS } from "./ewayDemoPortal.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

const INDIA_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const MONTH_NUMBERS: Record<string, string> = { Jan: "01", Feb: "02", Mar: "03", Apr: "04", May: "05", Jun: "06", Jul: "07", Aug: "08", Sep: "09", Oct: "10", Nov: "11", Dec: "12" };
const SAMPLE_GSTIN = "29ABCDE1234F1Z5";
const INVOICE_NUMBER = "SYN/2026/101";

/** The portal's vehicle form takes a datetime-local value read as India time. */
function indiaDateTimeLocal(utcMs: number): string {
  return new Date(utcMs + INDIA_OFFSET_MS).toISOString().slice(0, 16);
}

/** "14 Oct 2026" as the portal prints it, back to the YYYY-MM-DD the app takes. */
function isoFromPortalDay(words: string): string {
  const [day, month, year] = words.split(" ");
  return `${year}-${MONTH_NUMBERS[month]}-${day.padStart(2, "0")}`;
}

test("the demo guide's order works end to end over HTTP, and the portal is off without the switch", async t => {
  const originalSwitch = process.env.EWAY_DEMO_PORTAL;
  process.env.EWAY_DEMO_PORTAL = "1";
  t.after(() => {
    if (originalSwitch === undefined) delete process.env.EWAY_DEMO_PORTAL;
    else process.env.EWAY_DEMO_PORTAL = originalSwitch;
  });
  const f = await httpFixture(t);
  const portalGet = async (path: string) => {
    const response = await fetch(f.base + path);
    return { status: response.status, text: await response.text() };
  };
  const portalPost = async (path: string, fields: Record<string, string>) => {
    const response = await fetch(f.base + path, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(fields).toString() });
    return { status: response.status, text: await response.text() };
  };

  const guide = await portalGet("/demo/eway-guide");
  assert.equal(guide.status, 200);
  assert.ok(guide.text.includes("/demo/eway-portal/check"), "the guide links the look-up page");

  // Shipper books, carrier accepts.
  const booking = await f.book(); assert.equal(booking.status, 201);
  const id = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);

  // Shipper generates the bill on the practice portal and reads the number and date off the page.
  const generated = await portalPost("/demo/eway-portal/generate", { makerGstin: SAMPLE_GSTIN, invoiceNumber: INVOICE_NUMBER, invoiceDate: "2026-10-14", transporterName: "Synthetic Carrier A" });
  assert.equal(generated.status, 200, generated.text);
  const numberMatch = /<p class="number">(\d{4}) (\d{4}) (\d{4})<\/p>/.exec(generated.text);
  const dateMatch = /Generated on (\d{1,2} [A-Z][a-z]{2} \d{4})/.exec(generated.text);
  assert.ok(numberMatch && dateMatch, "the result page shows the number and the Generated on date");
  const billNumber = numberMatch[1] + numberMatch[2] + numberMatch[3];
  const billDate = isoFromPortalDay(dateMatch[1]);

  const saved = await f.request(`/shipments/${id}/eway-bill`, "POST", { kind: "BILL", billNumber, billDate, makerGstin: SAMPLE_GSTIN, invoiceNumber: INVOICE_NUMBER }, f.tokens.shipperA);
  assert.equal(saved.status, 200, JSON.stringify(saved.body));

  const opsLists = await f.request("/ops/eway-bills", "GET", undefined, f.tokens.ops);
  assert.ok((opsLists.body.toCheck as Array<{ id: string }>).some(s => s.id === id), "ops lists the bill under toCheck");

  // Carrier adds the truck on the portal, then the same truck in the app.
  const validUntilUtcMs = Math.floor((Date.now() + 24 * 60 * 60 * 1000) / 60000) * 60000;
  const vehicle = await portalPost("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", validUntil: indiaDateTimeLocal(validUntilUtcMs) });
  assert.equal(vehicle.status, 200, vehicle.text);
  assert.ok(vehicle.text.includes("Vehicle KA01AB1234 added."));
  const truck = await f.request(`/v1/pilot/carrier/shipments/${id}/eway-bill/truck`, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs }, f.tokens.carrierA);
  assert.equal(truck.status, 200, JSON.stringify(truck.body));

  // The driver reads the bill, truck and valid-until, and cannot add a truck.
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "TEST-D", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const driverToken = await f.login("8000000013");
  const driverList = await f.request("/v1/pilot/carrier/shipments", "GET", undefined, driverToken);
  const driverSees = (driverList.body.shipments as Array<{ id: string; ewayBill?: Record<string, unknown> }>).find(s => s.id === id)!.ewayBill!;
  assert.deepEqual([driverSees.billNumber, driverSees.truckNumber, driverSees.validUntilUtcMs], [billNumber, "KA01AB1234", validUntilUtcMs]);
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/eway-bill/truck`, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs }, driverToken)).status, 403, "the driver reads only");

  // Ops looks the four details up on the portal, then records what it saw.
  const lookup = await portalGet("/demo/eway-portal/check?" + new URLSearchParams({ number: billNumber, billDate, gstin: SAMPLE_GSTIN, invoiceNumber: INVOICE_NUMBER }).toString());
  assert.equal(lookup.status, 200);
  assert.ok(lookup.text.includes("<h2>Found (practice site)</h2>"), lookup.text);
  assert.ok(lookup.text.includes("KA01AB1234"), "the look-up shows the vehicle");
  const checked = await f.request(`/ops/eway-bills/${id}/check`, "POST", { result: "FOUND", billNumber }, f.tokens.ops);
  assert.equal(checked.status, 200, JSON.stringify(checked.body));

  const shipperView = (await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperA)).body.shipment.ewayBill;
  assert.equal(shipperView.check.result, "FOUND");
  assert.equal(shipperView.truckNumber, "KA01AB1234");

  // The seeded bill from the demo script is known to the portal.
  const seeded = await portalGet("/demo/eway-portal/check?" + new URLSearchParams({ number: "123456789012", billDate: "2026-10-01", gstin: SAMPLE_GSTIN, invoiceNumber: "SYN/2026/001" }).toString());
  assert.ok(seeded.text.includes("<h2>Found (practice site)</h2>"), "the seeded bill is found");

  delete process.env.EWAY_DEMO_PORTAL;
  for (const path of ["/demo/eway-portal", "/demo/eway-portal/check", "/demo/eway-guide"]) {
    assert.equal((await portalGet(path)).status, 404, `${path} is off without the switch`);
  }
});

test("a portal form that stalls mid-body does not hold up other requests, and is closed after the timeout", async t => {
  const originalSwitch = process.env.EWAY_DEMO_PORTAL;
  const originalTimeout = process.env.EWAY_DEMO_PORTAL_BODY_TIMEOUT_MS;
  process.env.EWAY_DEMO_PORTAL = "1";
  process.env.EWAY_DEMO_PORTAL_BODY_TIMEOUT_MS = "1500";
  const sockets: Socket[] = [];
  t.after(() => {
    for (const socket of sockets) socket.destroy();
    if (originalSwitch === undefined) delete process.env.EWAY_DEMO_PORTAL;
    else process.env.EWAY_DEMO_PORTAL = originalSwitch;
    if (originalTimeout === undefined) delete process.env.EWAY_DEMO_PORTAL_BODY_TIMEOUT_MS;
    else process.env.EWAY_DEMO_PORTAL_BODY_TIMEOUT_MS = originalTimeout;
  });
  assert.equal(FORM_BODY_TIMEOUT_MS, 5000, "the real timeout is 5 seconds; this test shortens it");
  const f = await httpFixture(t);

  const stalled = connect(Number(new URL(f.base).port), "127.0.0.1");
  sockets.push(stalled);
  await once(stalled, "connect");
  const closed = once(stalled, "close");
  const sentAt = Date.now();
  stalled.write("POST /demo/eway-portal/generate HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 100\r\n\r\nm");
  await new Promise(resolve => setTimeout(resolve, 100));

  const otherStartedAt = Date.now();
  const health = await f.request("/health");
  assert.equal(health.status, 200);
  assert.ok(Date.now() - otherStartedAt < 1000, "another route answers while the portal body is still trickling in");

  await closed;
  assert.ok(Date.now() - sentAt < 1500 + 1000, "the stalled body is closed shortly after the timeout");
});
