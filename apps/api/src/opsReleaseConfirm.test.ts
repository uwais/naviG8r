import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";
import { addTestPodPhoto } from "../test/fixtures.ts";
import { FakePage, inlineScript } from "../test/fakePage.ts";
import type { FakeElement } from "../test/fakePage.ts";

const rupees = (paise: number) => "₹" + (paise / 100).toLocaleString("en-IN", { minimumFractionDigits: paise % 100 ? 2 : 0, maximumFractionDigits: 2 });

/** A shipment whose proof of delivery the shipper accepted, so FINANCE may release it now. */
async function readyToRelease(f: Awaited<ReturnType<typeof httpFixture>>) {
  const id = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  addTestPodPhoto(f.store, id);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperA)).status, 200);
  const credit = rupees(f.store.shipments.get(id)!.netToCarrierPaise);
  return {
    id,
    question: `Release payment for shipment ${id}? ${credit} is credited to Synthetic Carrier A's ledger and paid out in the payout batch, not sent now.`,
    result: `Payment released for shipment ${id}: ${credit} credited to Synthetic Carrier A's ledger.`,
  };
}

async function openAsFinance(f: Awaited<ReturnType<typeof httpFixture>>, path: string) {
  const page = new FakePage(f.base);
  page.session.set("navig8r_access", f.tokens.finance);
  page.run(inlineScript(await (await fetch(f.base + path)).text()));
  await page.settle();
  return page;
}

for (const path of ["/ops", "/ops/v2"]) {
  test(`${path}: Release payment first asks in the page; only Confirm release sends the money`, async t => {
    const f = await httpFixture(t);
    const { id, question, result } = await readyToRelease(f);
    const page = await openAsFinance(f, path);
    const row = page.byId("shipments").children.find(article => article.textContent.includes(id))!;
    assert.ok(row, "the ready shipment is listed");

    await page.click(page.visibleButton("Release payment", row)!);
    assert.equal(page.releaseRequests().length, 0, "the first tap sends nothing");
    assert.ok(row.textContent.includes(question), row.textContent);
    assert.equal(page.visibleButton("Release payment", row), undefined, "the button waits behind the question");
    assert.equal(page.focused?.textContent, "Cancel", "a stray Enter cancels rather than releases");
    assert.equal(page.focused?.parent?.className, "ask", "the question's buttons get the 48 px rule");

    await page.click(page.visibleButton("Cancel", row)!);
    assert.equal(row.textContent.includes(question), false, "Cancel takes the question away");
    assert.equal(page.releaseRequests().length, 0);
    assert.equal(f.store.shipments.get(id)!.status, "PENDING_RELEASE");

    await page.click(page.visibleButton("Release payment", row)!);
    await page.click(page.visibleButton("Confirm release", row)!);
    assert.deepEqual(page.releaseRequests().map(request => request.path), [`/ops/shipments/${id}/release`]);
    assert.equal(f.store.shipments.get(id)!.status, "DELIVERED");
    assert.equal(page.nativeDialogs, 0, "no browser confirm or alert");
    assert.equal(page.byId("error").textContent, "");
    assert.equal(page.focused, page.byId("released"), "focus lands on the result, not on a removed button");
    assert.equal(page.focused?.textContent, result);
  });
}

test("the question's buttons are at least 48 px tall on /ops and /ops/v1 (checked in the served CSS, not by layout)", async t => {
  const f = await httpFixture(t);
  for (const path of ["/ops", "/ops/v1"]) {
    const html = await (await fetch(f.base + path)).text();
    assert.match(html, /\.ask button\{min-height:48px\}/, path);
  }
});

test("/ops: a payment released elsewhere is not offered for release again", async t => {
  const f = await httpFixture(t);
  const { id } = await readyToRelease(f);
  const page = await openAsFinance(f, "/ops");
  const row = page.byId("shipments").children.find(article => article.textContent.includes(id))!;
  assert.equal((await f.request(`/ops/shipments/${id}/release`, "POST", {}, f.tokens.finance)).status, 200);
  await page.click(page.visibleButton("Release payment", row)!);
  assert.equal(page.byId("error").textContent, "This payment is no longer waiting for release. Reload to see where it stands.");
  assert.equal(page.visibleButton("Confirm release", row), undefined);
});

function releaseForm(page: FakePage): FakeElement {
  const form = page.byId("actions").children.find(card => card.tagName === "form" && card.children[0]?.textContent === "Release payment");
  assert.ok(form, "FINANCE sees the Release payment form");
  return form;
}
function fill(form: FakeElement, values: Record<string, string>) {
  for (const input of form.descendants()) if (input.name in values) input.value = values[input.name]!;
}

test("/ops/v1: Release payment asks in the page, not in a browser dialog, and a changed field drops the question", async t => {
  const f = await httpFixture(t);
  const { id, question, result } = await readyToRelease(f);
  const page = await openAsFinance(f, "/ops/v1");
  let form = releaseForm(page);
  fill(form, { shipmentId: id, reason: "POD_REVIEWED" });

  await page.click(page.visibleButton("Release payment", form)!);
  assert.equal(page.nativeDialogs, 0, "no window.confirm");
  assert.equal(page.releaseRequests().length, 0, "the first tap sends nothing");
  assert.ok(form.textContent.includes(question), form.textContent);
  assert.equal(page.focused?.textContent, "Cancel");

  form.oninput!({ preventDefault() {} });
  assert.equal(form.textContent.includes(question), false, "editing the shipment ID drops a question about the old one");
  assert.ok(page.visibleButton("Release payment", form));

  await page.click(page.visibleButton("Release payment", form)!);
  await page.click(page.visibleButton("Cancel", form)!);
  assert.equal(page.releaseRequests().length, 0);
  assert.equal(f.store.shipments.get(id)!.status, "PENDING_RELEASE");

  await page.click(page.visibleButton("Release payment", form)!);
  await page.click(page.visibleButton("Confirm release", form)!);
  assert.deepEqual(page.releaseRequests().map(request => request.path), [`/ops/shipments/${id}/release`]);
  assert.equal(f.store.shipments.get(id)!.status, "DELIVERED");
  assert.equal(page.byId("notice").textContent, result);
  form = releaseForm(page);
  assert.ok(page.visibleButton("Release payment", form), "the rebuilt form is ready for the next one");
});

test("/ops/v1: a shipment that is not ready, or already released, gets a plain sentence instead of the question", async t => {
  const f = await httpFixture(t);
  const held = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${held}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  addTestPodPhoto(f.store, held);
  assert.equal((await f.request(`/shipments/${held}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
  const { id: released } = await readyToRelease(f);
  assert.equal((await f.request(`/ops/shipments/${released}/release`, "POST", {}, f.tokens.finance)).status, 200);
  const page = await openAsFinance(f, "/ops/v1");
  const cases = [
    [held, `Shipment ${held} can't be released yet: the shipper must accept the proof of delivery, or the 48-hour hold must end. Nothing was released.`],
    [released, `Shipment ${released} is not waiting for payment release; it may have been released already. Nothing was released.`],
  ];
  for (const [id, sentence] of cases) {
    const form = releaseForm(page);
    fill(form, { shipmentId: id, reason: "POD_REVIEWED" });
    await page.click(page.visibleButton("Release payment", form)!);
    assert.equal(page.byId("error").textContent, sentence);
    assert.equal(page.visibleButton("Confirm release", form), undefined, "no question about money that cannot move");
    assert.ok(page.visibleButton("Release payment", form), "the form stays usable");
  }
  assert.equal(page.releaseRequests().length, 0);
});

/** After the release request is sent, every read fails, as if the network dropped once the money moved. */
function failReadsAfterRelease(page: FakePage) {
  page.run(`(() => {
    const sendRequest = fetch;
    let releaseSent = false;
    fetch = (path, init = {}) => {
      if (releaseSent && (init.method ?? "GET") === "GET") return Promise.reject(new TypeError("Failed to fetch"));
      if (path.endsWith("/release")) releaseSent = true;
      return sendRequest(path, init);
    };
  })()`);
}

for (const path of ["/ops", "/ops/v2"]) {
  test(`${path}: a release that worked is reported even when the list cannot refresh`, async t => {
    const f = await httpFixture(t);
    const { id, result } = await readyToRelease(f);
    const page = await openAsFinance(f, path);
    const row = page.byId("shipments").children.find(article => article.textContent.includes(id))!;
    failReadsAfterRelease(page);
    await page.click(page.visibleButton("Release payment", row)!);
    await page.click(page.visibleButton("Confirm release", row)!);
    assert.equal(f.store.shipments.get(id)!.status, "DELIVERED");
    assert.equal(page.byId("released").textContent, result + " Released, but the list could not refresh. Reload the page.");
    assert.equal(page.byId("error").textContent, "");
  });
}

test("/ops/v1: a release that worked is reported even when the list cannot refresh", async t => {
  const f = await httpFixture(t);
  const { id, result } = await readyToRelease(f);
  const page = await openAsFinance(f, "/ops/v1");
  const form = releaseForm(page);
  fill(form, { shipmentId: id, reason: "POD_REVIEWED" });
  failReadsAfterRelease(page);
  await page.click(page.visibleButton("Release payment", form)!);
  await page.click(page.visibleButton("Confirm release", form)!);
  assert.equal(f.store.shipments.get(id)!.status, "DELIVERED");
  assert.equal(page.byId("notice").textContent, result + " Released, but the list could not refresh. Reload the page.");
  assert.equal(page.byId("error").textContent, "");
});

test("/ops and /ops/v1: with no amount from the server, Release payment says so and asks nothing", async t => {
  const f = await httpFixture(t);
  const sentence = "Release is off for this shipment: the server did not send the amount. Nothing was released.";
  for (const path of ["/ops", "/ops/v1"]) {
    const { id } = await readyToRelease(f);
    const page = await openAsFinance(f, path);
    f.store.shipments.get(id)!.netToCarrierPaise = NaN;
    let within: FakeElement;
    if (path === "/ops") within = page.byId("shipments").children.find(article => article.textContent.includes(id))!;
    else fill((within = releaseForm(page)), { shipmentId: id, reason: "POD_REVIEWED" });
    await page.click(page.visibleButton("Release payment", within)!);
    assert.equal(page.byId("error").textContent, sentence, path);
    assert.equal(page.visibleButton("Confirm release", within), undefined, path);
    assert.ok(page.visibleButton("Release payment", within), path);
  }
});

test("/ops/v1: a field changed while the shipment details load drops the question instead of asking about old values", async t => {
  const f = await httpFixture(t);
  const { id, question } = await readyToRelease(f);
  const page = await openAsFinance(f, "/ops/v1");
  const form = releaseForm(page);
  fill(form, { shipmentId: id, reason: "POD_REVIEWED" });
  const asking = form.onsubmit!({ preventDefault() {} });
  fill(form, { shipmentId: "load-typed-later" });
  await asking;
  await page.settle();
  assert.equal(form.textContent.includes(question), false, form.textContent);
  assert.equal(page.visibleButton("Confirm release", form), undefined);
  assert.ok(page.visibleButton("Release payment", form), "the form stays usable");
  assert.equal(page.releaseRequests().length, 0);
});
