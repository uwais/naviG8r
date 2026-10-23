import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { ewayBillStartBlockReason } from "./ewayBillStartGate.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";
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
  assert.equal(ewayBillStartBlockReason(booked({ ...finalBill(), validUntilUtcMs: undefined }), "KA01AB1234", now), "expired");
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
