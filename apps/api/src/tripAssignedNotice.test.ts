// Owner, 21 Oct 2026: the driver a trip is assigned to hears it in the app, whether or not anything is booked
// on it. Only that driver hears it: never the shipper, never the rest of the carrier, never the person who chose.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

/** Carrier A with two drivers, a dispatcher and an owner, all signed in; nobody assigned yet. */
async function carrierWithTwoDrivers(t: TestContext) {
  const f = await httpFixture(t);
  const orgId = f.carrierA.org.id;
  const staff = [
    ["8000000013", "DRIVER", "KA02XY9999"],
    ["8000000014", "DRIVER", "KA03ZZ1111"],
    ["8000000015", "DISPATCHER", null],
  ] as const;
  const people = staff.map(([phone, role, truck]) => {
    registerCustomerUser(f.store, { fullName: `Synthetic ${phone}`, phone });
    return inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone, role, ...(truck ? { vehicleRegistrationNumber: truck, vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 } : {}) });
  });
  const owner = registerCustomerUser(f.store, { fullName: "Synthetic Owner", phone: "8000000016" });
  f.store.memberships.set(`${owner.user.id}:${orgId}`, { userId: owner.user.id, orgId, role: "OWNER", createdAtUtcMs: Date.now() });
  const tokens = {
    driverA: await f.login("8000000013"), driverB: await f.login("8000000014"), dispatcher: await f.login("8000000015"),
    owner: await f.login("8000000016"), ownerDriver: f.tokens.carrierA, shipper: f.tokens.shipperA,
  };
  const [driverA, driverB] = people;
  const assign = (driver: { user: { id: string } }, token = tokens.ownerDriver) =>
    f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driverA.vehicle.id, driverUserId: driver.user.id }, token);
  const tripNotices = async (token: string) =>
    ((await f.request("/v1/notifications", "GET", undefined, token)).body.notifications as Array<Record<string, any>>)
      .filter((notice) => notice.eventKey === "trip.assigned");
  return { f, driverA, driverB, tokens, assign, tripNotices };
}

test("the assigned driver hears of a new trip with nothing booked on it; the shipper and the rest of the carrier do not", async t => {
  const { f, driverA, tokens, assign, tripNotices } = await carrierWithTwoDrivers(t);
  assert.equal([...f.store.shipments.values()].filter((s) => s.anchorTripId === f.trip.id).length, 0, "nothing is booked");
  assert.equal((await assign(driverA)).status, 200);

  const [notice, ...more] = await tripNotices(tokens.driverA);
  assert.ok(notice, "driver A has the notice");
  assert.equal(more.length, 0);
  assert.equal(notice.tripId, f.trip.id);
  assert.equal(notice.data.body, "You have a new trip: A to B, leaves 16 Sep.");
  assert.doesNotMatch(JSON.stringify(notice), /Paise|₹/, "no amounts");
  for (const who of ["driverB", "dispatcher", "owner", "ownerDriver", "shipper"] as const) {
    assert.equal((await tripNotices(tokens[who])).length, 0, `${who} hears nothing`);
  }

  const inbox = await f.request("/v1/notifications/shipments", "GET", undefined, tokens.driverA);
  const row = (inbox.body.shipments as Array<Record<string, any>>).find((item) => item.tripId === f.trip.id);
  assert.deepEqual({ tripRoute: row?.tripRoute, unreadCount: row?.unreadCount, notificationId: row?.notificationId }, { tripRoute: "A to B", unreadCount: 1, notificationId: notice.id });
  const opened = await f.request(`/v1/notifications/${notice.id}/open`, "POST", {}, tokens.driverA);
  assert.equal(opened.status, 200);
  assert.deepEqual(opened.body, { organizationId: f.carrierA.org.id, tripId: f.trip.id }, "opening it goes to the trip");
  assert.equal((await f.request(`/v1/notifications/${notice.id}/read`, "PATCH", {}, tokens.driverA)).status, 200);
  assert.equal((await f.request("/v1/notifications", "GET", undefined, tokens.driverA)).body.unreadCount, 0);
});

test("choosing yourself as the driver gives you no notice", async t => {
  const { f, tokens, tripNotices } = await carrierWithTwoDrivers(t);
  const self = { user: { id: f.carrierA.user.id } };
  const assigned = await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST",
    { vehicleId: [...f.store.vehicles.values()].find((v) => v.orgId === f.carrierA.org.id && v.registrationNumber === "TEST-A")!.id, driverUserId: self.user.id }, tokens.ownerDriver);
  assert.equal(assigned.status, 200);
  assert.equal(f.store.anchorTrips.get(f.trip.id)!.assignedDriverUserId, self.user.id);
  for (const who of ["ownerDriver", "driverA", "driverB", "owner", "dispatcher", "shipper"] as const) {
    assert.equal((await tripNotices(tokens[who])).length, 0, `${who} hears nothing`);
  }
});

test("a trip given to a second driver tells the second; the first no longer sees the notice", async t => {
  const { f, driverA, driverB, tokens, assign, tripNotices } = await carrierWithTwoDrivers(t);
  assert.equal((await assign(driverA)).status, 200);
  const [first] = await tripNotices(tokens.driverA);
  assert.ok(first);
  assert.equal((await assign(driverB, tokens.owner)).status, 200);
  assert.equal((await tripNotices(tokens.driverB)).length, 1, "driver B hears of the trip");
  assert.equal((await tripNotices(tokens.driverA)).length, 0, "the trip is no longer driver A's");
  assert.equal((await f.request(`/v1/notifications/${first.id}/open`, "POST", {}, tokens.driverA)).status, 404);
  assert.equal((await tripNotices(tokens.owner)).length, 0, "the owner who chose hears nothing");
  assert.equal((await assign(driverB, tokens.owner)).status, 200, "saving the same driver again");
  assert.equal((await tripNotices(tokens.driverB)).length, 1, "is not a new trip");

  assert.equal((await assign(driverA, tokens.owner)).status, 200, "given back to driver A");
  const backToA = await tripNotices(tokens.driverA);
  assert.deepEqual(backToA.map((notice) => notice.id), [first.id], "driver A sees the first notice again, not a second");
  assert.equal([...f.store.notifications.values()].filter((n) => n.eventKey === "trip.assigned" && n.recipientUserId === driverA.user.id).length, 1);
});
