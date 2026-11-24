// Who sees what on the Load Board (owner, 4 Nov 2026): a posted load carries no amount of any kind; carriers see the
// cities, weight, size and pickup days, never who posted it or where exactly; drivers never see the board. A posted
// load has no note (owner, 4 Nov 2026).
import test from "node:test";
import assert from "node:assert/strict";
import { allKeys, loadBoardFixture, loadBody } from "./loadBoardSetup.ts";

const AMOUNT_KEY = /paise|price|payout|fee|rate|amount|gross|commission|net|earning/i;

test("a carrier office reads the board with only the cities, weight, size and pickup days: no amount, shipper, map point or poster", async t => {
  const { f, tokens, post, board } = await loadBoardFixture(t);
  const posted = await post();
  assert.equal(posted.status, 201, JSON.stringify(posted.body));

  for (const who of ["carrierB", "dispatcher", "carrierA"] as const) {
    const read = await board(tokens[who]);
    assert.equal(read.status, 200, `${who}: ${JSON.stringify(read.body)}`);
    assert.equal(read.body.loads.length, 1, who);
    const [load] = read.body.loads;
    assert.deepEqual(Object.keys(load).sort(), ["earliestPickupDate", "fromCity", "id", "latestPickupDate", "packages", "postedAtUtcMs", "toCity", "weightKg"], who);
    assert.deepEqual([load.fromCity, load.toCity, load.weightKg], ["Pune", "Mumbai", 400]);
    const text = JSON.stringify(read.body);
    assert.equal(allKeys(read.body).filter((key) => AMOUNT_KEY.test(key)).length, 0, `${who}: no amount field`);
    for (const secret of ["Synthetic Shipper A", f.shipperA.org.id, f.shipperA.user.id, f.shipperA.user.phone, "18.5204", "73.8567"]) {
      assert.ok(!text.includes(secret), `${who} must not see ${secret}`);
    }
  }
});

test("drivers, shippers, staff and strangers never read the board", async t => {
  const { f, tokens, post, board } = await loadBoardFixture(t);
  assert.equal((await post()).status, 201);
  assert.equal((await board(tokens.driver)).status, 403, "a driver");
  assert.equal((await board(tokens.shipperA)).status, 403, "the poster reads My loads, not the board");
  assert.equal((await board(tokens.shipperB)).status, 403, "another shipper");
  assert.equal((await board(tokens.unapproved)).status, 409, "a carrier not yet approved");
  assert.equal((await board(tokens.ops)).status, 403, "staff use the ops list");
  assert.equal((await f.request("/v1/load-board", "GET")).status, 401, "no sign-in");
});

test("a load whose shipper company was switched off leaves the board and takes no route", async t => {
  const { f, tokens, post, board, makeRoute } = await loadBoardFixture(t);
  const loadId = (await post()).body.load.id as string;
  const org = f.store.organizations.get(f.shipperA.org.id)!;
  f.store.organizations.set(org.id, { ...org, inactiveAtUtcMs: Date.now(), inactiveReason: "synthetic" });
  assert.deepEqual((await board(tokens.carrierB)).body.loads, []);
  assert.equal((await makeRoute(loadId)).status, 409);
});

test("another shipper can neither list nor withdraw the load, and a driver cannot make a route for it", async t => {
  const { f, tokens, post, makeRoute, unapproved } = await loadBoardFixture(t);
  const posted = await post();
  const loadId = posted.body.load.id as string;

  const theirs = await f.request("/v1/posted-loads", "GET", undefined, tokens.shipperB);
  assert.equal(theirs.status, 200);
  assert.deepEqual(theirs.body.loads, [], "shipper B lists only its own loads");
  assert.equal((await f.request(`/v1/posted-loads/${loadId}/withdraw`, "POST", {}, tokens.shipperB)).status, 404);
  assert.equal((await f.request("/v1/posted-loads", "GET", undefined, tokens.carrierB)).status, 403, "a carrier has no My loads");
  assert.equal((await f.request("/v1/posted-loads", "POST", loadBody(), tokens.carrierB)).status, 403, "a carrier cannot post");
  assert.equal((await f.request("/v1/posted-loads", "GET", undefined, tokens.driver)).status, 403);

  assert.equal((await makeRoute(loadId, tokens.driver)).status, 403, "a driver never answers the board");
  assert.equal((await makeRoute(loadId, tokens.unapproved, { orgId: unapproved.org.id })).status, 409, "nor does an unapproved carrier");
  assert.equal(f.store.postedLoads.get(loadId)?.routes.length, 0);
});

test("the poster sees everything it entered and the routes made for it, with no amount anywhere", async t => {
  const { tokens, post, makeRoute, f } = await loadBoardFixture(t);
  const posted = await post();
  const loadId = posted.body.load.id as string;
  const made = await makeRoute(loadId);
  assert.equal(made.status, 201, JSON.stringify(made.body));

  const mine = await f.request("/v1/posted-loads", "GET", undefined, tokens.shipperA);
  assert.equal(mine.status, 200);
  const [load] = mine.body.loads;
  assert.deepEqual(load.from, { city: "Pune", lat: 18.5204, lng: 73.8567 });
  assert.equal(load.routes.length, 1);
  assert.equal(load.routes[0].trip.carrierDisplayName, "Synthetic Carrier B");
  assert.equal(load.routes[0].trip.vehicleClass, "MEDIUM");
  assert.equal(load.routes[0].canBook, true);
  assert.equal(allKeys(mine.body).filter((key) => AMOUNT_KEY.test(key)).length, 0, "no amount field");
  assert.ok(!allKeys(mine.body).some((key) => ["assignedDriverUserId", "assignedVehicleId", "lastLiveLocation"].includes(key)), "who drives stays the carrier's");
});

test("a new load alerts every approved carrier office member who has load alerts on, and nobody else", async t => {
  const { f, tokens, post, notices } = await loadBoardFixture(t);
  const off = await f.request("/v1/me/settings", "PATCH", { loadAlerts: false }, tokens.carrierA);
  assert.equal(off.status, 200, JSON.stringify(off.body));
  assert.deepEqual(off.body, { loadAlerts: false });
  const posted = await post();
  const loadId = posted.body.load.id as string;

  const told = (list: Array<Record<string, any>>) => list.filter((n) => n.eventKey === "posted_load.new");
  for (const who of ["carrierB", "dispatcher"] as const) {
    const [notice, ...more] = told(await notices(tokens[who]));
    assert.ok(notice, `${who} is told`);
    assert.equal(more.length, 0);
    assert.equal(notice.postedLoadId, loadId);
    assert.equal(notice.data.title, "New load on the Load Board");
    assert.equal(allKeys(notice).filter((key) => AMOUNT_KEY.test(key)).length, 0);
    assert.ok(!JSON.stringify(notice).includes("Synthetic Shipper A"), "no shipper name");
  }
  for (const who of ["carrierA", "driver", "unapproved", "shipperA", "shipperB"] as const) {
    assert.deepEqual(told(await notices(tokens[who])), [], `${who} is not told`);
  }
  const stored = [...f.store.notifications.values()].filter((n) => n.eventKey === "posted_load.new");
  assert.deepEqual(stored.map((n) => n.recipientUserId).sort(), [f.carrierB.user.id, [...f.store.users.values()].find((u) => u.phone === "8000000021")!.id].sort(), "exactly the two office members");
});

test("a note sent by an older app is ignored, as the route form ignores fields it does not read: not kept, shown to nobody", async t => {
  const { f, tokens, post, makeRoute, notices } = await loadBoardFixture(t);
  const posted = await post(loadBody({ note: "Synthetic old-app note" }));
  assert.equal(posted.status, 201, JSON.stringify(posted.body));
  const loadId = posted.body.load.id as string;
  assert.equal((await makeRoute(loadId)).status, 201);
  assert.equal("note" in f.store.postedLoads.get(loadId)!, false, "not stored");
  const seen = [
    posted.body,
    (await f.request("/v1/posted-loads", "GET", undefined, tokens.shipperA)).body,
    (await f.request("/v1/load-board", "GET", undefined, tokens.carrierB)).body,
    (await f.request("/ops/posted-loads", "GET", undefined, tokens.ops)).body,
    await notices(tokens.carrierB),
    await notices(tokens.shipperA),
  ];
  for (const body of seen) {
    assert.ok(!allKeys(body).includes("note") && !JSON.stringify(body).includes("old-app note"), JSON.stringify(body));
  }
});
