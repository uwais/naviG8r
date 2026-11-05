// The /ops/beta "Load Board" card: every posted load, its state, times and routes, read only and with no amount.
import test from "node:test";
import assert from "node:assert/strict";
import { FakePage, inlineScript } from "../../../../test/fakePage.ts";
import { loadBoardFixture, loadBody } from "./loadBoardSetup.ts";

test("/ops/beta lists each posted load with its state, shipper, pickup days and routes, and offers no action", async t => {
  const { f, tokens, post, makeRoute } = await loadBoardFixture(t);
  const open = (await post()).body.load.id as string;
  assert.equal((await makeRoute(open)).status, 201);
  const withdrawn = (await post(loadBody({ from: { city: "Delhi", lat: 28.61, lng: 77.2 }, to: { city: "Jaipur", lat: 26.91, lng: 75.79 } }))).body.load.id as string;
  assert.equal((await f.request(`/v1/posted-loads/${withdrawn}/withdraw`, "POST", {}, tokens.shipperA)).status, 200);

  const page = new FakePage(f.base);
  page.session.set("navig8r_access", tokens.ops);
  page.run(inlineScript(await (await fetch(f.base + "/ops/beta")).text()));
  await page.settle();

  const body = page.byId("postedLoadsBody");
  for (const words of ["Pune to Mumbai, 400 kg", open, "Synthetic Shipper A", "On the board", "1 route made: Synthetic Carrier B", "Delhi to Jaipur", "Withdrawn by the shipper", "No route made yet"]) {
    assert.ok(body.textContent.includes(words), `the card shows: ${words}`);
  }
  assert.equal(page.byId("postedLoadsCount").textContent, "2 loads, 1 on the board");
  assert.ok(!/₹|Fragile/.test(body.textContent), "no amount and no note");
  assert.equal(page.visibleButton("Withdraw", body), undefined, "read only");
});
