import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";
import { publishAnchorTrip } from "./services.ts";

// Needs a disposable Postgres whose AnchorTripRow already has the "assignedVehicleId" and "assignedDriverUserId" columns.
const databaseUrl = process.env.EWAY_TRIP_TEST_DATABASE_URL;
const disposableDatabaseUrl = databaseUrl &&
  /^postgres(?:ql)?:\/\/[^/]*127\.0\.0\.1(?::\d+)?\/navig8r_trip_test(?:\?.*)?$/.test(databaseUrl)
  ? databaseUrl
  : undefined;

test("PostgreSQL keeps a trip's truck and driver across a save and reload, and a trip with none comes back with none", {
  skip: !databaseUrl,
}, async t => {
  assert.ok(disposableDatabaseUrl, "EWAY_TRIP_TEST_DATABASE_URL must target 127.0.0.1/navig8r_trip_test");
  const previousDatabaseUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = disposableDatabaseUrl;
  const f = await httpFixture(t);
  const unassigned = publishAnchorTrip(f.store, { carrierId: f.carrierA.org.id, originCity: "C", destCity: "D", windowStart: "2026-09-16", windowEnd: "2026-09-17", vehicleClass: "MEDIUM", capacityKg: 1000 });
  const choice = { vehicleId: f.carrierA.vehicle.id, driverUserId: f.carrierA.user.id };
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", choice, f.tokens.carrierA)).status, 200);
  const database = await import("./persistenceDb.ts");
  t.after(async () => {
    await database.disconnectDatabase();
    if (previousDatabaseUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousDatabaseUrl;
  });
  await database.saveStoreToDatabase(f.store);
  const reloaded = await database.loadStoreFromDatabase();
  const assigned = reloaded.anchorTrips.get(f.trip.id);
  assert.deepEqual([assigned?.assignedVehicleId, assigned?.assignedDriverUserId], [choice.vehicleId, choice.driverUserId]);
  assert.ok(reloaded.anchorTrips.has(unassigned.id), "the trip with no assignment is saved too");
  const none = reloaded.anchorTrips.get(unassigned.id);
  assert.deepEqual([none?.assignedVehicleId, none?.assignedDriverUserId], [undefined, undefined], "absent, not null");
});
