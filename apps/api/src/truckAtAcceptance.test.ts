// What the shipper needs to make both parts of the e-way bill in one portal visit (owner decision, 16 Oct 2026): the
// carrier's transporter ID, the truck named when the carrier accepts, and the portal's form of a truck number.
import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { inviteCarrierDriver, publishAnchorTrip, registerCustomerUser } from "./services.ts";
import { getIntegrationShipmentSnapshot, getIntegrationShipmentTracking } from "./integrationServices.ts";
import { portalTruckNumber } from "./tripAssignmentRules.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

const transporterIdRule = "A transporter ID is 15 letters and digits, starting with two digits: your GSTIN, or the TRANSIN from the e-way bill portal. Leave it empty if you do not have one.";
const transporterIdRoute = "/v1/pilot/carrier/transporter-id";

/** Carrier A takes on a driver, with a truck registered as "UP 1 345", and a dispatcher, so it becomes a fleet. */
async function hireStaff(f: Fixture) {
  registerCustomerUser(f.store, { fullName: "Synthetic Driver One", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "UP 1 345", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000015", role: "DISPATCHER" });
  return { driverUserId: driver.user.id, driverTruckId: driver.vehicle.id, driverToken: await f.login("8000000013"), dispatcherToken: await f.login("8000000015") };
}

async function bookOnFixtureTrip(f: Fixture): Promise<string> {
  const booking = await f.book();
  assert.equal(booking.status, 201);
  return booking.body.shipment.id as string;
}

const accept = (f: Fixture, shipmentId: string, body: unknown, token: string) =>
  f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", body, token);

test("the owner sets the transporter ID, cleaned, and clears it; a wrong one changes nothing; dispatchers, drivers and shippers may not set it", async t => {
  const f = await httpFixture(t);
  const staff = await hireStaff(f);
  const setTo = (transporterId: unknown, token: string) => f.request(transporterIdRoute, "PATCH", { transporterId }, token);
  assert.equal((await f.request(transporterIdRoute, "PATCH", { transporterId: "29ABCDE1234F1Z5" })).status, 401);

  const saved = await setTo(" 29abcde 1234f1z5 ", f.tokens.carrierA);
  assert.deepEqual([saved.status, saved.body.org.transporterId], [200, "29ABCDE1234F1Z5"], "spaces removed, letters upper-cased");
  const wrongOnes: unknown[] = ["29ABCDE1234F1Z", "29ABCDE1234F1Z55", "AB29CDE1234F1Z5", "29ABCDE-1234F1Z", 291234567890123, undefined];
  for (const wrong of wrongOnes) {
    const refused = await setTo(wrong, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.error, refused.body.field, refused.body.detail], [400, "invalid_transporter_id", "transporterId", transporterIdRule], String(wrong));
  }
  assert.equal(f.store.organizations.get(f.carrierA.org.id)?.transporterId, "29ABCDE1234F1Z5", "a refused value changes nothing");
  for (const token of [staff.dispatcherToken, staff.driverToken, f.tokens.shipperA]) {
    assert.equal((await setTo("27AAAAA0000A1Z5", token)).status, 403);
  }
  assert.equal(loadStoreFromDisk(f.dataFilePath!).organizations.get(f.carrierA.org.id)?.transporterId, "29ABCDE1234F1Z5", "it survives a restart");

  for (const cleared of [null, "   "]) {
    assert.equal((await setTo("29ABCDE1234F1Z5", f.tokens.carrierA)).status, 200);
    const response = await setTo(cleared, f.tokens.carrierA);
    assert.deepEqual([response.status, response.body.org.transporterId], [200, undefined], JSON.stringify(cleared));
    assert.equal(loadStoreFromDisk(f.dataFilePath!).organizations.get(f.carrierA.org.id)?.transporterId, undefined);
  }
  const rows = [...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()].filter((event) => event.action === "TRANSPORTER_ID_CHANGED");
  assert.deepEqual(rows.map((event) => [event.resourceType, event.resourceId, event.previousState, event.newState]), [
    ["organization", f.carrierA.org.id, "ABSENT", "SET"],
    ["organization", f.carrierA.org.id, "SET", "SET"],
    ["organization", f.carrierA.org.id, "SET", "ABSENT"],
    ["organization", f.carrierA.org.id, "ABSENT", "SET"],
    ["organization", f.carrierA.org.id, "SET", "ABSENT"],
  ]);
  assert.equal(JSON.stringify(rows).includes("29ABCDE1234F1Z5"), false, "the audit log never holds the ID");
});

test("the carrier office reads its transporter ID on /v1/pilot/me; its drivers and other carriers do not", async t => {
  const f = await httpFixture(t);
  const staff = await hireStaff(f);
  assert.equal((await f.request(transporterIdRoute, "PATCH", { transporterId: "29ABCDE1234F1Z5" }, f.tokens.carrierA)).status, 200);
  const me = async (token: string) => (await f.request("/v1/pilot/me", "GET", undefined, token)).body as { organizations: Array<{ id: string; transporterId?: string }> };
  for (const token of [f.tokens.carrierA, staff.dispatcherToken]) {
    assert.equal((await me(token)).organizations.find((org) => org.id === f.carrierA.org.id)?.transporterId, "29ABCDE1234F1Z5");
  }
  assert.equal(JSON.stringify(await me(staff.driverToken)).includes("29ABCDE1234F1Z5"), false, "a driver has no use for it");
  assert.equal(JSON.stringify(await me(f.tokens.carrierB)).includes("29ABCDE1234F1Z5"), false, "nor does another carrier");
});

test("a carrier can give its transporter ID at sign-up; a wrong one registers nothing; leaving it out is fine", async t => {
  const f = await httpFixture(t);
  const signUp = (phone: string, transporterId: unknown) => f.request("/v1/pilot/driver/register", "POST", {
    fullName: "Synthetic Carrier C", phone, orgDisplayName: "Synthetic Carrier C",
    vehicleRegistrationNumber: "KA05MN0001", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000, transporterId,
  });
  const wrong = await signUp("8000000017", "12345");
  assert.deepEqual([wrong.status, wrong.body.error, wrong.body.field, wrong.body.detail], [400, "invalid_transporter_id", "transporterId", transporterIdRule]);
  assert.equal([...f.store.users.values()].some((user) => user.phone === "8000000017"), false, "nothing was registered");

  const registered = await signUp("8000000017", "29 trnsp 1234 a1z7");
  assert.equal(registered.status, 201);
  assert.equal(f.store.organizations.get(registered.body.org.id as string)?.transporterId, "29TRNSP1234A1Z7");
  const owner = (await f.request("/v1/pilot/me", "GET", undefined, await f.login("8000000017"))).body as { organizations: Array<{ transporterId?: string }> };
  assert.equal(owner.organizations[0]?.transporterId, "29TRNSP1234A1Z7", "the new owner reads it back");

  for (const [phone, none] of [["8000000018", undefined], ["8000000019", ""], ["8000000020", null]] as Array<[string, unknown]>) {
    const withoutOne = await signUp(phone, none);
    assert.equal(withoutOne.status, 201, String(none));
    assert.equal(f.store.organizations.get(withoutOne.body.org.id as string)?.transporterId, undefined);
  }
});

test("the shipper's shipments carry the carrier's transporter ID from acceptance until delivery; public trips, carriers, ops, other shippers and ERP never do", async t => {
  const f = await httpFixture(t);
  assert.equal((await f.request(transporterIdRoute, "PATCH", { transporterId: "29ABCDE1234F1Z5" }, f.tokens.carrierA)).status, 200);
  const booking = await f.book();
  assert.deepEqual([booking.status, "carrierTransporterId" in booking.body.shipment], [201, false], "not in the booking reply: the carrier has not accepted");
  const id = booking.body.shipment.id as string;
  const get = (path: string, token?: string) => f.request(path, "GET", undefined, token);
  assert.equal("carrierTransporterId" in (await get(`/shipments/${id}`, f.tokens.shipperA)).body.shipment, false, "nor on the shipment before acceptance");
  assert.equal((await accept(f, id, undefined, f.tokens.carrierA)).status, 200);

  assert.equal((await get(`/shipments/${id}`, f.tokens.shipperA)).body.shipment.carrierTransporterId, "29ABCDE1234F1Z5");
  const listed = ((await get("/shipments", f.tokens.shipperA)).body.shipments as Array<{ id: string; carrierTransporterId?: string }>).find((shipment) => shipment.id === id);
  assert.equal(listed?.carrierTransporterId, "29ABCDE1234F1Z5");
  assert.equal((await get(`/shipments/${id}/tracking`, f.tokens.shipperA)).body.shipment.carrierTransporterId, "29ABCDE1234F1Z5");
  // A different GSTIN from the transporter ID, so the searches below find only the transporter ID.
  const bill = { kind: "BILL", billNumber: "123456789012", billDate: "2026-10-01", makerGstin: "27AAAAA0000A1Z5", invoiceNumber: "INV/1" };
  const billSaved = await f.request(`/shipments/${id}/eway-bill`, "POST", bill, f.tokens.shipperA);
  assert.deepEqual([billSaved.status, billSaved.body.shipment.carrierTransporterId], [200, "29ABCDE1234F1Z5"], "the e-way bill routes' replies too");

  const elsewhere: Array<[string, string | undefined]> = [
    ["/anchor-trips", undefined],
    [`/anchor-trips/${f.trip.id}`, undefined],
    ["/v1/pilot/carrier/shipments", f.tokens.carrierA],
    ["/v1/pilot/carrier/shipments", f.tokens.carrierB],
    ["/v1/pilot/me", f.tokens.carrierB],
    [`/ops/shipments/${id}`, f.tokens.ops],
    ["/shipments", f.tokens.shipperB],
    [`/shipments/${id}`, f.tokens.shipperB],
  ];
  for (const [path, token] of elsewhere) {
    assert.equal(JSON.stringify((await get(path, token)).body).includes("29ABCDE1234F1Z5"), false, path);
  }
  const erp = JSON.stringify([getIntegrationShipmentSnapshot(f.store, f.shipperA.org.id, id), getIntegrationShipmentTracking(f.store, f.shipperA.org.id, id)]);
  assert.deepEqual([erp.includes("TransporterId"), erp.includes("29ABCDE1234F1Z5")], [false, false], "ERP responses keep their shape, and never carry the ID");

  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal("carrierTransporterId" in (await get(`/shipments/${id}`, f.tokens.shipperA)).body.shipment, false, "gone once the driver confirms delivery");

  // A carrier with no transporter ID: the field is left out, not sent empty.
  const tripOfCarrierB = publishAnchorTrip(f.store, { carrierId: f.carrierB.org.id, originCity: "C", destCity: "D", windowStart: "2026-10-16", windowEnd: "2026-10-17", vehicleClass: "MEDIUM", capacityKg: 1000 });
  const onCarrierB = await f.book(f.tokens.shipperA, { anchorTripId: tripOfCarrierB.id });
  assert.equal(onCarrierB.status, 201);
  const onCarrierBId = onCarrierB.body.shipment.id as string;
  assert.equal((await accept(f, onCarrierBId, undefined, f.tokens.carrierB)).status, 200);
  assert.equal("carrierTransporterId" in (await get(`/shipments/${onCarrierBId}`, f.tokens.shipperA)).body.shipment, false);
});

test("accepting with a truck names it on a trip that names none: the truck only, the shipper sees it in the portal's form", async t => {
  const f = await httpFixture(t);
  const staff = await hireStaff(f);
  const id = await bookOnFixtureTrip(f);
  const accepted = await accept(f, id, { vehicleId: staff.driverTruckId }, staff.dispatcherToken);
  assert.deepEqual([accepted.status, accepted.body.shipment.status, accepted.body.shipment.assignedTruckNumber], [200, "BOOKED", "UP010345"]);
  const trip = loadStoreFromDisk(f.dataFilePath!).anchorTrips.get(f.trip.id);
  assert.deepEqual([trip?.assignedVehicleId, trip?.assignedDriverUserId], [staff.driverTruckId, undefined], "the driver stays as it was, and it is saved");
  assert.equal((await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperA)).body.shipment.assignedTruckNumber, "UP010345");
  const rows = [...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()].filter((event) => ["TRIP_ASSIGNED", "CARRIER_ACCEPTED"].includes(event.action));
  assert.deepEqual(rows.map((event) => [event.action, event.resourceId, event.previousState, event.newState]), [
    ["TRIP_ASSIGNED", f.trip.id, "UNASSIGNED", "ASSIGNED"],
    ["CARRIER_ACCEPTED", id, "PENDING_CARRIER_ACCEPT", "BOOKED"],
  ], "the truck is named first, then the booking is accepted");
  assert.equal(JSON.stringify(rows).includes(staff.driverTruckId), false, "state words only");
});

test("a truck outside the carrier's active fleet is refused and nothing is accepted; no body accepts as before; a refused acceptance names no truck", async t => {
  const f = await httpFixture(t);
  const staff = await hireStaff(f);
  const id = await bookOnFixtureTrip(f);
  f.store.vehicles.set(f.carrierA.vehicle.id, { ...f.carrierA.vehicle, inactiveAtUtcMs: Date.now() });
  const refusals: Array<[string, unknown]> = [
    ["another carrier's truck", f.carrierB.vehicle.id],
    ["no such truck", "no-such-truck"],
    ["an inactive truck", f.carrierA.vehicle.id],
    ["not a truck id", 42],
  ];
  for (const [what, vehicleId] of refusals) {
    const refused = await accept(f, id, { vehicleId }, f.tokens.carrierA);
    assert.deepEqual([refused.status, refused.body.error, refused.body.field, refused.body.detail], [400, "invalid_trip_assignment", "vehicleId", "Choose a truck from your own fleet."], what);
  }
  assert.equal(f.store.shipments.get(id)?.status, "PENDING_CARRIER_ACCEPT", "nothing was accepted");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, undefined, "and no truck was named");

  // The carrier's approval and the shipper's payment are checked before the truck, so neither refusal names one.
  const carrierOrg = f.store.organizations.get(f.carrierA.org.id)!;
  f.store.organizations.set(carrierOrg.id, { ...carrierOrg, kycStatus: "SUBMITTED" });
  const notApproved = await accept(f, id, { vehicleId: staff.driverTruckId }, f.tokens.carrierA);
  assert.deepEqual([notApproved.status, notApproved.body.error], [409, "carrier_compliance_required"]);
  f.store.organizations.set(carrierOrg.id, carrierOrg);
  const payment = f.store.payments.get(f.store.shipments.get(id)!.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, status: "CREATED" });
  const unpaid = await accept(f, id, { vehicleId: staff.driverTruckId }, f.tokens.carrierA);
  assert.deepEqual([unpaid.status, unpaid.body.error], [400, "checkout_not_completed_for_accept"]);
  f.store.payments.set(payment.id, payment);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, undefined, "a refusal before the truck check names no truck");

  const asBefore = await accept(f, id, undefined, f.tokens.carrierA);
  assert.deepEqual([asBefore.status, asBefore.body.shipment.status], [200, "BOOKED"], "an older app build sends no body");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, undefined, "and names no truck");

  const again = await accept(f, id, { vehicleId: staff.driverTruckId }, f.tokens.carrierA);
  assert.deepEqual([again.status, again.body.error], [400, "shipment_not_acceptable"]);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, undefined, "a booking that cannot be accepted names no truck either");
});

test("a vehicleId is ignored when the trip already names a truck, and when the caller is a driver", async t => {
  const f = await httpFixture(t);
  const staff = await hireStaff(f);
  f.store.anchorTrips.set(f.trip.id, { ...f.store.anchorTrips.get(f.trip.id)!, assignedVehicleId: staff.driverTruckId, assignedDriverUserId: staff.driverUserId });
  const onNamedTrip = await bookOnFixtureTrip(f);
  const kept = await accept(f, onNamedTrip, { vehicleId: f.carrierA.vehicle.id }, f.tokens.carrierA);
  assert.deepEqual([kept.status, kept.body.shipment.status], [200, "BOOKED"]);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, staff.driverTruckId, "the office changes a named truck on the trip screen");

  // A trip from before assignments existed: it names nobody, and the driver who started it keeps it.
  const legacyTrip = publishAnchorTrip(f.store, { carrierId: f.carrierA.org.id, originCity: "C", destCity: "D", windowStart: "2026-10-16", windowEnd: "2026-10-17", vehicleClass: "MEDIUM", capacityKg: 1000 });
  const onLegacyTrip = (await f.book(f.tokens.shipperA, { anchorTripId: legacyTrip.id })).body.shipment.id as string;
  f.store.anchorTrips.set(legacyTrip.id, { ...f.store.anchorTrips.get(legacyTrip.id)!, status: "IN_PROGRESS", startedByUserId: staff.driverUserId });
  const byDriver = await accept(f, onLegacyTrip, { vehicleId: staff.driverTruckId }, staff.driverToken);
  assert.deepEqual([byDriver.status, byDriver.body.shipment.status], [200, "BOOKED"]);
  assert.equal(f.store.anchorTrips.get(legacyTrip.id)?.assignedVehicleId, undefined, "a driver cannot name a truck");
});

test("truck numbers in the portal's form: the district padded to two digits and the number to four, ending where a space was typed; other shapes only cleaned", () => {
  const cases: Array<[string, string]> = [
    ["UP 1 345", "UP010345"],
    ["UP1345", "UP010345"],
    ["UP 32 345", "UP320345"],
    ["MH 12 345", "MH120345"],
    ["mh-12-345", "MH120345"],
    ["KA01AB1234", "KA01AB1234"],
    ["ka 01-ab 1234", "KA01AB1234"],
    ["MH12A1", "MH12A0001"],
    ["DL3CAB1234", "DL03CAB1234"],
    ["KA011234", "KA011234"],
    ["UP010345", "UP010345"],
    ["KA01123", "KA010123"],
    ["KA 01 123", "KA010123"],
    ["UP01345", "UP010345"],
    ["22 BH 1234 AA", "22BH1234AA"],
    ["KA01AB12345", "KA01AB12345"],
    ["TEST-A", "TESTA"],
  ];
  for (const [typed, portal] of cases) assert.equal(portalTruckNumber(typed), portal, typed);
});
