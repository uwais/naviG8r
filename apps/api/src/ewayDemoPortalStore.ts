/**
 * The practice e-way bill site's bills: held in memory, lost on restart, at most 500, with two seeded bills that
 * are never dropped.
 */
import { randomInt } from "node:crypto";
import { INDIA_OFFSET_MS, PERSONAS } from "./ewayDemoPortalRules.ts";
import type { DemoBill } from "./ewayDemoPortalRules.ts";

const MAX_BILLS = 500;
const SEEDED_BILL_NUMBER = "123456789012";
const SEEDED_TRUCK_BILL_NUMBER = "234567890123";
const SEEDED_BILL_NUMBERS = new Set([SEEDED_BILL_NUMBER, SEEDED_TRUCK_BILL_NUMBER]);
/** Fixed when the server starts; the demo seed reads it so the shipment and this site show the same valid-until. */
export const SEEDED_TRUCK_VALID_UNTIL_UTC_MS = Date.now() + 20 * 60 * 60 * 1000;
const SUPPLIER_GSTIN = PERSONAS[0].id;
const TRANSPORTER_ID = PERSONAS[1].id;

const billsByNumber = new Map<string, DemoBill>();

/**
 * The demo seed (scripts/rbac-manual.mjs) gives shipments load-a-with-bill and load-a-with-truck these exact
 * bills, so this site must know them too or ops' look-up would say no match. Change both together.
 * The truck bill's valid-until comes from server start, not from its distance: the seed only knows that time.
 */
function addSeededBills(): void {
  billsByNumber.set(SEEDED_BILL_NUMBER, {
    billNumber: SEEDED_BILL_NUMBER,
    billDate: "2026-10-01",
    generatedAtUtcMs: Date.UTC(2026, 9, 1) - INDIA_OFFSET_MS,
    generatorId: SUPPLIER_GSTIN,
    supplierGstin: SUPPLIER_GSTIN,
    recipientGstin: "29AAACS1234K1Z1",
    dispatchPin: "560022",
    deliveryPin: "570001",
    documentNumber: "SYN/2026/001",
    documentDate: "2026-10-01",
    goodsValueRupees: "75000",
    hsnCode: "8471",
    transportReason: "Supply",
    transporterId: TRANSPORTER_ID,
    distanceKm: 150,
    vehicleUpdates: [],
    extensions: [],
    validUpToUtcMs: null,
    cancelledAtUtcMs: null,
  });
  billsByNumber.set(SEEDED_TRUCK_BILL_NUMBER, {
    billNumber: SEEDED_TRUCK_BILL_NUMBER,
    billDate: "2026-10-02",
    generatedAtUtcMs: Date.UTC(2026, 9, 2) - INDIA_OFFSET_MS,
    generatorId: SUPPLIER_GSTIN,
    supplierGstin: SUPPLIER_GSTIN,
    recipientGstin: "33AAACT5678L1Z2",
    dispatchPin: "560100",
    deliveryPin: "641001",
    documentNumber: "SYN/2026/002",
    documentDate: "2026-10-02",
    goodsValueRupees: "240000",
    hsnCode: "8418",
    transportReason: "Supply",
    transporterId: TRANSPORTER_ID,
    distanceKm: 360,
    vehicleUpdates: [{ vehicleNumber: "KA01AB1234", reasonCode: "4", remark: "", byPersonaKey: "transporter", atUtcMs: Date.now() }],
    extensions: [],
    validUpToUtcMs: SEEDED_TRUCK_VALID_UNTIL_UTC_MS,
    cancelledAtUtcMs: null,
  });
}
addSeededBills();

export function findBill(billNumber: string): DemoBill | undefined {
  return billsByNumber.get(billNumber);
}

/** A Map keeps insertion order, so the first key that is not seeded is the oldest droppable bill. */
function dropOldestBill(): void {
  for (const billNumber of billsByNumber.keys()) {
    if (SEEDED_BILL_NUMBERS.has(billNumber)) continue;
    billsByNumber.delete(billNumber);
    return;
  }
}

/** A free random 12-digit number, or null if twenty tries all collided. */
export function newBillNumber(): string | null {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    let digits = String(randomInt(1, 10));
    for (let position = 1; position < 12; position += 1) digits += String(randomInt(0, 10));
    if (!billsByNumber.has(digits)) return digits;
  }
  return null;
}

export function addBill(bill: DemoBill): void {
  if (billsByNumber.size >= MAX_BILLS) dropOldestBill();
  billsByNumber.set(bill.billNumber, bill);
}
