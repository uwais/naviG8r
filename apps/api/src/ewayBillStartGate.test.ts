import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { ewayBillStartBlockReason } from "./ewayBillStartGate.ts";
import { EWAY_BILL_HOLDS_START_EVENT, EWAY_BILL_TRUCK_CHANGED_EVENT } from "./notifications.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";
import { markInactive } from "./softDelete.ts";
import type { EwayBill, Shipment } from "./types.ts";

const DAY_MS = 86400000;
const entered = { enteredAtUtcMs: 1, enteredByUserId: "synthetic" };
const finalBill = (truckNumber = "KA01AB1234"): EwayBill =>
  ({ kind: "BILL", billNumber: "123456789012", truckNumber, validUntilUtcMs: Date.now() + DAY_MS, ...entered });

test("the reason a booking's e-way bill holds the trip, or none when it is final", () => {
  const now = Date.now();
  const booked = (ewayBill?: EwayBill) => ({ status: "BOOKED", customerOrgName: "Synthetic Shipper A", ...(ewayBill ? { ewayBill } : {}) }) as Shipment;
  assert.equal(ewayBillStartBlockReason(booked(), "KA01AB1234", now), "no_bill");
  assert.equal(ewayBillStartBlockReason(booked({ kind: "BILL", billNumber: "123456789012", ...entered }), "KA01AB1234", now), "truck_missing");
  assert.equal(ewayBillStartBlockReason(booked(finalBill("KA02XY9999")), "KA01AB1234", now), "truck_differs");
  assert.equal(ewayBillStartBlockReason(booked(finalBill()), undefined, now), "truck_differs", "a trip with no truck matches no bill");
  assert.equal(ewayBillStartBlockReason(booked({ ...finalBill(), validUntilUtcMs: now }), "KA01AB1234", now), "expired");
  assert.equal(ewayBillStartBlockReason(booked({ ...finalBill(), validUntilUtcMs: undefined }), "KA01AB1234", now), "truck_missing",
    "the truck and its valid-until time are saved together, so no time means the truck is not added yet");
  const problem: EwayBill = { ...finalBill(), check: { result: "PROBLEM", problemReason: "CANCELLED", checkedAtUtcMs: 1, checkedByUserId: "synthetic" } };
  assert.equal(ewayBillStartBlockReason(booked(problem), "KA01AB1234", now), "problem");
  const found: EwayBill = { ...finalBill(), check: { result: "FOUND", checkedAtUtcMs: 1, checkedByUserId: "synthetic" } };
  assert.equal(ewayBillStartBlockReason(booked(found), "KA01AB1234", now), null);
  assert.equal(ewayBillStartBlockReason(booked(finalBill()), "KA01AB1234", now), null, "no ops check is needed");
  assert.equal(ewayBillStartBlockReason(booked(finalBill("ka 01 ab 1234")), "KA01AB1234", now), null, "compared in the portal form");
  assert.equal(ewayBillStartBlockReason(booked({ kind: "NOT_NEEDED", notNeededReason: "BELOW_THRESHOLD", ...entered }), undefined, now), null);
});

test("start is refused with one line per booking whose bill is not final, names no money, and works once every bill is final", async t => {
  const f = await httpFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver One", phone: "8000000013" });
  const hired = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA01AB1234", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const driverToken = await f.login("8000000013");
  const assigned = await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: hired.vehicle.id, driverUserId: hired.user.id }, f.tokens.carrierA);
  assert.equal(assigned.status, 200);
  const bookAndAccept = async () => {
    const booking = await f.book(f.tokens.shipperA);
    assert.equal(booking.status, 201);
    const id = booking.body.shipment.id as string;
    assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
    return id;
  };
  const first = await bookAndAccept();
  const second = await bookAndAccept();
  const setBill = (shipmentId: string, ewayBill: EwayBill) =>
    f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, ewayBill });
  const start = (token = driverToken) => f.request(`/v1/pilot/anchor-trips/${f.trip.id}/start`, "POST", {}, token);

  const refused = await start();
  assert.equal(refused.status, 409);
  assert.deepEqual(Object.keys(refused.body).sort(), ["error", "shipments"]);
  assert.equal(refused.body.error, "eway_bill_not_ready");
  assert.deepEqual(refused.body.shipments, [
    { shipmentId: first, shipperName: "Synthetic Shipper A", reason: "no_bill" },
    { shipmentId: second, shipperName: "Synthetic Shipper A", reason: "no_bill" },
  ]);
  assert.ok(!/paise|amount|net|gross|commission|payment/i.test(JSON.stringify(refused.body)), "no money in the refusal");

  setBill(second, finalBill());
  const cases: Array<[EwayBill, string]> = [
    [{ kind: "BILL", billNumber: "123456789012", ...entered }, "truck_missing"],
    [finalBill("KA02XY9999"), "truck_differs"],
    [{ ...finalBill(), validUntilUtcMs: Date.now() - 1000 }, "expired"],
    [{ ...finalBill(), check: { result: "PROBLEM", problemReason: "NOT_FOUND", checkedAtUtcMs: 1, checkedByUserId: "synthetic" } }, "problem"],
  ];
  for (const [bill, reason] of cases) {
    setBill(first, bill);
    const answer = await start();
    assert.equal(answer.status, 409, reason);
    assert.deepEqual(answer.body.shipments, [{ shipmentId: first, shipperName: "Synthetic Shipper A", reason }]);
  }
  assert.equal((await start(f.tokens.carrierA)).body.error, "eway_bill_not_ready", "the owner is held the same way");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "OPEN", "a refused start changes nothing");

  setBill(first, { kind: "NOT_NEEDED", notNeededReason: "GOODS_EXEMPT", ...entered });
  const started = await start();
  assert.equal(started.status, 200);
  assert.equal(started.body.trip.status, "IN_PROGRESS");
});

/** Carrier A's trip with a hired driver and truck KA01AB1234, plus helpers to book, set a bill, start and remind. */
async function tripWithTruck(t: Parameters<typeof httpFixture>[0]) {
  const f = await httpFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver One", phone: "8000000013" });
  const hired = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA01AB1234", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const assign = (vehicleId: string) => f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId, driverUserId: hired.user.id }, f.tokens.carrierA);
  assert.equal((await assign(hired.vehicle.id)).status, 200);
  const bookAndAccept = async () => {
    const booking = await f.book(f.tokens.shipperA);
    assert.equal(booking.status, 201);
    const id = booking.body.shipment.id as string;
    assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
    return id;
  };
  const setBill = (shipmentId: string, ewayBill: EwayBill) =>
    f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, ewayBill });
  const start = () => f.request(`/v1/pilot/anchor-trips/${f.trip.id}/start`, "POST", {}, f.tokens.carrierA);
  const remind = (shipmentId: string, token = f.tokens.carrierA) =>
    f.request(`/v1/pilot/anchor-trips/${f.trip.id}/shipments/${shipmentId}/eway-bill-reminder`, "POST", {}, token);
  const noticesFor = (eventKey: string, userId: string) =>
    [...f.store.notifications.values()].filter((n) => n.eventKey === eventKey && n.recipientUserId === userId);
  return { f, hired, assign, bookAndAccept, setBill, start, remind, noticesFor };
}

test("a deleted booking neither holds the start nor counts as the accepted one", async t => {
  const { f, bookAndAccept, setBill, start } = await tripWithTruck(t);
  const deleted = await bookAndAccept();
  const deleteBooking = () => f.store.shipments.set(deleted, markInactive(f.store.shipments.get(deleted)!, Date.now(), "synthetic"));
  // No bill and no payment the start would take: both checks would refuse it if they read this booking.
  f.store.shipments.set(deleted, { ...f.store.shipments.get(deleted)!, paymentId: "missing-payment" });
  deleteBooking();
  assert.equal((await start()).body.error, "no_accepted_shipments", "only a deleted booking is accepted");
  const kept = await bookAndAccept();
  setBill(kept, finalBill());
  const started = await start();
  assert.equal(started.status, 200);
  assert.equal(started.body.trip.status, "IN_PROGRESS");
});

test("a booking waiting for the carrier holds the start, listed before the bills, until it is accepted", async t => {
  const { f, bookAndAccept, setBill, start } = await tripWithTruck(t);
  const accepted = await bookAndAccept();
  setBill(accepted, finalBill());
  const waiting = (await f.book(f.tokens.shipperA)).body.shipment.id as string;

  const refused = await start();
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, "eway_bill_not_ready");
  assert.deepEqual(refused.body.shipments, [{ shipmentId: waiting, shipperName: "Synthetic Shipper A", reason: "waiting_for_accept" }]);
  assert.ok(!/paise|amount|net|gross|commission|payment/i.test(JSON.stringify(refused.body)), "no money in the refusal");

  setBill(accepted, { kind: "BILL", billNumber: "123456789012", ...entered });
  assert.deepEqual((await start()).body.shipments.map((s: { reason: string }) => s.reason), ["waiting_for_accept", "truck_missing"],
    "the carrier's own step first, then the bills");
  setBill(accepted, finalBill());

  const listed = await f.request("/v1/pilot/carrier/shipments", "GET", undefined, f.tokens.carrierA);
  const byId = new Map(listed.body.shipments.map((s: { id: string }) => [s.id, s]));
  assert.equal((byId.get(waiting) as { readyToAccept?: boolean }).readyToAccept, true);
  assert.equal("readyToAccept" in (byId.get(accepted) as object), false, "only a booking waiting for the carrier says it");
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.status, "OPEN", "a refused start changes nothing");

  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${waiting}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  setBill(waiting, finalBill());
  const started = await start();
  assert.equal(started.status, 200);
  assert.equal(started.body.trip.status, "IN_PROGRESS");
});

test("a booking whose checkout is not done does not hold the start, and once the trip starts no booking is accepted", async t => {
  const { f, bookAndAccept, setBill, start } = await tripWithTruck(t);
  const accepted = await bookAndAccept();
  setBill(accepted, finalBill());
  const unpaid = (await f.book(f.tokens.shipperA)).body.shipment.id as string;
  const failed = (await f.book(f.tokens.shipperA)).body.shipment.id as string;
  const setPayment = (shipmentId: string, status: "CREATED" | "FAILED" | "AUTHORIZED") => {
    const pay = f.store.payments.get(f.store.shipments.get(shipmentId)!.paymentId)!;
    f.store.payments.set(pay.id, { ...pay, status });
  };
  setPayment(unpaid, "CREATED");
  setPayment(failed, "FAILED");

  const listed = await f.request("/v1/pilot/carrier/shipments", "GET", undefined, f.tokens.carrierA);
  for (const id of [unpaid, failed]) {
    assert.equal(listed.body.shipments.find((s: { id: string }) => s.id === id).readyToAccept, false);
  }
  const started = await start();
  assert.equal(started.status, 200, "only the shipper can finish paying, so these do not hold the trip");
  assert.equal(started.body.trip.status, "IN_PROGRESS");

  // The shipper finishes paying after the trip has left: the booking still cannot join it.
  setPayment(unpaid, "AUTHORIZED");
  const accept = () => f.request(`/v1/pilot/carrier/shipments/${unpaid}/accept`, "POST", {}, f.tokens.carrierA);
  const refused = await accept();
  assert.equal(refused.status, 409);
  assert.deepEqual(refused.body, { error: "trip_already_started", detail: "This trip is already on the way, so it cannot take this booking." });
  assert.equal(f.store.shipments.get(unpaid)?.status, "PENDING_CARRIER_ACCEPT", "nothing changed");

  f.store.anchorTrips.set(f.trip.id, { ...f.store.anchorTrips.get(f.trip.id)!, status: "COMPLETED" });
  assert.equal((await accept()).body.error, "trip_already_started", "a finished trip is refused the same way");
});

test("a refused start tells no shipper: the office reminds them with Remind", async t => {
  const { f, bookAndAccept, start } = await tripWithTruck(t);
  await bookAndAccept();
  assert.equal((await start()).status, 409);
  assert.equal([...f.store.notifications.values()].filter((n) => n.eventKey === EWAY_BILL_HOLDS_START_EVENT).length, 0);
});

test("only the trip's own carrier office may send a reminder", async t => {
  const { f, bookAndAccept, remind } = await tripWithTruck(t);
  const shipmentId = await bookAndAccept();
  const driverToken = await f.login("8000000013");
  for (const [who, token] of [["the shipper", f.tokens.shipperA], ["the trip's driver", driverToken], ["another carrier", f.tokens.carrierB], ["ops", f.tokens.ops]] as const) {
    const refused = await remind(shipmentId, token);
    assert.ok(refused.status === 403 || refused.status === 404, `${who} is refused, got ${refused.status}`);
  }
  assert.equal([...f.store.notifications.values()].filter((n) => n.eventKey === EWAY_BILL_HOLDS_START_EVENT).length, 0, "a refused request sends nothing");
  const sent = await remind(shipmentId);
  assert.equal(sent.status, 200);
  assert.deepEqual(sent.body, { sent: true });
});

test("a reminder tells the shipper why once, until they read it or the reason changes", async t => {
  const { f, bookAndAccept, setBill, remind, noticesFor } = await tripWithTruck(t);
  const shipmentId = await bookAndAccept();
  const ready = await bookAndAccept();
  setBill(ready, finalBill());

  assert.deepEqual((await remind(shipmentId)).body, { sent: true });
  const first = noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id);
  assert.equal(first.length, 1);
  assert.equal(first[0].shipmentId, shipmentId);
  assert.equal(first[0].data?.title, "The trip is waiting for your e-way bill");
  assert.equal(first[0].data?.body, "Add the e-way bill for this shipment, or say none is needed.");
  assert.equal(first[0].data?.reason, "no_bill");
  assert.ok(loadStoreFromDisk(process.env.DATA_FILE!).notifications.has(first[0].id), "the reminder is saved");

  assert.deepEqual((await remind(shipmentId)).body, { sent: false }, "the same reason, still unread");
  assert.equal(noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id).length, 1);

  setBill(shipmentId, { ...finalBill(), validUntilUtcMs: Date.now() - 1000 });
  assert.deepEqual((await remind(shipmentId)).body, { sent: true }, "a new reason is sent");
  const afterChange = noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id);
  assert.equal(afterChange.length, 2);
  assert.ok(afterChange.find((n) => n.id === first[0].id)?.readAtUtcMs != null, "the out-of-date reminder is marked read");
  const second = afterChange.find((n) => n.id !== first[0].id)!;
  assert.equal(second.readAtUtcMs, undefined);
  assert.equal(second.data?.reason, "expired");
  assert.equal(second.data?.body, "The valid-until time you entered has passed. Check the bill on the portal, then enter the new time here.");

  assert.equal((await f.request(`/v1/notifications/${second.id}/read`, "PATCH", {}, f.tokens.shipperA)).status, 200);
  assert.deepEqual((await remind(shipmentId)).body, { sent: true }, "read, so the office can remind again");
  assert.equal(noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id).length, 3);
  assert.equal(noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.carrierA.user.id).length, 0, "the office sent it; it is not told");
  assert.ok(![...f.store.notifications.values()].some((n) => n.eventKey === EWAY_BILL_HOLDS_START_EVENT && n.recipientOrgId === f.carrierA.org.id));
});

test("a reminder is refused for a booking that does not hold the start, or one not on the trip", async t => {
  const { f, bookAndAccept, setBill, remind } = await tripWithTruck(t);
  const shipmentId = await bookAndAccept();
  setBill(shipmentId, finalBill());
  const refused = await remind(shipmentId);
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, "eway_bill_not_holding_start");
  const waiting = await f.book(f.tokens.shipperA);
  assert.equal((await remind(waiting.body.shipment.id)).body.error, "eway_bill_not_holding_start", "a booking not accepted yet holds nothing");
  assert.equal((await remind("no-such-shipment")).status, 404);
  assert.equal([...f.store.notifications.values()].filter((n) => n.eventKey === EWAY_BILL_HOLDS_START_EVENT).length, 0);
});

test("no reminder for a different truck while the trip has no truck: the office chooses one first", async t => {
  const f = await httpFixture(t);
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, undefined);
  const booking = await f.book(f.tokens.shipperA);
  const shipmentId = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, ewayBill: finalBill() });
  const refused = await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/shipments/${shipmentId}/eway-bill-reminder`, "POST", {}, f.tokens.carrierA);
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, "trip_has_no_truck");
  assert.equal([...f.store.notifications.values()].filter((n) => n.eventKey === EWAY_BILL_HOLDS_START_EVENT).length, 0);
});

test("the first truck chosen for a trip tells no shipper", async t => {
  const f = await httpFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver One", phone: "8000000013" });
  const hired = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA01AB1234", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  assert.equal(f.store.anchorTrips.get(f.trip.id)?.assignedVehicleId, undefined);
  const booking = await f.book(f.tokens.shipperA);
  const shipmentId = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, ewayBill: finalBill("KA02XY9999") });
  const assigned = await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: hired.vehicle.id, driverUserId: hired.user.id }, f.tokens.carrierA);
  assert.equal(assigned.status, 200);
  assert.equal([...f.store.notifications.values()].filter((n) => n.eventKey === EWAY_BILL_TRUCK_CHANGED_EVENT).length, 0);
});

test("changing the trip's truck tells only the shippers whose bill names another truck, and keeps one unread notice each", async t => {
  const { f, hired, assign, bookAndAccept, setBill, noticesFor } = await tripWithTruck(t);
  const onOldTruck = await bookAndAccept();
  const onNewTruck = await bookAndAccept();
  const noTruckYet = await bookAndAccept();
  setBill(onOldTruck, finalBill("KA01AB1234"));
  setBill(onNewTruck, finalBill("ka 05 mn 4321"));
  setBill(noTruckYet, { kind: "BILL", billNumber: "123456789012", ...entered });
  const second = { ...hired.vehicle, id: "synthetic-second-truck", registrationNumber: "KA05MN4321" };
  const third = { ...hired.vehicle, id: "synthetic-third-truck", registrationNumber: "KA09ZZ0001" };
  f.store.vehicles.set(second.id, second);
  f.store.vehicles.set(third.id, third);
  const unread = (shipmentId: string) => noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id).filter((n) => n.shipmentId === shipmentId && n.readAtUtcMs == null);

  assert.equal((await assign(hired.vehicle.id)).status, 200);
  assert.equal(noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id).length, 0, "same truck, nothing changed");

  assert.equal((await assign(second.id)).status, 200);
  const notices = noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id);
  assert.deepEqual(notices.map((n) => n.shipmentId), [onOldTruck], "a bill already on the new truck, or with no truck, needs no change");
  assert.equal(notices[0].data?.title, "The truck on your trip is different from your e-way bill");
  assert.equal(notices[0].data?.body, "Synthetic Carrier A set the truck on this trip to KA05MN4321. Your e-way bill has KA01AB1234. "
    + "Ask Synthetic Carrier A which is right. If the bill is wrong, fix it on the portal, then here.");
  assert.equal(noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.carrierA.user.id).length, 0, "the office made the change; it is not told");

  assert.equal((await assign(third.id)).status, 200);
  assert.equal(unread(onOldTruck).length, 1, "the earlier notice is marked read before the new one");
  assert.match(String(unread(onOldTruck)[0].data?.body), /to KA09ZZ0001\. Your e-way bill has KA01AB1234\./);
  assert.equal(unread(onNewTruck).length, 1);
  assert.match(String(unread(onNewTruck)[0].data?.body), /Your e-way bill has KA05MN4321\./, "the bill's truck in the portal form");

  const sentBefore = noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id).length;
  assert.equal((await assign(hired.vehicle.id)).status, 200);
  assert.equal(unread(onOldTruck).length, 0, "back on the bill's truck: its notices are marked read");
  assert.equal(unread(onNewTruck).length, 1);
  assert.equal(noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id).length, sentBefore + 1, "nothing is sent for the bill the trip is back on");
});

test("a truck notice never shows the carrier's id when the carrier has no name", async t => {
  const { f, hired, assign, bookAndAccept, setBill, noticesFor } = await tripWithTruck(t);
  const shipmentId = await bookAndAccept();
  setBill(shipmentId, finalBill("KA01AB1234"));
  const second = { ...hired.vehicle, id: "synthetic-second-truck", registrationNumber: "KA05MN4321" };
  f.store.vehicles.set(second.id, second);
  const { displayName: _name, ...nameless } = f.store.organizations.get(f.carrierA.org.id)!;
  f.store.organizations.set(f.carrierA.org.id, nameless as typeof f.carrierA.org);
  assert.equal((await assign(second.id)).status, 200);
  const [notice] = noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id);
  assert.equal(notice.data?.body, "Your carrier set the truck on this trip to KA05MN4321. Your e-way bill has KA01AB1234. "
    + "Ask your carrier which is right. If the bill is wrong, fix it on the portal, then here.");
  assert.ok(!String(notice.data?.body).includes(f.carrierA.org.id));
});
