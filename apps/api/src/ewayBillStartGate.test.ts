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
  const bookAndAccept = async (accept = true) => {
    const booking = await f.book(f.tokens.shipperA);
    assert.equal(booking.status, 201);
    const id = booking.body.shipment.id as string;
    if (accept) assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
    return id;
  };
  const first = await bookAndAccept();
  const second = await bookAndAccept();
  await bookAndAccept(false);
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
  ], "only accepted bookings count; the one waiting for acceptance does not");
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

/** Carrier A's trip with a hired driver and truck KA01AB1234, plus helpers to book, set a bill and start. */
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
  const noticesFor = (eventKey: string, userId: string) =>
    [...f.store.notifications.values()].filter((n) => n.eventKey === eventKey && n.recipientUserId === userId);
  return { f, hired, assign, bookAndAccept, setBill, start, noticesFor };
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

test("a refused start tells each blocking shipper once until they read it, saves the notice, and tells the carrier nothing", async t => {
  const { f, bookAndAccept, setBill, start, noticesFor } = await tripWithTruck(t);
  const shipmentId = await bookAndAccept();
  const ready = await bookAndAccept();
  setBill(ready, finalBill());
  assert.equal((await start()).status, 409);
  const first = noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id);
  assert.equal(first.length, 1, "only the shipment whose bill holds the trip");
  assert.equal(first[0].shipmentId, shipmentId);
  assert.equal(first[0].data?.title, "The trip is waiting for your e-way bill");
  assert.equal(first[0].data?.body, "Add the e-way bill for this shipment, or say none is needed.");
  const saved = loadStoreFromDisk(process.env.DATA_FILE!);
  assert.ok(saved.notifications.has(first[0].id), "the notice is saved although the start was refused");

  setBill(shipmentId, { ...finalBill(), validUntilUtcMs: Date.now() - 1000 });
  assert.equal((await start()).status, 409);
  assert.equal(noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id).length, 1, "no second notice while the first is unread");

  assert.equal((await f.request(`/v1/notifications/${first[0].id}/read`, "PATCH", {}, f.tokens.shipperA)).status, 200);
  assert.equal((await start()).status, 409);
  const after = noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.shipperA.user.id);
  assert.equal(after.length, 2, "read, so the next refusal tells them again");
  assert.equal(after.find((n) => n.id !== first[0].id)?.data?.body,
    "The valid-until time you entered has passed. Check the bill on the portal, then enter the new time here.");
  assert.equal(noticesFor(EWAY_BILL_HOLDS_START_EVENT, f.carrierA.user.id).length, 0, "the carrier tapped Start; it is not told");
  assert.ok(![...f.store.notifications.values()].some((n) => n.eventKey === EWAY_BILL_HOLDS_START_EVENT && n.recipientOrgId === f.carrierA.org.id));
});

test("changing the trip's truck tells only the shippers whose bill names another truck", async t => {
  const { f, hired, assign, bookAndAccept, setBill, noticesFor } = await tripWithTruck(t);
  const onOldTruck = await bookAndAccept();
  const onNewTruck = await bookAndAccept();
  const noTruckYet = await bookAndAccept();
  setBill(onOldTruck, finalBill("KA01AB1234"));
  setBill(onNewTruck, finalBill("ka 05 mn 4321"));
  setBill(noTruckYet, { kind: "BILL", billNumber: "123456789012", ...entered });
  const second = { ...hired.vehicle, id: "synthetic-second-truck", registrationNumber: "KA05MN4321" };
  f.store.vehicles.set(second.id, second);

  assert.equal((await assign(hired.vehicle.id)).status, 200);
  assert.equal(noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id).length, 0, "same truck, nothing changed");

  assert.equal((await assign(second.id)).status, 200);
  const notices = noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.shipperA.user.id);
  assert.deepEqual(notices.map((n) => n.shipmentId), [onOldTruck], "a bill already on the new truck, or with no truck, needs no change");
  assert.equal(notices[0].data?.body, "Synthetic Carrier A changed the truck to KA05MN4321. Update your e-way bill.");
  assert.equal(noticesFor(EWAY_BILL_TRUCK_CHANGED_EVENT, f.carrierA.user.id).length, 0, "the office made the change; it is not told");
});
