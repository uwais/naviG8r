// The data file went from version 7 to 8 for the Load Board: a version 7 file loads with no posted loads and every
// load alert on, and a version 8 file keeps posted loads, Load Board notices and alert choices across a restart.
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createStore } from "../../../store.ts";
import { dumpStore, loadStoreFromDisk, saveStoreToDisk } from "../../../persistence.ts";
import type { PostedLoad } from "../postedLoad.ts";

const load: PostedLoad = {
  id: "load_synthetic", shipperOrgId: "org_shipper", postedByUserId: "user_shipper",
  from: { city: "Pune", lat: 18.52, lng: 73.85 }, to: { city: "Mumbai", lat: 19.07, lng: 72.87 },
  weightKg: 400, packages: { kind: "SIZES", count: 4, length: 40, width: 30, height: 20, unit: "INCHES" },
  earliestPickupDate: "2026-11-05", latestPickupDate: "2026-11-06", note: "Synthetic note", state: "BOOKED",
  postedAtUtcMs: 1, closedAtUtcMs: 3, routes: [{ tripId: "trip_synthetic", carrierOrgId: "org_carrier", madeAtUtcMs: 2 }],
  booking: { shipmentId: "shp_synthetic", bookedAtUtcMs: 3 },
};

test("a version 7 data file loads with an empty Load Board, and saves back as version 8", async t => {
  const dir = await mkdtemp(join(tmpdir(), "load-board-v7-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const file = join(dir, "store.json");
  const { postedLoads: _loads, loadAlertSettings: _settings, ...v7 } = { ...dumpStore(createStore()), version: 7 };
  await writeFile(file, JSON.stringify(v7));

  const store = loadStoreFromDisk(file);
  assert.equal(store.version, 8);
  assert.equal(store.postedLoads.size, 0);
  assert.equal(store.loadAlertSettings.size, 0);
  saveStoreToDisk(file, store);
  const saved = JSON.parse(await readFile(file, "utf8"));
  assert.deepEqual([saved.version, saved.postedLoads, saved.loadAlertSettings], [8, [], []]);
});

test("posted loads, Load Board notices and alert choices survive a save and reload", async t => {
  const dir = await mkdtemp(join(tmpdir(), "load-board-v8-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const file = join(dir, "store.json");
  const store = createStore();
  store.postedLoads.set(load.id, load);
  store.loadAlertSettings.set("user_office", { userId: "user_office", loadAlertsOn: false, updatedAtUtcMs: 5 });
  store.notifications.set("n1", {
    id: "n1", recipientSequence: 1, eventId: "posted_load.new:load_synthetic", eventKey: "posted_load.new",
    recipientUserId: "user_office", recipientOrgId: "org_carrier", shipmentId: "", postedLoadId: load.id, createdAtUtcMs: 4,
    data: { postedLoadId: load.id, audience: "CARRIER", title: "New load on the Load Board", body: "Pune to Mumbai" },
  });
  store.notificationSequence = 1;
  saveStoreToDisk(file, store);

  const reloaded = loadStoreFromDisk(file);
  assert.deepEqual(reloaded.postedLoads.get(load.id), load);
  assert.equal(reloaded.loadAlertSettings.get("user_office")?.loadAlertsOn, false);
  assert.equal(reloaded.notifications.get("n1")?.postedLoadId, load.id);
});
