import { httpFixture } from "../test/httpFixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";

test("/ops/beta carries the two e-way bill cards with every heading, button and link word from the contract", async t => {
  const f = await httpFixture(t);
  const html = await (await fetch(f.base + "/ops/beta")).text();
  const words = [
    "E-way bills to check", "Missing", "Shipper says no e-way bill is needed",
    "Open the government portal", "Mark as found on the portal", "Report a problem", "Copy", "Copied", "Select it and copy it yourself.",
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
    assert.match(address, /^https:\/\/fonts\.(googleapis|gstatic)\.com|^http:\/\/www\.w3\.org\/2000\/svg$|^https:\/\/ewaybillgst\.gov\.in$/, address);
  }
});
