import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { connect } from "node:net";
import type { Socket } from "node:net";
import { httpFixture } from "../test/httpFixtures.ts";
import { FORM_BODY_TIMEOUT_MS } from "./ewayDemoPortalForm.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

const INDIA_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const MONTH_NUMBERS: Record<string, number> = { Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6, Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12 };
const SAMPLE_GSTIN = "29ABCDE1234F1Z5";
const TRANSPORTER_ID = "29TRNSP1234A1Z7";
const INVOICE_NUMBER = "SYN/2026/101";

/** "Valid up to 17 Oct 2026, 23:59" as the portal prints it, in India time, back to UTC milliseconds for the app. */
function utcMsFromPortalValidUpTo(words: string): number {
  const match = /^(\d{1,2}) ([A-Z][a-z]{2}) (\d{4}), (\d{2}):(\d{2})$/.exec(words);
  assert.ok(match, words);
  return Date.UTC(Number(match[3]), MONTH_NUMBERS[match[2]] - 1, Number(match[1]), Number(match[4]), Number(match[5])) - INDIA_OFFSET_MS;
}

test("the demo guide's order works end to end over HTTP, and the portal is off without the switch", async t => {
  const originalSwitch = process.env.EWAY_DEMO_PORTAL;
  process.env.EWAY_DEMO_PORTAL = "1";
  t.after(() => {
    if (originalSwitch === undefined) delete process.env.EWAY_DEMO_PORTAL;
    else process.env.EWAY_DEMO_PORTAL = originalSwitch;
  });
  const f = await httpFixture(t);
  const portalGet = async (path: string, cookie = "") => {
    const response = await fetch(f.base + path, { headers: cookie ? { cookie } : {} });
    return { status: response.status, text: await response.text() };
  };
  const portalPost = async (path: string, fields: Record<string, string>, cookie = "") => {
    const response = await fetch(f.base + path, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded", ...(cookie ? { cookie } : {}) }, body: new URLSearchParams(fields).toString() });
    return { status: response.status, setCookie: response.headers.get("set-cookie") ?? "", text: await response.text() };
  };
  const signIn = async (persona: string) => {
    const reply = await portalPost("/demo/eway-portal/sign-in", { persona });
    assert.equal(reply.status, 303);
    return reply.setCookie.split(";")[0];
  };

  const guide = await portalGet("/demo/eway-guide");
  assert.equal(guide.status, 200);
  assert.ok(guide.text.includes("/demo/eway-portal/check"), "the guide links the Verify page");

  // Shipper books, carrier accepts.
  const booking = await f.book(); assert.equal(booking.status, 201);
  const id = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);

  // Shipper signs in to the practice portal as the Supplier and generates the bill, naming the transporter and no vehicle.
  const supplierCookie = await signIn("supplier");
  const generated = await portalPost("/demo/eway-portal/generate", {
    supplierGstin: SAMPLE_GSTIN, recipientGstin: "33AAACT5678L1Z2", dispatchPin: "560099", deliveryPin: "600032", documentNumber: INVOICE_NUMBER,
    documentDate: "2026-10-01", goodsValueRupees: "75000", hsnCode: "8471", transportReason: "Supply", distanceKm: "450", vehicleNumber: "", transporterId: TRANSPORTER_ID,
  }, supplierCookie);
  assert.equal(generated.status, 200, generated.text);
  assert.ok(generated.text.includes("Part B not entered: not valid for movement"));
  const numberMatch = /<p class="number">(\d{4}) (\d{4}) (\d{4}) <span class="practice-mark">\(practice\)<\/span><\/p>/.exec(generated.text);
  const dateMatch = /<dt>Bill date<\/dt><dd>[^<]* \((\d{4}-\d{2}-\d{2})\)<\/dd>/.exec(generated.text);
  assert.ok(numberMatch && dateMatch, "the result page shows the number and the bill date");
  const billNumber = numberMatch[1] + numberMatch[2] + numberMatch[3];
  const billDate = dateMatch[1];

  // The shipper saves the portal's number and date in the app; the document number is the app's invoice number.
  const saved = await f.request(`/shipments/${id}/eway-bill`, "POST", { kind: "BILL", billNumber, billDate, makerGstin: SAMPLE_GSTIN, invoiceNumber: INVOICE_NUMBER }, f.tokens.shipperA);
  assert.equal(saved.status, 200, JSON.stringify(saved.body));

  const opsLists = await f.request("/ops/eway-bills", "GET", undefined, f.tokens.ops);
  assert.ok((opsLists.body.toCheck as Array<{ id: string }>).some(s => s.id === id), "ops lists the bill under toCheck");

  // The carrier only reads the bill, so it cannot add the truck in the app.
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/eway-bill/truck`, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs: Date.now() + 86400000 }, f.tokens.carrierA)).status, 403, "the carrier reads only");

  // Shipper, still the Supplier, updates the vehicle for the first time and copies the computed valid-up-to into the app.
  const vehicle = await portalPost("/demo/eway-portal/vehicle", { billNumber, vehicleNumber: "KA01AB1234", reasonCode: "4", remark: "" }, supplierCookie);
  assert.equal(vehicle.status, 200, vehicle.text);
  const validUpToMatch = /Vehicle KA01AB1234\. Valid up to (\d{1,2} [A-Z][a-z]{2} \d{4}, \d{2}:\d{2}) \(India time\)/.exec(vehicle.text);
  assert.ok(validUpToMatch, vehicle.text);
  const validUntilUtcMs = utcMsFromPortalValidUpTo(validUpToMatch[1]);
  const todayInIndia = new Date(Date.now() + INDIA_OFFSET_MS);
  assert.equal(validUntilUtcMs, Date.UTC(todayInIndia.getUTCFullYear(), todayInIndia.getUTCMonth(), todayInIndia.getUTCDate() + 3, 23, 59) - INDIA_OFFSET_MS, "450 km is three days, ending 23:59 India time");
  const truck = await f.request(`/shipments/${id}/eway-bill/truck`, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs }, f.tokens.shipperA);
  assert.equal(truck.status, 200, JSON.stringify(truck.body));

  // The owner names the driver for the trip; the driver then reads the bill, truck and valid-until, and cannot add a truck.
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "TEST-D", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const driverToken = await f.login("8000000013");
  assert.equal((await f.request("/v1/pilot/carrier/shipments", "GET", undefined, driverToken)).body.shipments.length, 0, "a driver on no trip sees nothing");
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, f.tokens.carrierA)).status, 200);
  const driverList = await f.request("/v1/pilot/carrier/shipments", "GET", undefined, driverToken);
  const driverSees = (driverList.body.shipments as Array<{ id: string; ewayBill?: Record<string, unknown> }>).find(s => s.id === id)!.ewayBill!;
  assert.deepEqual([driverSees.billNumber, driverSees.truckNumber, driverSees.validUntilUtcMs], [billNumber, "KA01AB1234", validUntilUtcMs]);
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/eway-bill/truck`, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs }, driverToken)).status, 403, "the driver reads only");

  // Ops verifies the four details on the public Verify page, with no sign-in, then records what it saw.
  const lookup = await portalGet("/demo/eway-portal/check?" + new URLSearchParams({ number: billNumber, billDate, gstin: SAMPLE_GSTIN, invoiceNumber: INVOICE_NUMBER }).toString());
  assert.equal(lookup.status, 200);
  assert.ok(lookup.text.includes("<h2>Found (practice site)</h2>"), lookup.text);
  assert.ok(lookup.text.includes("KA01AB1234"), "the look-up shows the vehicle");
  assert.ok(lookup.text.includes(`Valid up to ${validUpToMatch[1]} (India time)`), "and the same valid-up-to");
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
