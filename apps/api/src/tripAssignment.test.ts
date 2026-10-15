import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { inviteCarrierDriver, publishAnchorTrip, registerCustomerUser } from "./services.ts";
import { getIntegrationShipmentSnapshot, getIntegrationShipmentTracking } from "./integrationServices.ts";
import { listGroupedNotifications, type GroupedInboxPageReader } from "./notifications.ts";
import { authorizationContext, resolvePrincipal } from "./rbac.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

async function hireDriver(f: Fixture, phone: string, fullName: string, registrationNumber: string) {
  registerCustomerUser(f.store, { fullName, phone });
  const hired = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone, role: "DRIVER", vehicleRegistrationNumber: registrationNumber, vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const token = await f.login(phone);
  return { userId: hired.user.id, vehicleId: hired.vehicle.id, token };
}
type HiredDriver = Awaited<ReturnType<typeof hireDriver>>;

/** Carrier A with two drivers, each with a truck, and a second trip beside the fixture's. */
async function fleetWithTwoDrivers(t: TestContext) {
  const f = await httpFixture(t);
  const first = await hireDriver(f, "8000000013", "Synthetic Driver One", "ka 01-ab 1234");
  const second = await hireDriver(f, "8000000014", "Synthetic Driver Two", "KA02XY9999");
  const secondTrip = publishAnchorTrip(f.store, { carrierId: f.carrierA.org.id, originCity: "C", destCity: "D", windowStart: "2026-09-16", windowEnd: "2026-09-17", vehicleClass: "MEDIUM", capacityKg: 1000 });
  return { f, first, second, secondTripId: secondTrip.id };
}

async function assign(f: Fixture, tripId: string, driver: HiredDriver, token: string) {
  return f.request(`/v1/pilot/anchor-trips/${tripId}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, token);
}

async function bookAndAccept(f: Fixture, tripId: string): Promise<string> {
  const booking = await f.book(f.tokens.shipperA, { anchorTripId: tripId });
  assert.equal(booking.status, 201);
  const id = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  return id;
}

const ids = (list: unknown): string[] => (list as Array<{ id: string }>).map((item) => item.id).sort();

test("the owner and a dispatcher name the truck and driver; a driver, another carrier and wrong choices are refused", async t => {
  const { f, first, second, secondTripId } = await fleetWithTwoDrivers(t);
  const route = `/v1/pilot/anchor-trips/${f.trip.id}/assignment`;
  const choice = { vehicleId: first.vehicleId, driverUserId: first.userId };
  assert.equal((await f.request(route, "POST", choice)).status, 401);
  const saved = await assign(f, f.trip.id, first, f.tokens.carrierA);
  assert.equal(saved.status, 200);
  const trip = saved.body.trip as Record<string, unknown>;
  assert.deepEqual(
    [trip.assignedVehicleId, trip.assignedDriverUserId, trip.assignedTruckNumber, trip.assignedDriverName, saved.body.driverBusy],
    [first.vehicleId, first.userId, "KA01AB1234", "Synthetic Driver One", false],
  );
  assert.equal((await f.request(route, "POST", choice, first.token)).status, 403, "a driver only reads the assignment");
  assert.equal((await f.request(route, "POST", choice, f.tokens.carrierB)).status, 404, "another carrier's trip does not exist for them");
  assert.equal((await f.request(route, "POST", choice, f.tokens.shipperA)).status, 404);
  const refusals: Array<[Record<string, unknown>, string]> = [
    [{ ...choice, vehicleId: f.carrierB.vehicle.id }, "vehicleId"],
    [{ ...choice, vehicleId: "no-such-truck" }, "vehicleId"],
    [{ driverUserId: first.userId }, "vehicleId"],
    [{ ...choice, driverUserId: f.carrierB.user.id }, "driverUserId"],
    [{ ...choice, driverUserId: f.shipperA.user.id }, "driverUserId"],
    [{ vehicleId: first.vehicleId }, "driverUserId"],
  ];
  for (const [body, field] of refusals) {
    const refused = await f.request(route, "POST", body, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.field], [400, field], JSON.stringify(body));
    assert.ok(/[.]$/.test(refused.body.detail), "detail is a sentence");
  }

  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000015", role: "DISPATCHER" });
  const dispatcherToken = await f.login("8000000015");
  const reassigned = await assign(f, f.trip.id, second, dispatcherToken);
  assert.equal(reassigned.status, 200, "a dispatcher may assign, and a new choice replaces the old");
  assert.equal(reassigned.body.trip.assignedDriverUserId, second.userId);

  f.store.anchorTrips.set(secondTripId, { ...f.store.anchorTrips.get(secondTripId)!, status: "COMPLETED" });
  const completed = await assign(f, secondTripId, first, f.tokens.carrierA);
  assert.deepEqual([completed.status, completed.body.error], [409, "trip_completed"]);

  const restored = loadStoreFromDisk(f.dataFilePath!);
  const kept = restored.anchorTrips.get(f.trip.id);
  assert.deepEqual([kept?.assignedVehicleId, kept?.assignedDriverUserId], [second.vehicleId, second.userId], "the assignment survives a restart");
  const rows = [...restored.auditEvents.values()].filter((event) => event.action === "TRIP_ASSIGNED");
  assert.deepEqual(rows.map((event) => [event.resourceType, event.previousState, event.newState]), [["trip", "UNASSIGNED", "ASSIGNED"], ["trip", "ASSIGNED", "ASSIGNED"]]);
  const auditText = JSON.stringify(rows);
  for (const named of [first.vehicleId, second.vehicleId, first.userId, second.userId, "KA01AB1234", "KA02XY9999", "Synthetic Driver"]) {
    assert.equal(auditText.includes(named), false, `${named} is not in the audit log`);
  }
});

test("naming a driver already on a trip in progress warns but still saves", async t => {
  const { f, first, second, secondTripId } = await fleetWithTwoDrivers(t);
  f.store.anchorTrips.set(f.trip.id, { ...f.trip, status: "IN_PROGRESS", assignedVehicleId: first.vehicleId, assignedDriverUserId: first.userId });
  const busy = await f.request(`/v1/pilot/anchor-trips/${secondTripId}/assignment`, "POST", { vehicleId: second.vehicleId, driverUserId: first.userId }, f.tokens.carrierA);
  assert.deepEqual([busy.status, busy.body.driverBusy, busy.body.trip.assignedDriverUserId], [200, true, first.userId]);
  const free = await assign(f, secondTripId, second, f.tokens.carrierA);
  assert.deepEqual([free.status, free.body.driverBusy], [200, false]);
});

test("the fleet list gives owners trucks and driver names, never phone numbers; drivers cannot read it", async t => {
  const { f, first, second } = await fleetWithTwoDrivers(t);
  const fleet = await f.request("/v1/pilot/carrier/fleet", "GET", undefined, f.tokens.carrierA);
  assert.equal(fleet.status, 200);
  assert.deepEqual(ids((fleet.body.vehicles as Array<{ id: string }>)), [f.carrierA.vehicle.id, first.vehicleId, second.vehicleId].sort());
  assert.deepEqual((fleet.body.drivers as Array<{ userId: string }>).map((driver) => driver.userId).sort(), [f.carrierA.user.id, first.userId, second.userId].sort());
  const text = JSON.stringify(fleet.body);
  for (const phone of ["8000000003", "8000000013", "8000000014"]) assert.equal(text.includes(phone), false, `${phone} stays on the server`);
  assert.equal(text.includes(f.carrierB.vehicle.id), false, "another carrier's trucks are not offered");
  assert.equal((await f.request("/v1/pilot/carrier/fleet", "GET", undefined, first.token)).status, 403);
  assert.equal((await f.request("/v1/pilot/carrier/fleet", "GET", undefined, f.tokens.shipperA)).status, 403);
});

test("a trip the solo owner-operator publishes names them and their truck; a dispatcher's and older trips stay unassigned", async t => {
  const f = await httpFixture(t);
  const lane = { orgId: f.carrierA.org.id, originCity: "A", destCity: "B", windowStart: "2026-10-16", windowEnd: "2026-10-17", vehicleClass: "MEDIUM", capacityKg: 500 };
  const published = await f.request("/v1/pilot/anchor-trips", "POST", lane, f.tokens.carrierA);
  assert.equal(published.status, 201);
  assert.deepEqual(
    [published.body.trip.assignedDriverUserId, published.body.trip.assignedVehicleId, published.body.trip.assignedTruckNumber],
    [f.carrierA.user.id, f.carrierA.vehicle.id, "TESTA"],
  );
  const audit = [...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()].filter((event) => event.action === "TRIP_ASSIGNED");
  assert.deepEqual(audit.map((event) => [event.previousState, event.newState]), [["UNASSIGNED", "ASSIGNED"]]);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedDriverUserId, undefined, "a trip from before stays unassigned");

  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000015", role: "DISPATCHER" });
  const byDispatcher = await f.request("/v1/pilot/anchor-trips", "POST", lane, await f.login("8000000015"));
  assert.equal(byDispatcher.status, 201);
  assert.equal(byDispatcher.body.trip.assignedDriverUserId, undefined, "a dispatcher is not a driver, so nothing fills in");
});

test("a driver sees only the trips naming them and their shipments, on every route; owners see all; an unassigned driver sees nothing", async t => {
  const { f, first, second, secondTripId } = await fleetWithTwoDrivers(t);
  const third = await hireDriver(f, "8000000016", "Synthetic Driver Three", "KA03ZZ0001");
  assert.equal((await assign(f, f.trip.id, first, f.tokens.carrierA)).status, 200);
  assert.equal((await assign(f, secondTripId, second, f.tokens.carrierA)).status, 200);
  const mine = await bookAndAccept(f, f.trip.id);
  const theirs = await bookAndAccept(f, secondTripId);
  const get = (path: string, token: string) => f.request(path, "GET", undefined, token);

  assert.deepEqual(ids((await get("/v1/pilot/carrier/shipments", first.token)).body.shipments), [mine]);
  assert.deepEqual(ids((await get(`/v1/pilot/carrier/shipments?anchorTripId=${secondTripId}`, first.token)).body.shipments), []);
  assert.deepEqual(ids((await get("/v1/pilot/anchor-trips", first.token)).body.trips), [f.trip.id]);
  assert.equal((await get(`/v1/pilot/anchor-trips/${f.trip.id}`, first.token)).status, 200);
  assert.deepEqual(ids((await get("/v1/pilot/carrier/shipments", second.token)).body.shipments), [theirs]);

  const hidden: Array<[string, string]> = [
    ["GET", `/v1/pilot/anchor-trips/${secondTripId}`],
    ["POST", `/v1/pilot/anchor-trips/${secondTripId}/start`],
    ["POST", `/v1/pilot/anchor-trips/${secondTripId}/location`],
    ["POST", `/v1/pilot/anchor-trips/${secondTripId}/complete`],
    ["GET", `/shipments/${theirs}`],
    ["GET", `/shipments/${theirs}/tracking`],
    ["POST", `/shipments/${theirs}/driver-pod`],
    ["POST", `/v1/pilot/carrier/shipments/${theirs}/accept`],
    ["GET", `/v1/shipments/${theirs}/conversation/timeline`],
    ["GET", `/v1/shipments/${theirs}/conversation/messages`],
  ];
  for (const [method, path] of hidden) {
    assert.equal((await f.request(path, method, method === "POST" ? { lat: 12.9, lng: 77.6 } : undefined, first.token)).status, 404, `${method} ${path}`);
  }
  assert.equal((await get(`/shipments/${mine}/tracking`, first.token)).status, 200);
  assert.equal((await get(`/v1/shipments/${mine}/conversation/timeline`, first.token)).status, 200);

  const inbox = await get("/v1/notifications", first.token);
  assert.ok((inbox.body.notifications as Array<{ shipmentId: string }>).length > 0, "the driver hears about their own shipment");
  assert.deepEqual([...new Set((inbox.body.notifications as Array<{ shipmentId: string }>).map((item) => item.shipmentId))], [mine]);
  const grouped = await get("/v1/notifications/shipments", first.token);
  assert.deepEqual((grouped.body.shipments as Array<{ shipmentId: string }>).map((group) => group.shipmentId), [mine]);

  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/start`, "POST", {}, first.token)).status, 200, "a driver starts their own trip");
  assert.equal((await f.request(`/shipments/${mine}/driver-pod`, "POST", {}, first.token)).status, 200, "and confirms delivery on it");

  assert.deepEqual(ids((await get("/v1/pilot/carrier/shipments", f.tokens.carrierA)).body.shipments), [mine, theirs].sort());
  assert.deepEqual(ids((await get("/v1/pilot/anchor-trips", f.tokens.carrierA)).body.trips), [f.trip.id, secondTripId].sort());

  assert.deepEqual((await get("/v1/pilot/carrier/shipments", third.token)).body.shipments, []);
  assert.deepEqual((await get("/v1/pilot/anchor-trips", third.token)).body.trips, []);
  assert.deepEqual((await get("/v1/notifications", third.token)).body.notifications, []);
  assert.equal((await get(`/v1/pilot/anchor-trips/${f.trip.id}`, third.token)).status, 404);
});

test("notifications from before an assignment stay hidden: the database inbox reader and the open route", async t => {
  const { f, first, second, secondTripId } = await fleetWithTwoDrivers(t);
  assert.equal((await assign(f, f.trip.id, first, f.tokens.carrierA)).status, 200);
  assert.equal((await assign(f, secondTripId, second, f.tokens.carrierA)).status, 200);
  const mine = await bookAndAccept(f, f.trip.id);
  const theirs = await bookAndAccept(f, secondTripId);
  // The database reader groups by recipient only, as a store holding notifications from before the change would.
  const databaseReader: GroupedInboxPageReader = async () => ({
    notificationSequence: f.store.notificationSequence,
    unreadCount: 2,
    groups: [mine, theirs].map((shipmentId) => ({ shipmentId, latestAtUtcMs: 1, unreadCount: 1, shipmentReference: shipmentId })),
  });
  const page = await authorizationContext.run({ principal: resolvePrincipal(f.store, first.userId), requestId: "synthetic" },
    () => listGroupedNotifications(f.store, 30, undefined, databaseReader));
  assert.deepEqual(page.shipments.map((group) => group.shipmentId), [mine]);

  const theirNotification = [...f.store.notifications.values()].find((item) => item.recipientUserId === second.userId && item.shipmentId === theirs);
  assert.ok(theirNotification, "the other driver was told about their shipment");
  f.store.notifications.set("synthetic-old", { ...theirNotification, id: "synthetic-old", recipientUserId: first.userId });
  assert.equal((await f.request("/v1/notifications/synthetic-old/open", "POST", {}, first.token)).status, 404);
  assert.equal((await f.request(`/v1/notifications/${theirNotification.id}/open`, "POST", {}, second.token)).status, 200);
});

test("the assigned truck reaches shipper, carrier and ops responses; finance, admin and ERP get none, and shippers never learn the driver", async t => {
  const { f, first } = await fleetWithTwoDrivers(t);
  assert.equal((await assign(f, f.trip.id, first, f.tokens.carrierA)).status, 200);
  const id = await bookAndAccept(f, f.trip.id);
  const get = (path: string, token: string) => f.request(path, "GET", undefined, token);

  assert.equal((await get(`/shipments/${id}`, f.tokens.shipperA)).body.shipment.assignedTruckNumber, "KA01AB1234");
  const carrierRow = ((await get("/v1/pilot/carrier/shipments", f.tokens.carrierA)).body.shipments as Array<{ id: string; assignedTruckNumber?: string }>).find((s) => s.id === id);
  assert.equal(carrierRow?.assignedTruckNumber, "KA01AB1234");
  assert.equal((await get(`/ops/shipments/${id}`, f.tokens.ops)).body.shipment.assignedTruckNumber, "KA01AB1234");
  for (const token of [f.tokens.finance, f.tokens.admin]) {
    const view = await get(`/ops/shipments/${id}`, token);
    assert.equal(view.status, 200);
    assert.equal(view.body.shipment.assignedTruckNumber, undefined);
  }

  for (const path of [`/shipments/${id}`, "/shipments", `/shipments/${id}/tracking`]) {
    const text = JSON.stringify((await get(path, f.tokens.shipperA)).body);
    for (const driverDetail of [first.userId, "Synthetic Driver One", "assignedDriver", "assignedVehicleId"]) {
      assert.equal(text.includes(driverDetail), false, `${driverDetail} reached the shipper on ${path}`);
    }
  }

  const erp = JSON.stringify([getIntegrationShipmentSnapshot(f.store, f.shipperA.org.id, id), getIntegrationShipmentTracking(f.store, f.shipperA.org.id, id)]);
  assert.equal(erp.includes("assigned"), false, "ERP responses keep their shape");
  assert.equal(erp.includes(first.userId), false);
});
