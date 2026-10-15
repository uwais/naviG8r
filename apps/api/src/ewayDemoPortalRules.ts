/**
 * The practice e-way bill site's rules: who may do what to a bill, how long a bill stays valid, and what a typed
 * form must look like. Pure functions over a bill and a time, so every rule can be tested with fixed clocks.
 *
 * Sources are CGST Rule 138 as substituted by Notification 12/2018, amended by 31/2019 and 94/2020. Where a rule
 * here goes beyond that text it is marked "assumed", and the guide page lists each one.
 */
// The date, GSTIN, invoice and truck shapes are the app's own, so for those four the practice site refuses exactly what the app refuses.
import { isGstinShaped, isInvoiceNumberShaped, isRealCalendarDate, isTruckNumberShaped } from "./ewayBillValidation.ts";

export type PersonaKey = "supplier" | "transporter" | "other";
export type Persona = { key: PersonaKey; role: string; name: string; idLabel: "GSTIN" | "Transporter ID"; id: string };

export const PERSONAS: readonly Persona[] = [
  { key: "supplier", role: "Supplier", name: "Synthetic Shipper A", idLabel: "GSTIN", id: "29ABCDE1234F1Z5" },
  { key: "transporter", role: "Transporter", name: "Synthetic Carrier A", idLabel: "Transporter ID", id: "29TRNSP1234A1Z7" },
  { key: "other", role: "Someone else", name: "Synthetic Other Business", idLabel: "GSTIN", id: "07OTHER1234B1Z2" },
];

export function personaFromKey(key: string | undefined): Persona | null {
  return PERSONAS.find((persona) => persona.key === key) ?? null;
}

export const VEHICLE_UPDATE_REASONS: readonly { code: string; words: string }[] = [
  { code: "1", words: "Break Down" },
  { code: "2", words: "Transhipment" },
  { code: "3", words: "Others" },
  { code: "4", words: "First Time" },
];
const FIRST_TIME = "4";
const OTHERS = "3";

export const EXTENSION_REASONS: readonly { code: string; words: string }[] = [
  { code: "NATURAL_CALAMITY", words: "Natural calamity" },
  { code: "LAW_AND_ORDER", words: "Law and order" },
  { code: "TRANSHIPMENT_DELAY", words: "Transhipment delay" },
  { code: "ACCIDENT", words: "Accident" },
  { code: "OTHER", words: "Other" },
];

/** The reason list on the real Part A form, as third-party guides show it; not from the notifications. */
export const TRANSPORT_REASONS: readonly string[] = [
  "Supply", "Export or Import", "Job Work", "SKD/CKD/Lots", "Recipient Not Known", "For Own Use", "Exhibition or Fairs", "Line Sales", "Others",
];

export type VehicleUpdate = { vehicleNumber: string; reasonCode: string; remark: string; byPersonaKey: PersonaKey; atUtcMs: number };
export type Extension = { reasonCode: string; remark: string; remainingDistanceKm: number; atUtcMs: number; validUpToUtcMs: number };

export type DemoBill = {
  billNumber: string;
  billDate: string;
  generatedAtUtcMs: number;
  generatorId: string;
  supplierGstin: string;
  recipientGstin: string;
  dispatchPin: string;
  deliveryPin: string;
  documentNumber: string;
  documentDate: string;
  goodsValueRupees: string;
  hsnCode: string;
  transportReason: string;
  transporterId: string;
  distanceKm: number;
  vehicleUpdates: VehicleUpdate[];
  extensions: Extension[];
  validUpToUtcMs: number | null;
  cancelledAtUtcMs: number | null;
};

export const INDIA_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const KM_PER_DAY = 200;
/** Assumed cap: keeps the longest validity at 20 days, inside the app's 30-day limit on a typed valid-until. */
export const MAX_DISTANCE_KM = 4000;
const EXTENSION_WINDOW_MS = 8 * HOUR_MS;
const CANCEL_WINDOW_MS = 24 * HOUR_MS;
/** A practice-site limit, not a portal rule: bills live in memory, so one bill cannot grow without end. */
export const MAX_ENTRIES_PER_LIST = 20;

export function indiaDateIso(utcMs: number): string {
  return new Date(utcMs + INDIA_OFFSET_MS).toISOString().slice(0, 10);
}

/** Notification 94/2020: one day per 200 km or part of it, from 1 Jan 2021. */
export function validityDays(distanceKm: number): number {
  return Math.max(1, Math.ceil(distanceKm / KM_PER_DAY));
}

/**
 * Explanation 1 to rule 138(10): the first day expires at midnight of the day after the start date, and each
 * further day adds one. Stored as the last millisecond of that day in India, 23:59:59.999: pages show it as 23:59,
 * the way the app's valid-until picker does, and a bill read as "valid up to 23:59" must not expire at 23:59:30.
 */
export function validUpToUtcMs(startUtcMs: number, distanceKm: number): number {
  const start = new Date(startUtcMs + INDIA_OFFSET_MS);
  const lastDay = start.getUTCDate() + validityDays(distanceKm);
  return Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), lastDay, 23, 59, 59, 999) - INDIA_OFFSET_MS;
}

export function transporterName(transporterId: string): string {
  const transporter = PERSONAS.find((persona) => persona.key === "transporter" && persona.id === transporterId);
  return transporter ? transporter.name : "";
}

export function currentVehicle(bill: DemoBill): string | null {
  return bill.vehicleUpdates.length > 0 ? bill.vehicleUpdates[bill.vehicleUpdates.length - 1].vehicleNumber : null;
}

function isGenerator(bill: DemoBill, persona: Persona): boolean {
  return persona.id === bill.generatorId;
}

function isNamedTransporter(bill: DemoBill, persona: Persona): boolean {
  return persona.key === "transporter" && persona.id === bill.transporterId;
}

function transporterHasUpdatedPartB(bill: DemoBill): boolean {
  return bill.vehicleUpdates.some((update) => update.byPersonaKey === "transporter");
}

/** Supplier and named transporter only. The real portal also shows a bill to its recipient; no persona here is one. */
export function detailRefusal(bill: DemoBill, persona: Persona): string {
  if (persona.key === "supplier" && persona.id === bill.supplierGstin) return "";
  if (isNamedTransporter(bill, persona) || isGenerator(bill, persona)) return "";
  return "Practice rule: Only the supplier on this bill and the transporter it names can see its details. You are neither.";
}

/** Rule 138(1) and its first proviso, 138(3). Refusing everyone else is a practice simplification. */
export function generateRefusal(persona: Persona): string {
  if (persona.key === "other") {
    return "Practice rule: Only the supplier or a transporter can generate an e-way bill here. Switch user to Supplier or Transporter.";
  }
  return "";
}

/** Rule 138(5) and 138(5A) proviso; blocking the supplier after a transporter's update is this site's reading. */
export function vehicleUpdateRefusal(bill: DemoBill, persona: Persona, reasonCode: string, nowUtcMs: number): string {
  if (bill.cancelledAtUtcMs !== null) return "This bill was cancelled. A cancelled bill cannot be changed.";
  if (!isGenerator(bill, persona) && !isNamedTransporter(bill, persona)) {
    return persona.key === "transporter"
      ? "This bill names a different transporter. Practice rule: Only the transporter it names, or whoever generated it, can update its vehicle."
      : "Practice rule: Only whoever generated this bill, or the transporter it names, can update its vehicle.";
  }
  if (persona.key === "supplier" && transporterHasUpdatedPartB(bill)) {
    return "The transporter has already updated the vehicle on this bill. Practice rule: After that, the supplier can no longer change it.";
  }
  if (bill.vehicleUpdates.length >= MAX_ENTRIES_PER_LIST) {
    return `This bill already has ${MAX_ENTRIES_PER_LIST} vehicle updates, the most this practice site keeps. Generate a new bill to keep practising.`;
  }
  if (bill.validUpToUtcMs !== null && nowUtcMs > bill.validUpToUtcMs) {
    return "This bill has expired. Practice rule: An expired bill's vehicle cannot be changed; the transporter can extend it in the eight hours after it expires.";
  }
  const isFirst = bill.vehicleUpdates.length === 0;
  if (isFirst && reasonCode !== FIRST_TIME) return "This bill has no vehicle yet. Practice rule: Choose First Time as the reason.";
  if (!isFirst && reasonCode === FIRST_TIME) return "This bill already has a vehicle. Practice rule: Choose Break Down, Transhipment or Others.";
  return "";
}

/** The first vehicle starts the validity from the stored distance; a later change keeps it. */
export function validUpToAfterVehicleUpdate(bill: DemoBill, nowUtcMs: number): number {
  if (bill.vehicleUpdates.length === 0 || bill.validUpToUtcMs === null) return validUpToUtcMs(nowUtcMs, bill.distanceKm);
  return bill.validUpToUtcMs;
}

/** Rule 138(10) second proviso (the transporter) and Notification 31/2019 (within eight hours from expiry). */
export function extensionRefusal(bill: DemoBill, persona: Persona, nowUtcMs: number): string {
  if (bill.cancelledAtUtcMs !== null) return "This bill was cancelled. A cancelled bill cannot be extended.";
  if (!isNamedTransporter(bill, persona) || !bill.vehicleUpdates.some((update) => update.byPersonaKey === "transporter")) {
    return "Practice rule: Only the transporter named on this bill, after it has updated the vehicle, can extend it.";
  }
  if (bill.extensions.length >= MAX_ENTRIES_PER_LIST) {
    return `This bill has already been extended ${MAX_ENTRIES_PER_LIST} times, the most this practice site keeps. Generate a new bill to keep practising.`;
  }
  if (bill.validUpToUtcMs === null) return "This bill has no vehicle yet, so it has no validity to extend.";
  if (nowUtcMs <= bill.validUpToUtcMs) {
    return "This bill has not expired yet. Practice rule: A bill can be extended only in the eight hours after it expires.";
  }
  if (nowUtcMs > bill.validUpToUtcMs + EXTENSION_WINDOW_MS) {
    return "The eight hours after this bill expired have passed. Practice rule: After that, it can no longer be extended.";
  }
  return "";
}

/** Rule 138(9). The rule names no one; letting only the generator cancel is assumed. */
export function cancelRefusal(bill: DemoBill, persona: Persona, nowUtcMs: number): string {
  if (bill.cancelledAtUtcMs !== null) return "This bill is already cancelled.";
  if (!isGenerator(bill, persona)) return "Practice rule: Only whoever generated this bill can cancel it.";
  if (nowUtcMs - bill.generatedAtUtcMs > CANCEL_WINDOW_MS) {
    return "This bill was generated more than 24 hours ago. Practice rule: A bill can be cancelled only within 24 hours of generation.";
  }
  return "";
}

// ---------- the four details ops looks a bill up by ----------

export type VerifyTyped = { billNumber: string; billDate: string; supplierGstin: string; documentNumber: string };
export type VerifyResult = { outcome: "found" | "cancelled" | "noMatch"; differingDetail: string | null };

export function cleanBillNumber(text: string): string {
  return text.replace(/[\s-]/g, "");
}

export function verifyBill(bill: DemoBill | undefined, typed: VerifyTyped): VerifyResult {
  if (!bill) return { outcome: "noMatch", differingDetail: null };
  const differing: string[] = [];
  if (bill.billDate !== typed.billDate.trim()) differing.push("bill date");
  if (bill.supplierGstin !== typed.supplierGstin.replace(/\s/g, "").toUpperCase()) differing.push("supplier GSTIN");
  if (bill.documentNumber !== typed.documentNumber.trim()) differing.push("document number");
  if (differing.length === 1) return { outcome: "noMatch", differingDetail: differing[0] };
  if (differing.length > 1) return { outcome: "noMatch", differingDetail: null };
  return { outcome: bill.cancelledAtUtcMs === null ? "found" : "cancelled", differingDetail: null };
}

// ---------- form shapes ----------

const PIN_PATTERN = /^[1-9][0-9]{5}$/;
const HSN_PATTERN = /^[0-9]{4}(?:[0-9]{2}){0,2}$/;
const MONEY_PATTERN = /^[0-9]{1,11}(?:\.[0-9]{1,2})?$/;
const PRINTABLE_ASCII = /^[\x20-\x7E]+$/;

// Transporter IDs share the GSTIN shape.
export { isGstinShaped };

export function cleanVehicleNumber(text: string): string {
  return text.replace(/[\s-]/g, "").toUpperCase();
}

export function cleanGstin(text: string): string {
  return text.replace(/\s/g, "").toUpperCase();
}

/** A whole number of km from 1 to the cap, or null. */
export function parseDistanceKm(text: string): number | null {
  if (!/^[0-9]{1,5}$/.test(text.trim())) return null;
  const distanceKm = Number(text.trim());
  return distanceKm >= 1 && distanceKm <= MAX_DISTANCE_KM ? distanceKm : null;
}

export type GenerateTyped = {
  supplierGstin: string; recipientGstin: string; dispatchPin: string; deliveryPin: string; documentNumber: string;
  documentDate: string; goodsValueRupees: string; hsnCode: string; transportReason: string; vehicleNumber: string;
  distanceKm: string; transporterId: string;
};

/** Returns the first problem as a plain sentence, or "" when the form can make a bill. */
export function generateInputProblem(typed: GenerateTyped, persona: Persona, nowUtcMs: number): string {
  if (!isGstinShaped(typed.supplierGstin)) return "A.1 GSTIN of Supplier is 15 letters and digits, for example 29ABCDE1234F1Z5.";
  if (persona.key === "supplier" && typed.supplierGstin !== persona.id) {
    return `Signed in as the supplier, A.1 must be your own GSTIN, ${persona.id}.`;
  }
  if (typed.recipientGstin !== "URP" && !isGstinShaped(typed.recipientGstin)) {
    return "A.3 GSTIN of Recipient is 15 letters and digits, or URP for an unregistered recipient.";
  }
  if (!PIN_PATTERN.test(typed.dispatchPin)) return "A.2 Place of Dispatch is a 6-digit PIN code.";
  if (!PIN_PATTERN.test(typed.deliveryPin)) return "A.4 Place of Delivery is a 6-digit PIN code.";
  if (!isInvoiceNumberShaped(typed.documentNumber)) {
    return "A.5 Document Number is up to 32 characters.";
  }
  if (!isRealCalendarDate(typed.documentDate)) return "Choose A.6 Document Date.";
  if (typed.documentDate > indiaDateIso(nowUtcMs)) return "A.6 Document Date cannot be in the future.";
  if (!MONEY_PATTERN.test(typed.goodsValueRupees) || Number(typed.goodsValueRupees) <= 0) {
    return "A.7 Value of Goods is an amount in rupees, for example 75000 or 75000.50.";
  }
  if (!HSN_PATTERN.test(typed.hsnCode)) return "A.8 HSN Code is 4, 6 or 8 digits.";
  if (!TRANSPORT_REASONS.includes(typed.transportReason)) return "Choose A.9 Reason for Transportation.";
  if (parseDistanceKm(typed.distanceKm) === null) return `Approximate distance is a whole number of km from 1 to ${MAX_DISTANCE_KM}.`;
  if (typed.vehicleNumber && !isTruckNumberShaped(typed.vehicleNumber)) {
    return "B.1 Vehicle Number is 6 to 12 letters and digits, for example KA01AB1234.";
  }
  if (typed.transporterId && !isGstinShaped(typed.transporterId)) {
    return "The Transporter ID is 15 letters and digits, for example 29TRNSP1234A1Z7.";
  }
  if (!typed.vehicleNumber && !typed.transporterId) {
    return "Enter B.1 Vehicle Number, or name a Transporter ID so the transporter can add the vehicle later.";
  }
  return "";
}

export function vehicleInputProblem(vehicleNumber: string, reasonCode: string, remark: string): string {
  if (!isTruckNumberShaped(vehicleNumber)) return "The vehicle number is 6 to 12 letters and digits, for example KA01AB1234.";
  if (!VEHICLE_UPDATE_REASONS.some((reason) => reason.code === reasonCode)) return "Choose a reason for the vehicle update.";
  return remarkProblem(remark, reasonCode === OTHERS);
}

export function extensionInputProblem(reasonCode: string, remark: string, remainingDistanceKm: string): string {
  if (!EXTENSION_REASONS.some((reason) => reason.code === reasonCode)) return "Choose a reason for the extension.";
  const problem = remarkProblem(remark, reasonCode === "OTHER");
  if (problem) return problem;
  if (parseDistanceKm(remainingDistanceKm) === null) return `Remaining distance is a whole number of km from 1 to ${MAX_DISTANCE_KM}.`;
  return "";
}

function remarkProblem(remark: string, required: boolean): string {
  if (required && remark.length < 3) return "With Others as the reason, write a remark of 3 to 50 characters.";
  if (remark.length > 50 || (remark && !PRINTABLE_ASCII.test(remark))) return "The remark is up to 50 characters.";
  return "";
}
