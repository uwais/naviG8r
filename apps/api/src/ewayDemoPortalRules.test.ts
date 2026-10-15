import assert from "node:assert/strict";
import { test } from "node:test";
import {
  PERSONAS, cancelRefusal, detailRefusal, extensionInputProblem, extensionRefusal, generateInputProblem, generateRefusal,
  isGstinShaped, parseDistanceKm, validUpToAfterVehicleUpdate, validUpToUtcMs, validityDays, vehicleInputProblem,
  vehicleUpdateRefusal, verifyBill,
} from "./ewayDemoPortalRules.ts";
import type { DemoBill, GenerateTyped } from "./ewayDemoPortalRules.ts";
import { formatIndiaDateTime } from "./ewayDemoPortalPages.ts";

const [supplier, transporter, someoneElse] = PERSONAS;
const otherTransporter = { ...transporter, id: "27TRNSP9999B1Z3", name: "Synthetic Carrier B" };
const HOUR_MS = 60 * 60 * 1000;

/** UTC milliseconds for a wall-clock time in India. */
function india(year: number, month: number, day: number, hour = 0, minute = 0): number {
  return Date.UTC(year, month - 1, day, hour, minute) - 5.5 * HOUR_MS;
}

/** 23:59:59.999 in India on that day, the instant a bill's validity ends. */
function lastInstantInIndia(year: number, month: number, day: number): number {
  return india(year, month, day, 23, 59) + 59_999;
}

function sampleBill(overrides: Partial<DemoBill> = {}): DemoBill {
  return {
    billNumber: "345678901234", billDate: "2026-10-14", generatedAtUtcMs: india(2026, 10, 14, 10), generatorId: supplier.id,
    supplierGstin: supplier.id, recipientGstin: "33AAACT5678L1Z2", dispatchPin: "560099", deliveryPin: "600032",
    documentNumber: "SYN/2026/101", documentDate: "2026-10-14", goodsValueRupees: "75000", hsnCode: "8471",
    transportReason: "Supply", transporterId: transporter.id, distanceKm: 350, vehicleUpdates: [], extensions: [],
    validUpToUtcMs: null, cancelledAtUtcMs: null, ...overrides,
  };
}

function withTransporterVehicle(bill: DemoBill, validUpToUtcMs: number): DemoBill {
  bill.vehicleUpdates.push({ vehicleNumber: "KA01AB1234", reasonCode: "4", remark: "", byPersonaKey: "transporter", atUtcMs: bill.generatedAtUtcMs });
  bill.validUpToUtcMs = validUpToUtcMs;
  return bill;
}

test("the persona ids are in the GSTIN shape", () => {
  for (const persona of PERSONAS) assert.ok(isGstinShaped(persona.id), persona.id);
});

test("validity is one day per 200 km or part of it, at least one day", () => {
  assert.deepEqual([1, 199, 200, 201, 400, 401, 4000].map(validityDays), [1, 1, 1, 2, 2, 3, 20]);
});

test("valid up to is the last instant of the day in India, the start date plus the days", () => {
  assert.equal(validUpToUtcMs(india(2026, 10, 14, 23, 50), 150), lastInstantInIndia(2026, 10, 15), "late on the 14th, one day");
  assert.equal(validUpToUtcMs(india(2026, 10, 14, 0, 5), 150), lastInstantInIndia(2026, 10, 15), "just after midnight, still one day to the 15th");
  assert.equal(validUpToUtcMs(india(2026, 10, 14, 10), 350), lastInstantInIndia(2026, 10, 16), "350 km, two days");
  assert.equal(validUpToUtcMs(india(2026, 10, 30, 10), 401), lastInstantInIndia(2026, 11, 2), "rolls into the next month");
  assert.equal(validUpToUtcMs(Date.UTC(2026, 9, 14, 20, 0), 100), lastInstantInIndia(2026, 10, 16), "20:00 UTC is already the 15th in India");
  assert.equal(formatIndiaDateTime(lastInstantInIndia(2026, 10, 16)), "16 Oct 2026, 23:59", "and it reads as 23:59");
});

test("a bill shown as valid up to 23:59 is still valid at 23:59:30 and expired at the next midnight", () => {
  const bill = withTransporterVehicle(sampleBill(), validUpToUtcMs(india(2026, 10, 14, 10), 350));
  const halfMinuteBeforeMidnight = india(2026, 10, 16, 23, 59) + 30_000;
  assert.equal(vehicleUpdateRefusal(bill, transporter, "1", halfMinuteBeforeMidnight), "");
  assert.match(extensionRefusal(bill, transporter, halfMinuteBeforeMidnight), /has not expired yet/);
  assert.match(vehicleUpdateRefusal(bill, transporter, "1", india(2026, 10, 17)), /has expired/);
  assert.equal(extensionRefusal(bill, transporter, india(2026, 10, 17)), "");
});

test("only the supplier or a transporter may generate", () => {
  assert.equal(generateRefusal(supplier), "");
  assert.equal(generateRefusal(transporter), "");
  assert.match(generateRefusal(someoneElse), /Only the supplier or a transporter can generate/);
});

test("generate form: shapes, own GSTIN for the supplier, and a vehicle or a transporter", () => {
  const now = india(2026, 10, 14, 12);
  const good: GenerateTyped = {
    supplierGstin: supplier.id, recipientGstin: "33AAACT5678L1Z2", dispatchPin: "560099", deliveryPin: "600032", documentNumber: "SYN/1",
    documentDate: "2026-10-14", goodsValueRupees: "75000", hsnCode: "8471", transportReason: "Supply", vehicleNumber: "", distanceKm: "350",
    transporterId: transporter.id,
  };
  assert.equal(generateInputProblem(good, supplier, now), "");
  assert.equal(generateInputProblem({ ...good, recipientGstin: "URP" }, supplier, now), "");
  assert.match(generateInputProblem({ ...good, supplierGstin: "27ABCDE1234F1Z5" }, supplier, now), /must be your own GSTIN/);
  assert.equal(generateInputProblem({ ...good, supplierGstin: "27ABCDE1234F1Z5" }, transporter, now), "", "a transporter generates for a supplier");
  assert.match(generateInputProblem({ ...good, dispatchPin: "012345" }, supplier, now), /A.2 Place of Dispatch/);
  assert.match(generateInputProblem({ ...good, documentDate: "2026-10-15" }, supplier, now), /cannot be in the future/);
  assert.match(generateInputProblem({ ...good, hsnCode: "84711" }, supplier, now), /HSN Code/);
  assert.match(generateInputProblem({ ...good, transportReason: "" }, supplier, now), /Reason for Transportation/);
  assert.match(generateInputProblem({ ...good, distanceKm: "4001" }, supplier, now), /from 1 to 4000/);
  assert.match(generateInputProblem({ ...good, transporterId: "" }, supplier, now), /Enter B.1 Vehicle Number, or name a Transporter ID/);
  assert.equal(generateInputProblem({ ...good, transporterId: "", vehicleNumber: "KA01AB1234" }, supplier, now), "");
  assert.equal(parseDistanceKm("0"), null);
  assert.equal(parseDistanceKm("12.5"), null);
  assert.equal(parseDistanceKm(" 350 "), 350);
});

test("vehicle update: generator or named transporter; First Time first; supplier blocked after the transporter", () => {
  const now = india(2026, 10, 14, 12);
  const bill = sampleBill();
  assert.equal(vehicleUpdateRefusal(bill, transporter, "4", now), "");
  assert.equal(vehicleUpdateRefusal(bill, supplier, "4", now), "", "the generator may do the first Part B");
  assert.match(vehicleUpdateRefusal(bill, someoneElse, "4", now), /Only whoever generated this bill, or the transporter it names/);
  assert.match(vehicleUpdateRefusal(bill, otherTransporter, "4", now), /names a different transporter/);
  assert.match(vehicleUpdateRefusal(bill, transporter, "1", now), /Choose First Time/);

  assert.equal(validUpToAfterVehicleUpdate(bill, now), lastInstantInIndia(2026, 10, 16), "first Part B starts validity from the stored 350 km");
  withTransporterVehicle(bill, india(2026, 10, 16, 23, 59));
  assert.equal(validUpToAfterVehicleUpdate(bill, india(2026, 10, 15, 9)), india(2026, 10, 16, 23, 59), "a later change keeps it");
  assert.match(vehicleUpdateRefusal(bill, transporter, "4", now), /already has a vehicle/);
  assert.equal(vehicleUpdateRefusal(bill, transporter, "1", now), "");
  assert.match(vehicleUpdateRefusal(bill, supplier, "1", now), /supplier can no longer change it/);
  assert.match(vehicleUpdateRefusal(bill, transporter, "1", india(2026, 10, 17, 0, 0)), /has expired/);
  assert.match(vehicleUpdateRefusal({ ...bill, cancelledAtUtcMs: now }, transporter, "1", now), /cancelled/);
});

test("a supplier who entered the first vehicle may change it until a transporter does", () => {
  const now = india(2026, 10, 14, 12);
  const bill = sampleBill({ validUpToUtcMs: india(2026, 10, 16, 23, 59) });
  bill.vehicleUpdates.push({ vehicleNumber: "KA01AB1234", reasonCode: "4", remark: "", byPersonaKey: "supplier", atUtcMs: now });
  assert.equal(vehicleUpdateRefusal(bill, supplier, "3", now), "");
});

test("vehicle and extension form shapes", () => {
  assert.equal(vehicleInputProblem("KA01AB1234", "1", ""), "");
  assert.match(vehicleInputProblem("AB12", "1", ""), /6 to 12 letters/);
  assert.match(vehicleInputProblem("KA01AB1234", "9", ""), /Choose a reason/);
  assert.match(vehicleInputProblem("KA01AB1234", "3", ""), /With Others as the reason, write a remark/);
  assert.equal(vehicleInputProblem("KA01AB1234", "3", "Tyre burst"), "");
  assert.equal(extensionInputProblem("ACCIDENT", "", "120"), "");
  assert.match(extensionInputProblem("", "", "120"), /Choose a reason for the extension/);
  assert.match(extensionInputProblem("OTHER", "", "120"), /write a remark/);
  assert.match(extensionInputProblem("ACCIDENT", "", "0"), /Remaining distance/);
});

test("extension: only the named transporter that updated Part B, only in the eight hours after expiry", () => {
  const expiry = india(2026, 10, 16, 23, 59);
  const bill = withTransporterVehicle(sampleBill(), expiry);
  assert.match(extensionRefusal(bill, transporter, expiry - 60_000), /has not expired yet. Practice rule/);
  assert.match(extensionRefusal(bill, transporter, expiry), /has not expired yet/, "the valid-up-to minute itself is still valid");
  assert.equal(extensionRefusal(bill, transporter, expiry + 60_000), "");
  assert.equal(extensionRefusal(bill, transporter, expiry + 8 * HOUR_MS), "", "the eighth hour is inside");
  assert.match(extensionRefusal(bill, transporter, expiry + 8 * HOUR_MS + 60_000), /eight hours after this bill expired have passed/);
  assert.match(extensionRefusal(bill, supplier, expiry + HOUR_MS), /Only the transporter named on this bill/);
  assert.match(extensionRefusal(bill, someoneElse, expiry + HOUR_MS), /Only the transporter named on this bill/);
  assert.match(extensionRefusal(bill, otherTransporter, expiry + HOUR_MS), /Only the transporter named on this bill/);

  const supplierVehicle = sampleBill({ validUpToUtcMs: expiry });
  supplierVehicle.vehicleUpdates.push({ vehicleNumber: "KA01AB1234", reasonCode: "4", remark: "", byPersonaKey: "supplier", atUtcMs: expiry - HOUR_MS });
  assert.match(extensionRefusal(supplierVehicle, transporter, expiry + HOUR_MS), /after it has updated the vehicle/);
  assert.match(extensionRefusal({ ...bill, cancelledAtUtcMs: expiry }, transporter, expiry + HOUR_MS), /cancelled/);
  assert.equal(validUpToUtcMs(expiry + HOUR_MS, 120), lastInstantInIndia(2026, 10, 18), "extended from 00:59 on the 17th over 120 km");
});

test("every refusal that states who may act or a time limit is marked as a practice rule", () => {
  const now = india(2026, 10, 14, 12);
  const expiry = india(2026, 10, 16, 23, 59);
  const updated = withTransporterVehicle(sampleBill(), expiry);
  const refusals = [
    generateRefusal(someoneElse),
    detailRefusal(sampleBill(), someoneElse),
    vehicleUpdateRefusal(sampleBill(), someoneElse, "4", now),
    vehicleUpdateRefusal(sampleBill(), otherTransporter, "4", now),
    vehicleUpdateRefusal(sampleBill(), transporter, "1", now),
    vehicleUpdateRefusal(updated, supplier, "1", now),
    vehicleUpdateRefusal(updated, transporter, "4", now),
    vehicleUpdateRefusal(updated, transporter, "1", expiry + 60_000),
    extensionRefusal(updated, supplier, expiry + HOUR_MS),
    extensionRefusal(updated, transporter, expiry - HOUR_MS),
    extensionRefusal(updated, transporter, expiry + 9 * HOUR_MS),
    cancelRefusal(sampleBill(), transporter, now),
    cancelRefusal(sampleBill(), supplier, now + 25 * HOUR_MS),
  ];
  for (const refusal of refusals) assert.match(refusal, /Practice rule: [A-Z]/, refusal);
});

test("a bill keeps at most 20 vehicle updates and 20 extensions, refused in plain words", () => {
  const expiry = india(2026, 10, 16, 23, 59);
  const full = withTransporterVehicle(sampleBill(), expiry);
  for (let count = 1; count < 20; count += 1) {
    full.vehicleUpdates.push({ vehicleNumber: "KA01AB1234", reasonCode: "1", remark: "", byPersonaKey: "transporter", atUtcMs: expiry - HOUR_MS });
  }
  assert.equal(full.vehicleUpdates.length, 20);
  assert.match(vehicleUpdateRefusal(full, transporter, "1", expiry - HOUR_MS), /already has 20 vehicle updates, the most this practice site keeps/);
  full.vehicleUpdates.pop();
  assert.equal(vehicleUpdateRefusal(full, transporter, "1", expiry - HOUR_MS), "", "the twentieth is still allowed");

  for (let count = 0; count < 20; count += 1) {
    full.extensions.push({ reasonCode: "ACCIDENT", remark: "", remainingDistanceKm: 10, atUtcMs: expiry, validUpToUtcMs: expiry });
  }
  assert.match(extensionRefusal(full, transporter, expiry + HOUR_MS), /already been extended 20 times, the most this practice site keeps/);
  full.extensions.pop();
  assert.equal(extensionRefusal(full, transporter, expiry + HOUR_MS), "", "the twentieth is still allowed");
});

test("cancel: the generator, within 24 hours of generation", () => {
  const bill = sampleBill();
  assert.equal(cancelRefusal(bill, supplier, bill.generatedAtUtcMs + 24 * HOUR_MS), "");
  assert.match(cancelRefusal(bill, supplier, bill.generatedAtUtcMs + 24 * HOUR_MS + 1), /more than 24 hours ago/);
  assert.match(cancelRefusal(bill, transporter, bill.generatedAtUtcMs + HOUR_MS), /Only whoever generated this bill can cancel it/);
  assert.match(cancelRefusal({ ...bill, cancelledAtUtcMs: 1 }, supplier, bill.generatedAtUtcMs + HOUR_MS), /already cancelled/);
});

test("details go to the supplier and the named transporter only", () => {
  const bill = sampleBill();
  assert.equal(detailRefusal(bill, supplier), "");
  assert.equal(detailRefusal(bill, transporter), "");
  assert.match(detailRefusal(bill, someoneElse), /Only the supplier on this bill and the transporter it names/);
  assert.match(detailRefusal(bill, otherTransporter), /You are neither/);
});

test("verify names the one detail that differs, and only when exactly one does", () => {
  const bill = sampleBill();
  const typed = { billNumber: bill.billNumber, billDate: "2026-10-14", supplierGstin: supplier.id.toLowerCase(), documentNumber: "SYN/2026/101" };
  assert.deepEqual(verifyBill(bill, typed), { outcome: "found", differingDetail: null });
  assert.deepEqual(verifyBill({ ...bill, cancelledAtUtcMs: 1 }, typed), { outcome: "cancelled", differingDetail: null });
  assert.deepEqual(verifyBill(bill, { ...typed, billDate: "2026-10-13" }), { outcome: "noMatch", differingDetail: "bill date" });
  assert.deepEqual(verifyBill(bill, { ...typed, supplierGstin: "27ABCDE1234F1Z5" }), { outcome: "noMatch", differingDetail: "supplier GSTIN" });
  assert.deepEqual(verifyBill(bill, { ...typed, documentNumber: "X" }), { outcome: "noMatch", differingDetail: "document number" });
  assert.deepEqual(verifyBill(bill, { ...typed, documentNumber: "X", billDate: "2026-10-13" }), { outcome: "noMatch", differingDetail: null });
  assert.deepEqual(verifyBill(undefined, typed), { outcome: "noMatch", differingDetail: null });
});
