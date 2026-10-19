import { httpFixture } from "../test/httpFixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { ewayBillScript } from "./opsConsoleBetaEwayBills.ts";
import { FakePage } from "../test/fakePage.ts";
import type { FakeElement } from "../test/fakePage.ts";

test("/ops/beta carries the two e-way bill cards with every heading, button and link word from the contract", async t => {
  const f = await httpFixture(t);
  const html = await (await fetch(f.base + "/ops/beta")).text();
  const words = [
    "E-way bills to check", "Missing", "Shipper says no e-way bill is needed",
    "Open the government portal", "Open the practice portal", "Mark as found on the portal", "Report a problem", "Copy", "Copied", "Select it and copy it yourself.",
    "Not found on the portal", "Cancelled on the portal", "Details here do not match the portal", "Confirm problem", "Cancel",
    "E-way bill number", "Bill date", "GSTIN of whoever made the bill", "Invoice number",
    "Only OPS can check e-way bills. You hold ",
    "countEwayBills", "countEwayMissing", "ewayBillsBody", "ewayMissingBody", "ewayBillsReload", "ewayMissingReload",
    "/ops/eway-bills", "invalid_eway_check", "eway_bill_not_entered", "eway_bill_locked",
  ];
  for (const word of words) assert.ok(html.includes(word), `the page must contain: ${word}`);
  assert.ok(html.includes("target: '_blank', rel: 'noopener noreferrer'"), "the portal link opens in a new tab without handing over the page");
  assert.ok(html.includes('href="#ewayBills"') && html.includes('href="#ewayMissing"'), "jump links to both cards");
});

test("the served script has no backtick or backslash, and compiles", async t => {
  const f = await httpFixture(t);
  const html = await (await fetch(f.base + "/ops/beta")).text();
  const script = html.split("<script>")[1]?.split("</script>")[0] ?? "";
  assert.ok(script.includes("loadEwayBills"), "the e-way bill script is part of the served script");
  assert.ok(!script.includes("`"), "no backtick");
  assert.ok(!script.includes("\\"), "no backslash: the template that builds the page would silently drop it");
  assert.doesNotThrow(() => new vm.Script(script), "the script has no syntax error");
});

test("the page names no web address except Google Fonts and the government portal", async t => {
  const f = await httpFixture(t);
  const html = await (await fetch(f.base + "/ops/beta")).text();
  const addresses = new Set(html.match(/https?:\/\/[^"' )]+/g) ?? []);
  assert.ok(addresses.has("https://ewaybillgst.gov.in"));
  for (const address of addresses) {
    assert.match(address, /^https:\/\/fonts\.(googleapis|gstatic)\.com(\/|$)|^http:\/\/www\.w3\.org\/2000\/svg$|^https:\/\/ewaybillgst\.gov\.in$/, address);
  }
});

const seededPracticeBill = { kind: "BILL", billNumber: "123456789012", billDate: "2026-10-01", makerGstin: "29ABCDE1234F1Z5", invoiceNumber: "SYN/2026/001" };

/** Builds one "E-way bills to check" card with the page's own element helper and returns its portal link. */
async function checkRowLink(base: string, portalAddress: string | null, shipment: unknown): Promise<FakeElement> {
  const html = await (await fetch(base + "/ops/beta")).text();
  const element = /function element\(tag, props, \.\.\.children\) \{[\s\S]*?\n\}/.exec(html)?.[0];
  assert.ok(element, "the page defines its element helper");
  const page = new FakePage(base);
  page.run("const byId = id => document.getElementById(id);\n" + element + ewayBillScript);
  if (portalAddress) page.run("ewayPortalAddress = " + JSON.stringify(portalAddress));
  const checkRow = page.run("ewayCheckRow") as (shipment: unknown) => FakeElement;
  return checkRow(shipment).descendants().find(node => node.tagName === "a")!;
}
function portalLink(base: string, portalAddress: string | null, bill: Record<string, string>): Promise<FakeElement> {
  return checkRowLink(base, portalAddress, { id: "load-a-with-bill", customerOrgName: "Synthetic Shipper A", pickupAddress: "A", dropAddress: "B", ewayBill: bill });
}

test("the practice portal link opens its Verify page with the bill's four details, and that page finds the bill", async t => {
  const f = await httpFixture(t);
  const before = process.env.EWAY_DEMO_PORTAL;
  process.env.EWAY_DEMO_PORTAL = "1";
  t.after(() => { if (before === undefined) delete process.env.EWAY_DEMO_PORTAL; else process.env.EWAY_DEMO_PORTAL = before; });

  const link = await portalLink(f.base, "/demo/eway-portal", seededPracticeBill);
  assert.equal(link.textContent, "Open the practice portal");
  assert.equal(link.getAttribute("href"), "/demo/eway-portal/check?number=123456789012&billDate=2026-10-01&gstin=29ABCDE1234F1Z5&invoiceNumber=SYN%2F2026%2F001");
  const verify = await fetch(f.base + link.getAttribute("href"));
  const text = await verify.text();
  assert.equal(verify.status, 200);
  assert.ok(text.includes("Found (practice site)"), "the Verify page looks the bill up straight away");
  assert.ok(text.includes('value="SYN/2026/001"'), "and shows the details it was given");

  const odd = await portalLink(f.base, "/demo/eway-portal", { ...seededPracticeBill, invoiceNumber: 'A&B"<i>' });
  assert.ok(odd.getAttribute("href")!.endsWith("&invoiceNumber=A%26B%22%3Ci%3E"), "every detail is encoded in the link");
  const oddText = await (await fetch(f.base + odd.getAttribute("href"))).text();
  assert.ok(oddText.includes('value="A&amp;B&quot;&lt;i&gt;"') && !oddText.includes("<i>"), "and escaped on the Verify page");
});

test("the government portal link stays the portal's own address", async t => {
  const f = await httpFixture(t);
  const link = await portalLink(f.base, null, seededPracticeBill);
  assert.equal(link.textContent, "Open the government portal");
  assert.equal(link.getAttribute("href"), "https://ewaybillgst.gov.in");
});

test("the practice link is built from what OPS really gets from /ops/eway-bills", async t => {
  const f = await httpFixture(t);
  const before = process.env.EWAY_DEMO_PORTAL;
  process.env.EWAY_DEMO_PORTAL = "1";
  t.after(() => { if (before === undefined) delete process.env.EWAY_DEMO_PORTAL; else process.env.EWAY_DEMO_PORTAL = before; });
  const id = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/shipments/${id}/eway-bill`, "POST", seededPracticeBill, f.tokens.shipperA)).status, 200);

  const reply = (await f.request("/ops/eway-bills", "GET", undefined, f.tokens.ops)).body;
  const shipment = reply.toCheck.find((s: { id: string }) => s.id === id);
  assert.ok(shipment, "OPS gets the bill to check");
  const link = await checkRowLink(f.base, reply.portalAddress, shipment);
  assert.equal(link.getAttribute("href"), "/demo/eway-portal/check?number=123456789012&billDate=2026-10-01&gstin=29ABCDE1234F1Z5&invoiceNumber=SYN%2F2026%2F001");
  assert.ok((await (await fetch(f.base + link.getAttribute("href"))).text()).includes("Found (practice site)"));
});

test("a bill missing some details leaves them out of the practice link rather than writing 'undefined'", async t => {
  const f = await httpFixture(t);
  const { makerGstin, invoiceNumber, ...older } = seededPracticeBill;
  const link = await portalLink(f.base, "/demo/eway-portal", older);
  assert.equal(link.getAttribute("href"), "/demo/eway-portal/check?number=123456789012&billDate=2026-10-01");
});
